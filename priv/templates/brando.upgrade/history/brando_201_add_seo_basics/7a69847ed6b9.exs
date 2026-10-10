defmodule Brando.Repo.Migrations.Brando201AddSeoBasics do
  use Ecto.Migration

  @moduledoc """
  In every site environment:

    * `Brando.Trait.Meta` adds two columns, here added to Brando's own table
      with the trait; application blueprints get them planned by
      `mix brando.gen.blueprint_migration`. `meta_canonical_url` overrides
      the page's canonical URL. `content_modified_at` moves only on
      substantive edits and is what JSON-LD `dateModified` and the sitemap's
      `lastmod` read; existing rows start from their last edit.
    * `sites_not_found_hits` keeps the 404 log (`Brando.Sites.FourOhFour`) in
      the database, as daily totals per URL and referrer, instead of only in
      memory.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:pages, prefix: prefix) do
        add :meta_canonical_url, :text
        add :content_modified_at, :utc_datetime
      end

      create table(:sites_not_found_hits, prefix: prefix) do
        add :url, :text, null: false
        add :referrer, :text, null: false, default: ""
        add :date, :date, null: false
        add :hits, :integer, null: false, default: 0
        add :last_hit_at, :utc_datetime, null: false
      end

      create unique_index(:sites_not_found_hits, [:url, :referrer, :date], prefix: prefix)
      create index(:sites_not_found_hits, [:date], prefix: prefix)
    end

    flush()

    for prefix <- prefixes() do
      execute ~s{UPDATE "#{prefix}".pages SET content_modified_at = COALESCE(edited_at, updated_at) WHERE content_modified_at IS NULL}
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:sites_not_found_hits, prefix: prefix)

      alter table(:pages, prefix: prefix) do
        remove :meta_canonical_url
        remove :content_modified_at
      end
    end
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
