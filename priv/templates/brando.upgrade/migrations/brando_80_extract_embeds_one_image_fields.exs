defmodule Brando.Repo.Migrations.ExtractEmbedsOneImageFields do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # Preserve image_series data before dropping.
    # A later migration (after galleries table is created) will use this
    # to populate galleries from the old image_series data.
    preserve_image_series_data()

    alter table(:images) do
      add :config_target, :text, default: "default"
      remove :image_series_id
    end

    drop constraint(:images_series, "imageseries_image_category_id_fkey")
    drop table(:images_categories)
    drop table(:images_series)

    flush()

    blueprints =
      Brando.Blueprint.list_blueprints() ++
        [Brando.Pages.Page, Brando.Users.User, Brando.Sites.Identity, Brando.Sites.SEO]

    for blueprint <- blueprints,
        %{type: :image, name: field_name} <- Brando.Blueprint.Assets.__assets__(blueprint) do
      image_field_query =
        from t in blueprint.__schema__(:source),
          select: %{
            id: t.id,
            image: field(t, ^field_name),
            inserted_at: t.inserted_at,
            updated_at: t.updated_at
          }

      image_fields =
        image_field_query
        |> Brando.Repo.all()
        |> Enum.reject(&(&1.image == nil))

      field_id_atom = :"#{field_name}_id"

      alter table(blueprint.__schema__(:source)) do
        add field_id_atom, references(:images, on_delete: :nilify_all)
      end

      flush()

      config_target = "image:#{inspect(blueprint)}:#{field_name}"

      for image_field <- image_fields do
        new_image = %{
          image: image_field.image,
          inserted_at: image_field.inserted_at,
          updated_at: image_field.updated_at,
          config_target: config_target
        }

        {_, [%{id: new_image_id}]} =
          Brando.Repo.insert_all("images", [new_image], returning: [:id])

        update_query =
          from t in blueprint.__schema__(:source),
            where: t.id == ^image_field.id,
            update: [set: [{^field_id_atom, ^new_image_id}]]

        Brando.repo().update_all(update_query, [])
      end

      alter table(blueprint.__schema__(:source)) do
        remove field_name
      end
    end
  end

  defp preserve_image_series_data do
    if table_exists?("images_series") do
      create table(:_legacy_image_series, primary_key: false) do
        add :id, :bigint
        add :name, :text
        add :slug, :text
        add :cfg, :jsonb
      end

      create table(:_legacy_image_series_images, primary_key: false) do
        add :image_id, :bigint
        add :image_series_id, :bigint
        add :sequence, :integer
      end

      create table(:_legacy_image_series_fks, primary_key: false) do
        add :table_name, :text
        add :entry_id, :bigint
        add :image_series_id, :bigint
      end

      flush()

      execute """
      INSERT INTO _legacy_image_series (id, name, slug, cfg)
      SELECT id, name, slug, cfg FROM images_series
      """

      execute """
      INSERT INTO _legacy_image_series_images (image_id, image_series_id, sequence)
      SELECT id, image_series_id, sequence FROM images WHERE image_series_id IS NOT NULL
      """

      # Discover all tables with image_series_id columns (except images/images_series themselves)
      fk_tables =
        Brando.repo().all(
          from(c in "columns",
            prefix: "information_schema",
            select: [:table_name],
            where: [table_schema: "public", column_name: "image_series_id"]
          )
        )
        |> Enum.map(& &1.table_name)
        |> Enum.reject(&(&1 in ["images", "images_series"] or String.starts_with?(&1, "_legacy_")))

      for fk_table <- fk_tables do
        execute """
        INSERT INTO _legacy_image_series_fks (table_name, entry_id, image_series_id)
        SELECT '#{fk_table}', id, image_series_id FROM #{fk_table} WHERE image_series_id IS NOT NULL
        """
      end
    end
  end

  defp table_exists?(table_name) do
    result =
      Brando.repo().all(
        from(t in "tables",
          prefix: "information_schema",
          select: [:table_name],
          where: [table_schema: "public", table_name: ^table_name]
        )
      )

    result != []
  end
end
