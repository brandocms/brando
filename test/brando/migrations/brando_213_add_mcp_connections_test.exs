defmodule Brando.Migrations.Brando213AddMCPConnectionsTest do
  # Runs the upgrade template inside the sandbox transaction, with the tables
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  # brando_232 adds the Figma token to mcp_settings
  @templates Enum.map(
               ~w(brando_213_add_mcp_connections.exs brando_232_add_figma_token_to_mcp_settings.exs),
               &Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/" <> &1)
             )
  @tables %{
    "mcp_settings" => Brando.MCP.Setting,
    "mcp_grants" => Brando.MCP.Grant,
    "mcp_tokens" => Brando.MCP.Token,
    "mcp_authorization_codes" => Brando.MCP.AuthorizationCode
  }

  defp run_template(template) do
    [{module, _bytecode}] = Code.compile_file(template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  defp columns(table) do
    Repo.query!(
      "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1",
      [table]
    ).rows
    |> List.flatten()
    |> Enum.sort()
  end

  test "creates the MCP tables with the columns the schemas use, with the migrations after it" do
    expected = Map.new(@tables, fn {table, _} -> {table, columns(table)} end)
    Repo.query!("DROP TABLE public.mcp_authorization_codes, public.mcp_tokens, public.mcp_grants, public.mcp_settings")

    Enum.each(@templates, &run_template/1)

    for {table, schema} <- @tables do
      assert columns(table) == expected[table]
      assert expected[table] == schema.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
      # Never cloned into an environment, nor copied into one by migrate_to_tenant
      assert Brando.Tenant.SharedTables.member?(table)
    end
  end
end
