defmodule Brando.TenantSharedTablesTest do
  # A table Brando keeps in `public` must be listed in
  # `Brando.Tenant.SharedTables`. Otherwise provisioning clones an empty copy
  # of it into every new environment, and `mix brando.migrate_to_tenant`
  # copies its rows there.
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant.SharedTables

  @root Path.expand("../..", __DIR__)

  # `create table(:name, ..., prefix: "public")`, over several lines too
  @create_public ~r/create(?:_if_not_exists)?\s+table\(\s*:?"?(\w+)"?\s*,[^)]*?prefix:\s*"public"/s

  defp pinned_schemas do
    {:ok, modules} = :application.get_key(:brando, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__schema__, 1),
        module.__schema__(:prefix) == "public",
        source = module.__schema__(:source),
        is_binary(source),
        do: {module, source}
  end

  defp tables_created_in_public do
    ["priv/templates/**/*.exs", "lib/**/*.ex"]
    |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1)))
    |> Enum.flat_map(fn file ->
      for [_, table] <- Regex.scan(@create_public, File.read!(file)), do: {Path.relative_to(file, @root), table}
    end)
  end

  test "every table a schema pins to public is shared" do
    assert pinned_schemas() != []

    assert for({module, table} <- pinned_schemas(), not SharedTables.member?(table), do: {module, table}) == []
  end

  test "every table a migration creates in public is shared" do
    created = tables_created_in_public()
    assert {"priv/templates/brando.upgrade/migrations/brando_213_add_mcp_connections.exs", "mcp_tokens"} in created

    assert for({file, table} <- created, not SharedTables.member?(table), do: {file, table}) == []
  end

  # So the copies older environments got before a table was listed here are
  # never read: a pinned schema's prefix wins over the environment's
  test "queries on a pinned schema read public inside an environment" do
    for {module, table} <- pinned_schemas() do
      query = Ecto.Query.put_query_prefix(from(row in module, select: row), "tenant_acme_staging")
      {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, BrandoIntegration.Repo, query)
      assert sql =~ ~s("public"."#{table}"), "#{inspect(module)}: #{sql}"
    end
  end
end
