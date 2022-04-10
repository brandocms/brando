defmodule Brando.Migrations.AddFiles do
  use Ecto.Migration

  def up do
    create table(:files) do
      add :title, :text
      add :mime_type, :text
      add :filesize, :integer
      add :filename, :text
      add :config_target, :text
      add :cdn, :boolean
      add :deleted_at, :utc_datetime
      timestamps()
      add :creator_id, references(:users, on_delete: :nothing)
    end
  end

  def down do
    drop table(:files)
  end
end
