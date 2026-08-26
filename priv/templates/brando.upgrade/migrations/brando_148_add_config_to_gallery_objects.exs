defmodule Brando.Repo.Migrations.AddConfigToGalleryObjects do
  use Ecto.Migration

  # `add_if_not_exists` has no inverse the `change/0` runner can infer, so
  # rolling back stopped here with "cannot reverse migration command". Spelling
  # out `up/0` and `down/0` matches the sibling migrations and keeps a full
  # forward/backward/forward rehearsal possible.
  def up do
    alter table(:galleries_gallery_objects) do
      add_if_not_exists :config, :map, default: %{}
    end
  end

  def down do
    alter table(:galleries_gallery_objects) do
      remove_if_exists :config, :map
    end
  end
end
