defmodule Brando.Notifications.JobFailures do
  @moduledoc """
  Notifies the `failed_job` routes when Oban gives a job up: it used every
  attempt, or returned `{:discard, reason}`. A job the worker cancelled is
  not a failure (a webhook delivery that failed for good cancels itself, and
  `Brando.Webhooks` notifies it on its own).

  The handler only queues a `Brando.Worker.NotificationDispatch` job, in the
  failed job's site and environment, carrying the worker, queue, attempts
  and the first line of the error. Per worker and environment, at most one
  is queued in `failed_job_interval` seconds (default 600), so a queue of
  failing jobs makes one message, not hundreds. Without tenancy every job
  counts; with it, only jobs that belong to a site environment do.

  Notification deliveries and dispatches themselves are never notified, so
  a broken route cannot notify itself in a loop.

      config :brando, Brando.Notifications, failed_jobs: false   # off
  """

  require Logger

  @handler "brando-notifications-failed-jobs"
  @ignored ["Brando.Worker.NotificationDelivery", "Brando.Worker.NotificationDispatch"]
  @error_length 200

  @doc "Attaches the Oban telemetry handler. Called from `Brando.Telemetry.attach/0`."
  def attach do
    :telemetry.attach_many(@handler, [[:oban, :job, :exception], [:oban, :job, :stop]], &__MODULE__.handle_event/4, nil)
  end

  @doc "The telemetry handler: queues a dispatch for a discarded job. Never raises."
  def handle_event(_event, _measurements, %{state: :discard, job: %Oban.Job{} = job} = meta, _config) do
    if Brando.Notifications.Routing.failed_jobs?() and job.worker not in @ignored do
      job |> args(meta) |> queue()
    end

    :ok
  rescue
    # A raising handler is detached for good
    error ->
      Logger.warning("[Brando.Notifications] Could not queue a failed-job notification: " <> Exception.message(error))
      :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  @doc "The dispatch job's arguments for a given-up `job`."
  def args(%Oban.Job{} = job, meta) do
    base = %{
      "failed_worker" => job.worker,
      "queue" => job.queue,
      "attempt" => job.attempt,
      "max_attempts" => job.max_attempts,
      "job_id" => job.id,
      "error" => error_line(meta[:error] || meta[:result])
    }

    case job.args do
      %{"tenant_prefix" => prefix} when is_binary(prefix) -> Map.put(base, "tenant_prefix", prefix)
      _ -> base
    end
  end

  defp queue(args) do
    if Map.has_key?(args, "tenant_prefix") or Brando.Tenant.mode() == :none do
      args
      |> Brando.Worker.NotificationDispatch.new(
        unique: [
          period: Brando.Notifications.Routing.failed_job_interval(),
          keys: [:failed_worker, :tenant_prefix],
          states: :all
        ]
      )
      |> Oban.insert()
    end
  end

  @doc "The first line of an error, at most 200 characters."
  def error_line(nil), do: nil

  def error_line(error) do
    text =
      cond do
        is_exception(error) -> Exception.message(error)
        is_binary(error) -> error
        true -> inspect(error)
      end

    text
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.slice(0, @error_length)
  end
end
