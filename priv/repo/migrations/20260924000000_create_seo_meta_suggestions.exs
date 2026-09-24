defmodule Brando.Repo.Migrations.Brando179CreateSeoMetaSuggestions do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_179_*`.
  """

  def change do
    create table(:seo_meta_suggestions) do
      add :schema, :string, null: false
      add :entry_id, :integer, null: false
      add :language, :string, null: false
      add :field, :string, null: false
      add :title, :string
      add :text, :text
      add :model, :string
      add :status, :string, null: false, default: "queued"
      add :error, :text
      add :generated_at, :utc_datetime
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      timestamps()
    end

    # One suggestion per entry, field and language: asking again replaces it.
    create unique_index(:seo_meta_suggestions, [:schema, :entry_id, :language, :field])
    create index(:seo_meta_suggestions, [:language, :status])
  end
end
