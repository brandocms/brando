defmodule Brando.Repo.Migrations.Brando199AddLibraryToMediaFolders do
  use Ecto.Migration

  @moduledoc """
  Marks folders that belong to the media library. A field configured with
  `hidden_folder` files its uploads in a folder with `library: false`, which
  the image, file and video lists, the alt-text page and the pickers leave
  out. Existing folders stay in the library.
  """

  def up do
    alter table(:media_folders) do
      add_if_not_exists :library, :boolean, default: true, null: false
    end
  end

  def down do
    alter table(:media_folders) do
      remove_if_exists :library, :boolean
    end
  end
end
