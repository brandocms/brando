defmodule Brando.Migrations.Brando231AddContentDefinitionAppliesTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_231_add_content_definition_applies.exs"
  @tenant "tenant_acme_staging"
  @table "content_definition_applies"

  test "creates the definition applies table in public and every environment, with the columns the schema uses" do
    # As brando_231 left it: brando_233 adds `definition`
    query!("ALTER TABLE public.content_definition_applies DROP COLUMN definition")
    expected = {column_definitions("public", @table), indexes("public", @table)}
    query!("DROP TABLE public.content_definition_applies")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert {column_definitions(schema, @table), indexes(schema, @table)} == expected
      assert references(schema, @table) == [{"applied_by_id", "public", "users"}]

      # brando_233 adds `definition`
      assert columns(schema, @table) ==
               (Brando.Content.DefinitionApply.__schema__(:fields) -- [:definition])
               |> Enum.map(&to_string/1)
               |> Enum.sort()
    end

    # Applies belong to an environment's content: never pinned to public
    refute Brando.Tenant.SharedTables.member?(@table)

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    for schema <- ["public", @tenant], do: refute(table?(schema, @table))
  end
end
