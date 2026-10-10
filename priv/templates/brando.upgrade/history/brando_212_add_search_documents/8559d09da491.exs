defmodule Brando.Repo.Migrations.Brando212AddSearchDocuments do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `search_documents`: the admin search index
  (`Brando.Search`). One row per entry and language holds the title, slug,
  meta description and the plain text of the entry's fields and blocks,
  and a `tsvector` built from them with the language's text search
  configuration (`norwegian`, `english`, or `simple` for any other).

  The table starts empty. Rebuild the index from Configuration → Utilities
  → Search index in each environment after migrating; from then on, saves
  keep it up to date.
  """

  def up do
    for prefix <- prefixes() do
      create table(:search_documents, prefix: prefix) do
        add :schema, :string, null: false
        add :entry_id, :bigint, null: false
        add :language, :string, null: false
        add :config, :string, null: false
        add :title, :text
        add :slug, :text
        add :description, :text
        add :body, :text
        add :status, :integer
        add :cover, :text
        add :document, :tsvector, null: false
        add :updated_at, :utc_datetime
        add :indexed_at, :utc_datetime_usec, null: false
      end

      create unique_index(:search_documents, [:schema, :entry_id, :language], prefix: prefix)
      create index(:search_documents, [:document], using: :gin, prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:search_documents, prefix: prefix)
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
