defmodule BrandoIntegration.Repo.Migrations.AddActivityEvents do
  use Ecto.Migration

  # Mirrors the brando_193 upgrade migration for the test schema.
  @moduledoc """
  The activity log (`Brando.Activity`): who created, changed, published,
  trashed, restored and deleted entries, and when.
  """

  def change do
    create table(:activity_events) do
      add :action, :string, null: false
      add :source, :string, null: false, default: "admin"
      add :user_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :schema, :string, null: false
      add :entry_id, :integer
      add :title, :text
      add :language, :string
      add :fields, {:array, :string}, null: false, default: []
      add :revision, :integer
      add :details, :map, null: false, default: %{}
      add :batch_id, :uuid

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:activity_events, [:inserted_at])
    create index(:activity_events, [:schema, :entry_id, :inserted_at])
    create index(:activity_events, [:user_id, :inserted_at])
  end
end
