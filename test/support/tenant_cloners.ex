defmodule Brando.TenantCloners do
  @moduledoc """
  Stands in for pg_dump inside a test's sandbox transaction, so a site can be
  provisioned with real tables: `clone_structure/2` creates the source's
  tables empty in the target, and `clone_schema/2` copies them with their rows.

      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
  """
  @behaviour Brando.Environments.StructureCloner
  @behaviour Brando.Environments.SchemaCloner

  alias Brando.Environments.Schema
  alias Brando.Tenant.SharedTables

  @impl Brando.Environments.StructureCloner
  def clone_structure(source, target) do
    for table <- tables(source),
        do: query!(~s|CREATE TABLE "#{target}"."#{table}" (LIKE "#{source}"."#{table}" INCLUDING ALL)|)

    :ok
  end

  @impl Brando.Environments.SchemaCloner
  def clone_schema(source, target) do
    :ok = Schema.create(target)
    :ok = clone_structure(source, target)

    for table <- tables(source),
        do: query!(~s|INSERT INTO "#{target}"."#{table}" SELECT * FROM "#{source}"."#{table}"|)

    :ok
  end

  defp tables(prefix) do
    %{rows: rows} = query!("SELECT tablename FROM pg_tables WHERE schemaname = $1", [prefix])
    for [table] <- rows, not SharedTables.member?(table), do: table
  end

  defp query!(sql, params \\ []), do: Brando.Repo.repo().query!(sql, params)
end
