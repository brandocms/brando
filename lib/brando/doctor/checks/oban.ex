defmodule Brando.Doctor.Checks.Oban do
  @moduledoc """
  Background jobs: the queues Oban runs, whether Brando's own queues for
  content events, webhook deliveries, the search index and notifications
  are among them,
  jobs stuck waiting or executing for more than an hour, and jobs discarded
  in the last 24 hours.

  In the admin the queues are read from the running Oban, so a paused queue
  shows. `mix brando.doctor` starts Oban without queues, so nothing runs while
  it looks; it reports the configured queues instead.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context

  @stuck_after_seconds 60 * 60
  @discarded_within_seconds 24 * 60 * 60
  @listed 20
  # Queues an application's own `config :brando, Oban` must keep: without
  # them content events, webhook deliveries, search updates and
  # notifications wait forever.
  @required ~w(content_events webhooks search_index notifications)

  @impl true
  def id, do: "oban"

  @impl true
  def label, do: dgettext("doctor", "Oban queues")

  @impl true
  def run(%Context{} = context) do
    evaluate(%{
      testing: context.oban[:testing],
      queues: queues(context),
      stuck: stuck_jobs(context),
      discarded: discarded_jobs(context),
      sweep: sweep_scheduled?(context.oban)
    })
  end

  @sweep inspect(Brando.Worker.ScheduledPublishingSweep)

  @doc """
  Whether the Oban configuration schedules `Brando.Worker.ScheduledPublishingSweep`,
  through `cron: [crontab: …]` or the cron plugin in `plugins`.
  """
  def sweep_scheduled?(oban) when is_list(oban) do
    plugins = if is_list(oban[:plugins]), do: oban[:plugins], else: []
    cron = if is_list(oban[:cron]), do: oban[:cron], else: []

    crontabs =
      [cron[:crontab]] ++
        for {plugin, opts} <- plugins, plugin in [Oban.Plugins.Cron, Oban.Cron], is_list(opts), do: opts[:crontab]

    crontabs
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.any?(fn
      {_schedule, worker} -> inspect(worker) == @sweep
      {_schedule, worker, _opts} -> inspect(worker) == @sweep
      _ -> false
    end)
  end

  def sweep_scheduled?(_oban), do: false

  @doc """
  Turns what was found into a result. `findings` has `:testing` (Oban's
  testing mode or nil), `:queues` (`[%{queue, limit, paused, live}]`), and
  `:stuck` and `:discarded` (`[%{id, worker, state, at, error}]`), and
  `:sweep`, whether the crontab has `Brando.Worker.ScheduledPublishingSweep`
  (taken as true when left out).
  """
  def evaluate(findings) do
    queues = findings.queues
    paused = Enum.filter(queues, & &1.paused)
    missing = missing_queues(findings)
    stuck = findings.stuck
    discarded = findings.discarded

    summary = summary(findings, paused)

    items =
      Enum.map(queues, &queue_item/1) ++
        Enum.map(Enum.take(stuck, @listed), &job_item/1) ++ Enum.map(Enum.take(discarded, @listed), &job_item/1)

    cond do
      queues == [] and findings.testing not in [:inline, :manual] ->
        error(dgettext("doctor", "no queues, so background jobs never run"),
          fix: dgettext("doctor", "give config :brando, Oban its queues (see Brando.Supervisor)"),
          items: items
        )

      no_sweep?(findings) ->
        warning(summary <> " · " <> dgettext("doctor", "no scheduled publishing sweep"),
          fix:
            dgettext(
              "doctor",
              "add {\"*/10 * * * *\", Brando.Worker.ScheduledPublishingSweep} to the crontab in config :brando, Oban"
            ),
          items: items
        )

      missing != [] ->
        warning(summary <> " · " <> dgettext("doctor", "no %{queues} queue", queues: Enum.join(missing, ", ")),
          fix:
            dgettext("doctor", "add %{queues} to the queues in config :brando, Oban (see Brando.Supervisor)",
              queues: Enum.map_join(missing, ", ", &"#{&1}: [limit: …]")
            ),
          items: items
        )

      paused != [] ->
        warning(summary <> " · " <> dngettext("doctor", "%{count} paused", "%{count} paused", length(paused)),
          fix: dgettext("doctor", "resume the paused queues"),
          items: items
        )

      stuck != [] ->
        warning(summary,
          fix: dgettext("doctor", "check that a node runs the queues, and the logs for the stuck workers"),
          items: items
        )

      discarded != [] ->
        warning(summary, fix: dgettext("doctor", "check the errors of the discarded jobs"), items: items)

      true ->
        ok(summary, items: items)
    end
  end

  # Without it, dates that came without jobs (environment clones, archive
  # restores) are never acted on
  defp no_sweep?(%{testing: testing}) when testing in [:inline, :manual], do: false
  defp no_sweep?(%{queues: []}), do: false
  defp no_sweep?(findings), do: Map.get(findings, :sweep, true) == false

  defp missing_queues(%{testing: testing}) when testing in [:inline, :manual], do: []
  defp missing_queues(%{queues: []}), do: []

  defp missing_queues(%{queues: queues}) do
    names = Enum.map(queues, & &1.queue)
    Enum.reject(@required, &(&1 in names))
  end

  defp summary(findings, paused) do
    discarded =
      if findings.discarded == [],
        do: [],
        else: [
          dngettext("doctor", "%{count} discarded in 24 h", "%{count} discarded in 24 h", length(findings.discarded))
        ]

    Enum.join(
      [queue_summary(findings, paused), dngettext("doctor", "%{count} stuck", "%{count} stuck", length(findings.stuck))] ++
        discarded,
      ", "
    )
  end

  defp queue_summary(%{testing: testing}, _paused) when testing in [:inline, :manual],
    do: dgettext("doctor", "testing mode, jobs run inline")

  defp queue_summary(%{queues: queues}, paused) do
    if Enum.any?(queues, & &1.live),
      do: dngettext("doctor", "%{count} running", "%{count} running", length(queues) - length(paused)),
      else: dngettext("doctor", "%{count} queue", "%{count} queues", length(queues))
  end

  defp queue_item(%{queue: queue, limit: limit, paused: paused}) do
    if paused,
      do: dgettext("doctor", "queue %{queue}, limit %{limit}, paused", queue: queue, limit: limit),
      else: dgettext("doctor", "queue %{queue}, limit %{limit}", queue: queue, limit: limit)
  end

  defp job_item(job) do
    error = job.error && ": " <> (job.error |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 160))
    "##{job.id} #{job.worker} (#{job.state}, #{format_time(job.at)})#{error}"
  end

  defp format_time(nil), do: "-"
  defp format_time(%NaiveDateTime{} = at), do: at |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
  defp format_time(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_string()

  defp queues(%Context{mode: :admin} = context) do
    case live_queues() do
      [] -> configured_queues(context)
      queues -> queues
    end
  end

  defp queues(context), do: configured_queues(context)

  defp live_queues do
    if Oban.whereis(Oban) do
      Enum.map(Oban.check_all_queues(Oban), fn state ->
        %{queue: to_string(state.queue), limit: state[:limit], paused: state[:paused] == true, live: true}
      end)
    else
      []
    end
  catch
    _kind, _reason -> []
  end

  defp configured_queues(%Context{oban: oban}) do
    case oban[:queues] do
      queues when is_list(queues) ->
        Enum.map(queues, &configured_queue/1)

      _ ->
        []
    end
  end

  defp configured_queue({queue, limit}) when is_integer(limit),
    do: %{queue: to_string(queue), limit: limit, paused: false, live: false}

  defp configured_queue({queue, opts}),
    do: %{queue: to_string(queue), limit: opts[:limit], paused: opts[:paused] == true, live: false}

  defp stuck_jobs(context) do
    cutoff = DateTime.add(context.now, -@stuck_after_seconds, :second)

    jobs(
      context,
      from(j in Oban.Job,
        where:
          (j.state == "available" and j.scheduled_at < ^cutoff) or
            (j.state == "executing" and j.attempted_at < ^cutoff),
        order_by: [asc: j.id],
        select: %{id: j.id, worker: j.worker, state: j.state, at: j.scheduled_at, error: nil}
      )
    )
  end

  defp discarded_jobs(context) do
    cutoff = DateTime.add(context.now, -@discarded_within_seconds, :second)

    jobs(
      context,
      from(j in Oban.Job,
        where: j.state == "discarded" and j.discarded_at > ^cutoff,
        order_by: [desc: j.discarded_at],
        select: %{id: j.id, worker: j.worker, state: j.state, at: j.discarded_at, errors: j.errors}
      )
    )
    |> Enum.map(fn job ->
      error = job.errors |> List.wrap() |> List.last() |> then(&(&1 && &1["error"]))
      job |> Map.delete(:errors) |> Map.put(:error, error)
    end)
  end

  # Oban's table lives in its own prefix, not the tenant's
  defp jobs(context, query) do
    Brando.Repo.repo().all(query, prefix: context.oban[:prefix] || "public")
  end
end
