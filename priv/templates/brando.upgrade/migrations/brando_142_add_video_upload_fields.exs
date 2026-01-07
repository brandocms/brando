defmodule Brando.Migrations.Videos.AddVideoUploadFields do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      add :status, :string, default: "ready"
      add :meta, :map, default: %{}
    end
  end

  def down do
    alter table(:videos) do
      remove :status
      remove :meta
    end
  end
end
