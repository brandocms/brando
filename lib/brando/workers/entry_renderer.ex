defmodule Brando.Worker.EntryRenderer do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:tenant_prefix, :schema, :entry_id], period: 5, states: :incomplete]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"entry_id" => entry_id, "schema" => schema}}) do
    schema = Module.concat([schema])
    Logger.info("==> [CRON] Rendering entry #{entry_id} for schema #{schema}")
    Brando.Content.Blocks.render_entry(schema, entry_id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
