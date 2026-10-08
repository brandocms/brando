defmodule Brando.Migrations.Brando212AddSearchDocumentsTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_212_add_search_documents.exs"
  @tenant "tenant_acme_staging"

  test "creates the search index table in public and every environment, as the schema and the indexer use it" do
    expected_columns = column_definitions("public", "search_documents")
    expected_indexes = indexes("public", "search_documents")
    query!("DROP TABLE public.search_documents")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert column_definitions(schema, "search_documents") == expected_columns
      assert indexes(schema, "search_documents") == expected_indexes
      assert Enum.any?(indexes(schema, "search_documents"), &(&1 =~ "USING gin (document)"))

      fields = Brando.Search.Document.__schema__(:fields) |> Enum.map(&to_string/1)
      assert Enum.sort(["document" | fields]) == columns(schema, "search_documents")
    end

    down(@template, version)

    for schema <- ["public", @tenant] do
      refute table?(schema, "search_documents")
    end
  end
end
