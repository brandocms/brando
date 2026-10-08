defmodule BrandoIntegration.Repo.Migrations.AddSearchDocuments do
  use Ecto.Migration

  # Mirrors the brando_212 upgrade migration for the test schema.
  @moduledoc """
  The admin search index (`Brando.Search`): one row per entry and language,
  with the text it was built from and a weighted `tsvector`.
  """

  def change do
    create table(:search_documents) do
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

    create unique_index(:search_documents, [:schema, :entry_id, :language])
    create index(:search_documents, [:document], using: :gin)
  end
end
