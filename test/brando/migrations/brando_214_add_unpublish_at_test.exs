defmodule Brando.Migrations.Brando214AddUnpublishAtTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_214_add_unpublish_at.exs"
  @tenant "tenant_acme_staging"
  @tables ~w(pages pages_fragments)

  defp definitions(schema, table),
    do: schema |> column_definitions(table) |> Enum.filter(&(elem(&1, 0) == "unpublish_at"))

  defp unpublish_indexes(schema, table), do: schema |> indexes(table) |> Enum.filter(&(&1 =~ "unpublish_at"))

  test "adds unpublish_at to pages and fragments in public and every environment, keeping their rows, and removes it" do
    expected = Map.new(@tables, &{&1, {definitions("public", &1), unpublish_indexes("public", &1)}})

    for table <- @tables, do: query!(~s(ALTER TABLE "#{table}" DROP COLUMN unpublish_at))
    create_environment(@tenant, @tables)

    pages =
      Map.new(["public", @tenant], fn schema ->
        [[id]] =
          rows("""
          INSERT INTO "#{schema}".pages (uri, language, title, template, status, inserted_at, updated_at)
          VALUES ('campaign', 'en', 'Campaign', 'default.html', 1, NOW(), NOW()) RETURNING id
          """)

        {schema, id}
      end)

    version = up(@template)

    for schema <- ["public", @tenant], table <- @tables do
      {columns, indexes} = expected[table]
      assert definitions(schema, table) == columns
      assert unpublish_indexes(schema, table) == indexes
    end

    for {schema, id} <- pages do
      assert rows(~s(SELECT title, unpublish_at FROM "#{schema}".pages WHERE id = $1), [id]) == [["Campaign", nil]]
    end

    down(@template, version)

    for schema <- ["public", @tenant], table <- @tables do
      assert definitions(schema, table) == []
      assert unpublish_indexes(schema, table) == []
    end
  end
end
