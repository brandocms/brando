defmodule Brando.Worker.ActivityPurger do
  @moduledoc """
  Removes activity events older than `Brando.Activity.retention_days/0`, in
  every active environment, and sign-in security events as old. Also prunes
  the tokens and codes of connected AI tools that nothing can use any more
  (`Brando.MCP.prune/0`).
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    purged =
      :all
      |> TenantJob.each_active_environment(fn -> Brando.Activity.purge() end)
      |> Enum.sum()

    Logger.info("==> [CRON] Deleted #{purged} activity events older than #{Brando.Activity.retention_days()} days")

    # The sign-in security log is shared by every site, so it is purged once
    security = Brando.Users.SecurityLog.purge()
    Logger.info("==> [CRON] Deleted #{security} security events older than #{Brando.Activity.retention_days()} days")

    mcp = Brando.MCP.prune()
    Logger.info("==> [CRON] Deleted #{mcp} unusable MCP tokens and codes")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
