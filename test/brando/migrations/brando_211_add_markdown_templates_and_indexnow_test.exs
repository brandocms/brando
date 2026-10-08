defmodule Brando.Migrations.Brando211AddMarkdownTemplatesAndIndexnowTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_211_add_markdown_templates_and_indexnow.exs"
  @tenant "tenant_acme_staging"

  defp markdown_code(schema),
    do: schema |> column_definitions("content_modules") |> Enum.filter(&(elem(&1, 0) == "markdown_code"))

  test "adds the Markdown template column and the IndexNow table in public and every environment, and drops them" do
    expected_markdown_code = markdown_code("public")
    expected_indexnow = {column_definitions("public", "sites_indexnow"), indexes("public", "sites_indexnow")}
    query!("ALTER TABLE content_modules DROP COLUMN markdown_code")
    query!("DROP TABLE sites_indexnow")
    create_environment(@tenant, ["content_modules"])

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert markdown_code(schema) == expected_markdown_code
      assert {column_definitions(schema, "sites_indexnow"), indexes(schema, "sites_indexnow")} == expected_indexnow

      assert columns(schema, "sites_indexnow") ==
               Brando.IndexNow.Settings.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    down(@template, version)

    for schema <- ["public", @tenant] do
      assert markdown_code(schema) == []
      refute table?(schema, "sites_indexnow")
    end
  end
end
