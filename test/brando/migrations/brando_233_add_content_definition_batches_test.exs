defmodule Brando.Migrations.Brando233AddContentDefinitionBatchesTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_233_add_content_definition_batches.exs"
  @tenant "tenant_acme_staging"
  @table "content_definition_batches"

  test "creates the definition batches table in public and every environment, with the columns the schema uses" do
    expected = {column_definitions("public", @table), indexes("public", @table)}
    applies = column_definitions("public", "content_definition_applies")
    query!("DROP TABLE public.content_definition_batches")
    query!("ALTER TABLE public.content_definition_applies DROP COLUMN definition")
    create_environment(@tenant)
    # brando_231 ran before it
    up("brando_231_add_content_definition_applies.exs")

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

    # `definition` for each apply row
    assert column_definitions("public", "content_definition_applies") == applies
    assert "definition" in columns(@tenant, "content_definition_applies")

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    for schema <- ["public", @tenant] do
      refute table?(schema, @table)
      refute "definition" in columns(schema, "content_definition_applies")
    end
  end
end
