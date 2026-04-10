defmodule Brando.Migrations.Videos.AddMutedToVideos do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      add_if_not_exists :muted, :boolean
    end
  end

  def down do
    alter table(:videos) do
      remove_if_exists :muted, :boolean
    end
  end
end
