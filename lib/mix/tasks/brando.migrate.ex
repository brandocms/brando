defmodule Mix.Tasks.Brando.Migrate do
  @shortdoc "Runs public or tenant migrations"

  @moduledoc """
  Runs public migrations by default and tenant migrations when scoped:

      mix brando.migrate
      mix brando.migrate --tenants
      mix brando.migrate --site acme

  Public migrations must be current before tenant migrations are run, because
  tenant discovery reads the public site/environment registry.
  """

  use Mix.Task

  @switches [tenants: :boolean, site: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or positional != [] do
      Mix.raise("Invalid arguments: #{inspect(positional ++ invalid)}")
    end

    if opts[:tenants] and opts[:site] do
      Mix.raise("Choose either --tenants or --site, not both")
    end

    cond do
      opts[:tenants] ->
        Mix.Task.run("app.start")
        Brando.Environments.migrate_all() |> report_tenant_result()

      is_binary(opts[:site]) ->
        Mix.Task.run("app.start")

        opts[:site]
        |> Brando.Tenant.Registry.get_site_by_key()
        |> case do
          nil -> Mix.raise("Unknown site key: #{opts[:site]}")
          site -> Brando.Environments.migrate_site(site) |> report_tenant_result()
        end

      true ->
        Mix.Task.run("ecto.migrate")
    end
  end

  defp report_tenant_result({:ok, migrated}) do
    Mix.shell().info("Migrated #{length(migrated)} tenant environment(s).")
  end

  defp report_tenant_result({:error, reason}) do
    Mix.raise("Tenant migration failed: #{inspect(reason)}")
  end
end
