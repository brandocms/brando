defmodule Brando.Migrations.Brando253AddContentDefinitionDropsTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_253_add_content_definition_drops.exs"
  @tenant "tenant_acme_staging"
  @table "content_definition_drops"

  test "creates the dropped rows table in public and every environment, with the columns the schema uses" do
    expected = {column_definitions("public", @table), indexes("public", @table)}
    query!("DROP TABLE public.content_definition_drops")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert {column_definitions(schema, @table), indexes(schema, @table)} == expected

      assert columns(schema, @table) ==
               Brando.Content.DefinitionDrop.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    # The rows belong to an environment's content: never pinned to public
    refute Brando.Tenant.SharedTables.member?(@table)

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    for schema <- ["public", @tenant], do: refute(table?(schema, @table))
  end
end
