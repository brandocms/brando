defmodule Brando.Migrations.Brando232AddContentDefinitionBatchesTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_232_add_content_definition_batches.exs"
  @tenant "tenant_acme_staging"
  @table "content_definition_batches"

  test "creates the definition batches table in public and every environment, with the columns the schema uses" do
    expected = {column_definitions("public", @table), indexes("public", @table)}
    query!("DROP TABLE public.content_definition_batches")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert {column_definitions(schema, @table), indexes(schema, @table)} == expected
      assert references(schema, @table) == [
               {"applied_by_id", "public", "users"},
               {"confirmed_by_id", "public", "users"},
               {"reverted_by_id", "public", "users"}
             ]

      assert columns(schema, @table) ==
               Brando.Content.DefinitionBatch.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    # Batches belong to an environment's content: never pinned to public
    refute Brando.Tenant.SharedTables.member?(@table)

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    for schema <- ["public", @tenant], do: refute(table?(schema, @table))
  end
end
