defmodule Mix.Tasks.Brando.Authorization.Migrate do
  @shortdoc "Reports or migrates legacy roles to scoped authorization groups"
  @moduledoc """
  Run `mix brando.authorization.migrate --dry-run` to inspect the migration, then
  `mix brando.authorization.migrate` to seed groups and backfill memberships.

  Review custom application rules before switching to:

      config :brando, authorization_mode: :groups

  The two resolvers are never combined. Keep legacy mode until the report and
  application policies have been reviewed. Re-running preserves edited grants.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, invalid} = OptionParser.parse(args, strict: [dry_run: :boolean])
    if invalid != [], do: Mix.raise("Unknown options: #{inspect(invalid)}")
    Mix.Task.run("app.start")

    case Brando.Authorization.Migration.run(opts) do
      {:ok, report} -> Mix.shell().info(inspect(report, pretty: true))
      {:error, reason} -> Mix.raise("Authorization migration failed: #{inspect(reason)}")
    end
  end
end
