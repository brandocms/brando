defmodule Brando.Repo.Migrations.FlattenImagesImageEmbed do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:images) do
      add :title, :text
      add :credits, :text
      add :alt, :text
      add :formats, {:array, :string}
      add :path, :text
      add :width, :integer
      add :height, :integer
      add :sizes, :map
      add :cdn, :boolean, default: false
      add :dominant_color, :text
      add :focal, :jsonb
    end

    flush()

    query = from t in "images", select: %{id: t.id, image: t.image, config_target: t.config_target}
    images = Brando.repo().all(query)

    for image <- images do
      {:ok, cfg} = Brando.Images.get_config_for(image)

      processed_formats =
        if image.image["formats"] do
          image.image["formats"]
        else
          image.image["path"]
          |> Brando.Images.get_processed_formats(cfg.formats)
          |> Enum.map(&to_string/1)
        end

      update_query = from t in "images", where: t.id == ^image.id, update: [set: [
        title: ^image.image["title"],
        credits: ^image.image["credits"],
        alt: ^image.image["alt"],
        formats: ^processed_formats,
        path: ^image.image["path"],
        width: ^image.image["width"],
        height: ^image.image["height"],
        sizes: ^image.image["sizes"],
        cdn: ^image.image["cdn"],
        dominant_color: ^image.image["dominant_color"],
        focal: ^image.image["focal"]
      ]]

      Brando.repo().update_all(update_query, [])
    end

    alter table(:images) do
      remove :image
    end
  end
end
