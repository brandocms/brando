defmodule Brando.Worker.EntryRenderer do
  @moduledoc false
  # Renders of an entry queued within 5 seconds and not started coalesce
  # (`Brando.Content.RenderQueue.enqueue/1`). One running, or waiting to
  # retry, gets another after it: it may have read the entry before the write.
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:tenant_prefix, :schema, :entry_id], period: 5, states: [:available, :scheduled]]

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @timeout :timer.seconds(30)

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"entry_id" => entry_id, "schema" => schema} = args} = job) do
    case rendering_before(job) do
      nil ->
        # Queued after writes this node may not have heard of yet
        Brando.Cache.ensure_fresh(args)
        schema = Module.concat([schema])
        Logger.info("==> [CRON] Rendering entry #{entry_id} for schema #{schema}")
        Brando.Content.Blocks.render_entry(schema, entry_id)

      earlier ->
        # This one stores last: with what the other one's queuing nodes had
        # heard of too
        take_tokens(job, earlier)
        {:snooze, 1}
    end
  end

  # A render of the entry that started before this one, on any node, may
  # have read the entry before the write that queued this one, and store
  # after this one. This one renders once it has stored. Each render stamps
  # its start in its job's meta with the database's clock, before it looks:
  # not the job's id, since a job queued in a transaction has the lower id
  # but may start later, and not Oban's `attempted_at`, read from the
  # fetching node's clock before the fetch has a connection. A render that
  # stamps after this one has looked reads after it, so after the write.
  # A stamp counts for the attempt that made it only. Waits no longer than
  # the other one's timeout, which a node that went down leaves executing
  # until `Oban.Lifeline` rescues it.
  defp rendering_before(%Oban.Job{id: id, worker: worker, args: args}) when is_integer(id) do
    case stamp_start(id) do
      nil ->
        nil

      started ->
        since = started - (@timeout + :timer.seconds(5)) * 1000
        entry = Map.take(args, ["tenant_prefix", "schema", "entry_id"])

        query =
          from j in Oban.Job,
            where:
              j.worker == ^worker and j.state == "executing" and j.id != ^id and
                fragment("?->>'render_attempted_at' IS NOT DISTINCT FROM ?::text", j.meta, j.attempted_at) and
                fragment("(?->>'render_started')::bigint", j.meta) > ^since and
                (fragment("(?->>'render_started')::bigint", j.meta) < ^started or
                   (fragment("(?->>'render_started')::bigint", j.meta) == ^started and j.id < ^id)) and
                fragment("? @> ?", j.args, type(^entry, :map)),
            select: j.args,
            limit: 1

        Brando.Repo.one(query)
    end
  end

  defp rendering_before(_job), do: nil

  # Microseconds, by the database's clock. Nil when the job has no row: run
  # by `Oban.Testing.perform_job/3`, say.
  defp stamp_start(id) do
    query =
      from j in Oban.Job,
        where: j.id == ^id,
        update: [
          set: [
            meta:
              fragment(
                """
                ? || jsonb_build_object(
                  'render_started', (extract(epoch from clock_timestamp()) * 1000000)::bigint,
                  'render_attempted_at', ?::text
                )
                """,
                j.meta,
                j.attempted_at
              )
          ]
        ],
        select: fragment("(?->>'render_started')::bigint", j.meta)

    case Brando.Repo.update_all(query, []) do
      {1, [started]} -> started
      {0, _} -> nil
    end
  end

  defp take_tokens(%Oban.Job{id: id, args: args}, earlier) do
    merged = Brando.Cache.Freshness.merge(args, earlier)
    if merged != args, do: Brando.Repo.update_all(from(j in Oban.Job, where: j.id == ^id), set: [args: merged])
  end

  @impl Oban.Worker
  def timeout(_job), do: @timeout
end
