defmodule Brando.Repo.Migrations.AddCreatorSoftDeletePalettes do
  use Ecto.Migration

  def change do
    alter table(:content_palettes) do
      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nothing)
    end
  end
end
