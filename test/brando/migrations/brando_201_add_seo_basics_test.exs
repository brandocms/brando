defmodule Brando.Migrations.Brando201AddSeoBasicsTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/brando_201_add_seo_basics.exs")
  @tenant "tenant_acme_production"

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp columns(schema, table) do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2"
    |> rows([schema, table])
    |> List.flatten()
  end

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "adds the meta columns and the 404 table in public and every tenant schema, backfilling from the last edit" do
    Repo.query!("ALTER TABLE pages DROP COLUMN meta_canonical_url, DROP COLUMN content_modified_at")
    Repo.query!("DROP TABLE sites_not_found_hits")
    Repo.query!(~s(CREATE SCHEMA "#{@tenant}"))
    Repo.query!(~s{CREATE TABLE "#{@tenant}".pages (LIKE public.pages INCLUDING DEFAULTS)})

    [[edited_id]] =
      rows("""
      INSERT INTO pages (uri, language, title, template, edited_at, inserted_at, updated_at)
      VALUES ('edited', 'en', 'Edited', 'default.html', '2026-01-01 10:00:00', '2025-01-01 10:00:00', '2026-05-01 10:00:00')
      RETURNING id
      """)

    [[untouched_id]] =
      rows("""
      INSERT INTO pages (uri, language, title, template, inserted_at, updated_at)
      VALUES ('untouched', 'en', 'Untouched', 'default.html', '2025-01-01 10:00:00', '2025-02-01 10:00:00')
      RETURNING id
      """)

    run_template()

    for schema <- ["public", @tenant] do
      assert "meta_canonical_url" in columns(schema, "pages")
      assert "content_modified_at" in columns(schema, "pages")
      assert "hits" in columns(schema, "sites_not_found_hits")
    end

    assert rows("SELECT content_modified_at FROM pages WHERE id = $1", [edited_id]) == [[~N[2026-01-01 10:00:00]]]
    assert rows("SELECT content_modified_at FROM pages WHERE id = $1", [untouched_id]) == [[~N[2025-02-01 10:00:00]]]
  end
end
