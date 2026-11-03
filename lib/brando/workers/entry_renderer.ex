defmodule Brando.Worker.EntryRenderer do
  @moduledoc false
  # Renders of an entry queued within 5 seconds and not started coalesce
  # (`Brando.Content.RenderQueue.enqueue/1`). One running, or waiting to
  # retry, gets another after it: it may have read the entry before the write.
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:tenant_prefix, :schema, :entry_id], period: 5, states: [:available, :scheduled]]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"entry_id" => entry_id, "schema" => schema} = args}) do
    # Queued after writes this node may not have heard of yet
    Brando.Cache.ensure_fresh(args)
    schema = Module.concat([schema])
    Logger.info("==> [CRON] Rendering entry #{entry_id} for schema #{schema}")
    Brando.Content.Blocks.render_entry(schema, entry_id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
