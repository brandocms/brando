defmodule Brando.Repo.Migrations.Brando201AddSeoBasics do
  use Ecto.Migration

  @moduledoc """
  `Brando.Trait.Meta` adds two columns, here added to Brando's own table with
  the trait; application blueprints get them planned by
  `mix brando.gen.blueprint_migration`:

    * `meta_canonical_url` overrides the page's canonical URL.
    * `content_modified_at` moves only on substantive edits, and is what
      JSON-LD `dateModified` and the sitemap's `lastmod` read. Existing rows
      start from their last edit.
  """

  def up do
    alter table(:pages) do
      add :meta_canonical_url, :text
      add :content_modified_at, :utc_datetime
    end

    flush()

    execute "UPDATE pages SET content_modified_at = COALESCE(edited_at, updated_at) WHERE content_modified_at IS NULL"
  end

  def down do
    alter table(:pages) do
      remove :meta_canonical_url
      remove :content_modified_at
    end
  end
end
