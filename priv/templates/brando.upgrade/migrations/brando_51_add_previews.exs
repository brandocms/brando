defmodule Brando.Repo.Migrations.AddPreviews do
  use Ecto.Migration

  def change do
    create table(:sites_previews) do
      add :preview_key, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :html, :binary
      add :creator_id, references(:users_users, on_delete: :nilify_all)
      timestamps()
    end

    create index(:sites_previews, [:preview_key])
  end
end
