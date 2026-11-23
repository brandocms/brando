defmodule BrandoIntegration.Repo.Migrations.AddImagesSources do
  use Ecto.Migration

  # Mirrors the brando_247 upgrade migration for the test schema.
  @moduledoc """
  Where an image's file came from (`Brando.Images.Source`): a picture of
  another service, by that service's reference to it.
  """

  def change do
    create table(:images_sources) do
      add :image_id, references(:images, on_delete: :delete_all), null: false
      add :source, :text, null: false
      add :ref, :text, null: false
      add :variant, :text
      add :config_target, :text
      timestamps(updated_at: false)
    end

    create unique_index(:images_sources, [:image_id, :source, :ref, "coalesce(variant, '')"],
             name: :images_sources_image_id_source_ref_variant_index
           )

    create index(:images_sources, [:source, :ref])
  end
end
