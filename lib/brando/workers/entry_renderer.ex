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
    if rendering_before?(job) do
      {:snooze, 1}
    else
      # Queued after writes this node may not have heard of yet
      Brando.Cache.ensure_fresh(args)
      schema = Module.concat([schema])
      Logger.info("==> [CRON] Rendering entry #{entry_id} for schema #{schema}")
      Brando.Content.Blocks.render_entry(schema, entry_id)
    end
  end

  # A render of the entry that started before this one, on any node, may
  # have read the entry before the write that queued this one, and store
  # after this one. This one renders once it has stored. Ordered by start,
  # not id: a job queued in a transaction has the lower id but may start
  # later. Start times are each node's clock, so they assume clocks in step.
  # Waits no longer than the other one's timeout, which a node that went
  # down leaves executing until `Oban.Lifeline` rescues it.
  defp rendering_before?(%Oban.Job{id: id, worker: worker, args: args} = job) when is_integer(id) do
    started = job.attempted_at || DateTime.utc_now()
    since = DateTime.add(DateTime.utc_now(), -(@timeout + :timer.seconds(5)), :millisecond)
    entry = Map.take(args, ["tenant_prefix", "schema", "entry_id"])

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state == "executing" and j.id != ^id and j.attempted_at > ^since and
            (j.attempted_at < ^started or (j.attempted_at == ^started and j.id < ^id)) and
            fragment("? @> ?", j.args, type(^entry, :map)),
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  defp rendering_before?(_job), do: false

  @impl Oban.Worker
  def timeout(_job), do: @timeout
end
