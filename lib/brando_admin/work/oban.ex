defmodule BrandoAdmin.Work.Oban do
  @moduledoc """
  Reports Oban jobs marked with `BrandoAdmin.Work.track/4` as work.

  | Oban event | Work |
  | --- | --- |
  | inserted, to run now | `start/4` with `queued` (or `running`), when given |
  | started (first attempt) | `update/4` with `running` |
  | failed with attempts left, snoozed, started again | kept from timing out, if it still runs |
  | succeeded | `finish/3` with `done`, unless `finish: false` |
  | cancelled, discarded | `fail/3` with `failed` |

  A step job (`step: true`) only `advance/3`s its work when it succeeds
  (`:ok`) or ends without succeeding (`:error`).

  An insert that hit a unique conflict starts nothing: no job of ours runs.
  """
  alias BrandoAdmin.Work

  require Logger

  @handler "brando-admin-work"
  @events [
    [:oban, :engine, :insert_job, :stop],
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  @doc "Attaches the telemetry handler. Called from `Brando.Telemetry.attach/0`."
  def attach, do: :telemetry.attach_many(@handler, @events, &__MODULE__.handle_event/4, nil)

  @doc "The telemetry handler. Never raises."
  def handle_event(event, _measurements, %{job: %Oban.Job{meta: %{"brando_work" => work}} = job} = meta, _config) do
    handle(event, meta, job, work)
    :ok
  rescue
    # A raising handler is detached for good
    error ->
      Logger.warning("[BrandoAdmin.Work] Could not report a job: " <> Exception.message(error))
      :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  defp handle([:oban, :engine, :insert_job, :stop], _meta, %Oban.Job{} = job, %{"step" => false} = work) do
    message = work["queued"] || work["running"]

    if (message && not job.conflict?) and job.state == "available" do
      report(work, :start, %{message: message})
    end
  end

  # A retry, or a run after a snooze (which gives its attempt back), only
  # keeps work running: the run before may have ended it
  defp handle([:oban, :job, :start], _meta, %Oban.Job{attempt: 1, meta: meta}, %{"step" => false} = work)
       when not is_map_key(meta, "snoozed") do
    report(work, :update, %{message: work["running"]})
  end

  defp handle([:oban, :job, :start], _meta, _job, %{"step" => false} = work), do: still_running(work)

  defp handle([:oban, :job, :stop], %{state: state}, _job, work) do
    case state do
      :success -> ended(work, :ok)
      state when state in [:cancelled, :discard] -> ended(work, :error)
      :snoozed -> still_running(work)
      _ -> :ok
    end
  end

  defp handle([:oban, :job, :exception], %{state: state}, _job, work) do
    case state do
      :discard -> ended(work, :error)
      _retrying -> still_running(work)
    end
  end

  defp handle(_event, _meta, _job, _work), do: :ok

  defp ended(%{"step" => true} = work, result), do: report(work, :advance, %{result: result})
  defp ended(%{"finish" => false}, :ok), do: :ok
  defp ended(work, :ok), do: report(work, :finish, %{message: work["done"]})
  defp ended(work, :error), do: report(work, :fail, %{message: work["failed"]})

  defp still_running(%{"step" => true}), do: :ok
  defp still_running(work), do: report(work, :touch, %{})

  defp report(work, op, attrs) do
    attrs =
      attrs
      |> Map.put(:prefix, work["prefix"])
      |> put_option(:timeout, work["timeout"])
      |> put_option(:toast, if(work["toast"] == "always", do: :always))

    Work.report(work["user_id"], work["key"], op, attrs)
  end

  defp put_option(attrs, _key, nil), do: attrs
  defp put_option(attrs, key, value), do: Map.put(attrs, key, value)
end
