defmodule Brando.Repo.Migrations.Brando248AddImagesSources do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `images_sources`: where an image's file came
  from (`Brando.Images.Source`), a picture of another service by that
  service's reference to it. `brando_figma_import_images` records the Figma
  picture of each image it stores or reuses, and `brando_figma_read_frame`
  names the library image a layer shows from it. Empty until the next
  import: frames imported before match after it.
  """

  def up do
    for prefix <- prefixes(), table?(prefix, "images") do
      create_if_not_exists table(:images_sources, prefix: prefix) do
        add :image_id, references(:images, on_delete: :delete_all, prefix: prefix), null: false
        add :source, :text, null: false
        add :ref, :text, null: false
        add :variant, :text
        add :config_target, :text
        timestamps(updated_at: false)
      end

      create_if_not_exists unique_index(
                             :images_sources,
                             [:image_id, :source, :ref, "coalesce(variant, '')"],
                             name: :images_sources_image_id_source_ref_variant_index,
                             prefix: prefix
                           )

      create_if_not_exists index(:images_sources, [:source, :ref], prefix: prefix)
    end
  end

  # What an import recorded: importing the frame again records it anew
  def down do
    for prefix <- prefixes(), do: drop_if_exists(table(:images_sources, prefix: prefix))
  end

  defp table?(prefix, table) do
    %{rows: [[name]]} = repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".#{table})])
    not is_nil(name)
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
