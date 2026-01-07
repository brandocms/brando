defmodule Brando.Migrations.Videos.AddVideoDurationField do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      add :duration, :string
    end
  end

  def down do
    alter table(:videos) do
      remove :duration
    end
  end
end
