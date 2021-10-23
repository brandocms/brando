defmodule Brando.Repo.Migrations.ExtractEmbedsOneImageFields do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:images) do
      add :config_target, :text, default: "default"
      remove :image_series_id
    end

    drop constraint(:images_series, "imageseries_image_category_id_fkey")
    drop table(:images_categories)
    drop table(:images_series)

    flush()

    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Users.User, Brando.Sites.Identity, Brando.Sites.SEO]

    for blueprint <- blueprints,
        %{type: :image, name: field_name} = image <- blueprint.__assets__() do

      image_field_query =
        from t in blueprint.__schema__(:source),
          select: %{id: t.id, image: field(t, ^field_name), inserted_at: t.inserted_at, updated_at: t.updated_at}

      image_fields =
        image_field_query
        |> Brando.repo().all()
        |> Enum.reject(&(&1.image == nil))

      field_id_atom = String.to_atom("#{field_name}_id")

      alter table(blueprint.__schema__(:source)) do
        add field_id_atom, references(:images, on_delete: :nilify_all)
      end

      flush()

      config_target = "image:#{inspect blueprint}:#{field_name}"

      for image_field <- image_fields do
        new_image = %{
          image: image_field.image,
          inserted_at: image_field.inserted_at,
          updated_at: image_field.updated_at,
          config_target: config_target
        }

        {_, [%{id: new_image_id}]} = Brando.repo().insert_all("images", [new_image], returning: [:id])

        update_query = from t in blueprint.__schema__(:source),
          where: t.id == ^image_field.id,
          update: [set: [{^field_id_atom, ^new_image_id}]]

        Brando.repo.update_all(update_query, [])
      end

      alter table(blueprint.__schema__(:source)) do
        remove field_name
      end
    end
  end
end
