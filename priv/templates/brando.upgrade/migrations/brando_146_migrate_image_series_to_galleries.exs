defmodule Brando.Repo.Migrations.MigrateImageSeriesToGalleries do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Migrates legacy image_series data (preserved by migration 80) into the
  new galleries system. For each blueprint with a :gallery asset:

  1. Adds a gallery_id FK column to the schema table
  2. Creates a gallery per old image_series with correct config_target
  3. Links images via galleries_gallery_objects
  4. Sets config_target on both gallery and its images
  5. Removes old image_series_id column
  6. Cleans up legacy tables
  """

  def up do
    unless table_exists?("_legacy_image_series_fks") do
      :ok
    else
      migrate_image_series_to_galleries()

      drop table(:_legacy_image_series_fks)
      drop table(:_legacy_image_series_images)
      drop table(:_legacy_image_series)
    end
  end

  def down do
    :ok
  end

  defp migrate_image_series_to_galleries do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    legacy_fks =
      Brando.repo().all(
        from(f in "_legacy_image_series_fks",
          select: %{
            table_name: f.table_name,
            entry_id: f.entry_id,
            image_series_id: f.image_series_id
          }
        )
      )

    legacy_images =
      Brando.repo().all(
        from(i in "_legacy_image_series_images",
          select: %{
            image_id: i.image_id,
            image_series_id: i.image_series_id,
            sequence: i.sequence
          }
        )
      )

    images_by_series = Enum.group_by(legacy_images, & &1.image_series_id)
    fks_by_table = Enum.group_by(legacy_fks, & &1.table_name)

    # Find blueprints with gallery assets
    blueprints = Brando.Blueprint.list_blueprints()

    gallery_blueprints =
      for blueprint <- blueprints,
          %{type: :gallery, name: gallery_field} <- Brando.Blueprint.Assets.__assets__(blueprint) do
        {blueprint, blueprint.__schema__(:source), gallery_field}
      end

    for {blueprint, table_name, gallery_field} <- gallery_blueprints do
      table_fks = Map.get(fks_by_table, table_name, [])

      if table_fks != [] do
        config_target = "gallery:#{inspect(blueprint)}:#{gallery_field}"
        gallery_id_col = :"#{gallery_field}_id"

        # Add gallery_id column if missing
        unless column_exists?(table_name, to_string(gallery_id_col)) do
          alter table(table_name) do
            add gallery_id_col, references(:galleries, on_delete: :nilify_all)
          end

          flush()
        end

        # Create a gallery per unique image_series_id
        series_ids = table_fks |> Enum.map(& &1.image_series_id) |> Enum.uniq()

        series_to_gallery =
          for series_id <- series_ids, into: %{} do
            {_, [%{id: gallery_id}]} =
              Brando.repo().insert_all(
                "galleries",
                [%{config_target: config_target, inserted_at: now, updated_at: now}],
                returning: [:id]
              )

            # Link images to gallery
            series_images = Map.get(images_by_series, series_id, [])

            gallery_objects =
              Enum.map(series_images, fn img ->
                %{
                  gallery_id: gallery_id,
                  image_id: img.image_id,
                  sequence: img.sequence || 0,
                  inserted_at: now,
                  updated_at: now
                }
              end)

            if gallery_objects != [] do
              Brando.repo().insert_all("galleries_gallery_objects", gallery_objects)
            end

            # Set config_target on gallery images
            image_ids = Enum.map(series_images, & &1.image_id)

            if image_ids != [] do
              from(i in "images", where: i.id in ^image_ids)
              |> Brando.repo().update_all(set: [config_target: config_target])
            end

            {series_id, gallery_id}
          end

        # Set gallery_id on entries
        for fk <- table_fks do
          gallery_id = Map.get(series_to_gallery, fk.image_series_id)

          if gallery_id do
            from(t in table_name, where: t.id == ^fk.entry_id)
            |> Brando.repo().update_all(set: [{gallery_id_col, gallery_id}])
          end
        end
      end
    end

    # Remove old image_series_id columns
    affected_tables =
      legacy_fks
      |> Enum.map(& &1.table_name)
      |> Enum.uniq()

    for table_name <- affected_tables do
      if column_exists?(table_name, "image_series_id") do
        alter table(table_name) do
          remove :image_series_id
        end
      end
    end
  end

  defp table_exists?(name) do
    Brando.repo().all(
      from(t in "tables",
        prefix: "information_schema",
        select: [:table_name],
        where: [table_schema: "public", table_name: ^name]
      )
    ) != []
  end

  defp column_exists?(table_name, column_name) do
    Brando.repo().all(
      from(c in "columns",
        prefix: "information_schema",
        select: [:column_name],
        where: [table_schema: "public", table_name: ^table_name, column_name: ^column_name]
      )
    ) != []
  end
end
