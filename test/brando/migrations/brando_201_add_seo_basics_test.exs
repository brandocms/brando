defmodule Brando.Migrations.Brando201AddSeoBasicsTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_201_add_seo_basics.exs"
  @tenant "tenant_acme_staging"

  defp insert_pages(schema) do
    [[edited_id]] =
      rows("""
      INSERT INTO "#{schema}".pages (uri, language, title, template, edited_at, inserted_at, updated_at)
      VALUES ('edited', 'en', 'Edited', 'default.html', '2026-01-01 10:00:00', '2025-01-01 10:00:00', '2026-05-01 10:00:00')
      RETURNING id
      """)

    [[untouched_id]] =
      rows("""
      INSERT INTO "#{schema}".pages (uri, language, title, template, inserted_at, updated_at)
      VALUES ('untouched', 'en', 'Untouched', 'default.html', '2025-01-01 10:00:00', '2025-02-01 10:00:00')
      RETURNING id
      """)

    {edited_id, untouched_id}
  end

  defp content_modified_at(schema, id),
    do: rows(~s(SELECT content_modified_at FROM "#{schema}".pages WHERE id = $1), [id])

  test "adds the meta columns and the 404 table in public and every environment, backfilling from the last edit" do
    hits_columns = column_definitions("public", "sites_not_found_hits")
    hits_indexes = indexes("public", "sites_not_found_hits")

    query!("ALTER TABLE pages DROP COLUMN meta_canonical_url, DROP COLUMN content_modified_at")
    query!("DROP TABLE sites_not_found_hits")
    create_environment(@tenant, ["pages"])

    pages = Map.new(["public", @tenant], &{&1, insert_pages(&1)})

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert ~w(meta_canonical_url content_modified_at) -- columns(schema, "pages") == []
      assert column_definitions(schema, "sites_not_found_hits") == hits_columns
      assert indexes(schema, "sites_not_found_hits") == hits_indexes

      {edited_id, untouched_id} = pages[schema]
      assert content_modified_at(schema, edited_id) == [[~N[2026-01-01 10:00:00]]]
      assert content_modified_at(schema, untouched_id) == [[~N[2025-02-01 10:00:00]]]
    end

    down(@template, version)

    for schema <- ["public", @tenant] do
      refute table?(schema, "sites_not_found_hits")
      refute "meta_canonical_url" in columns(schema, "pages")
      refute "content_modified_at" in columns(schema, "pages")

      {edited_id, untouched_id} = pages[schema]
      assert rows(~s{SELECT count(*) FROM "#{schema}".pages WHERE id = ANY($1)}, [[edited_id, untouched_id]]) == [[2]]
    end
  end
end
