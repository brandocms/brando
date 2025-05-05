defmodule Brando.Blueprint.Assets do
  @moduledoc """
  WIP

  ## Asset types


  ### File

  #### Example

      assets do
        asset :pdf, :file, required: true, cfg: %{
          allowed_mimetypes: ["application/pdf"],
          random_filename: false,
          upload_path: Path.join("files", "pdfs"),
          force_filename: "a_single_file.pdf",
          overwrite: true,
          size_limit: 16_000_000
        }
      end

  ### Gallery

  #### Example

      asset :project_gallery, :gallery,
        required: true,
        cfg: %{
          upload_path: Path.join(["images", "projects", "gallery"]),
          sizes: %{
            "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
            "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true},
            "small" => %{"size" => "700", "quality" => 70},
            "medium" => %{"size" => "1100", "quality" => 70},
            "large" => %{"size" => "1700", "quality" => 70},
            "xlarge" => %{"size" => "2100", "quality" => 70}
          },
          srcset: %{
            default: [
              {"small", "700w"},
              {"medium", "1100w"},
              {"large", "1700w"},
              {"xlarge", "2100w"}
            ]
          }
        }

  ### Image

  #### Example

      asset :cover, :image,
        required: true,
        cfg: %{
          upload_path: Path.join(["images", "projects", "covers"]),
          sizes: %{
            "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
            "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true},
            "small" => %{"size" => "700", "quality" => 70},
            "medium" => %{"size" => "1100", "quality" => 70},
            "large" => %{"size" => "1700", "quality" => 70},
            "xlarge" => %{"size" => "2100", "quality" => 70}
          },
          srcset: %{
            default: [
              {"small", "700w"},
              {"medium", "1100w"},
              {"large", "1700w"},
              {"xlarge", "2100w"}
            ]
          }
        }
  """
  import Ecto.Query

  alias Brando.Blueprint
  alias Ecto.Changeset
  alias Spark.Dsl.Extension

  def __assets__(module) do
    Extension.get_entities(module, [:assets])
  end

  def __asset__(module, name) do
    Extension.get_persisted(module, {:asset, name})
  end

  def __asset_opts__(module, name) do
    module
    |> __asset__(name)
    |> Map.get(:opts, [])
  end

  def run_cast_assets(changeset, assets, user) do
    Enum.reduce(assets, changeset, fn rel, cs -> run_cast_asset(rel, cs, user) end)
  end

  ##
  ## image is belongs_to Image
  def run_cast_asset(%{type: :image, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## file is belongs_to File
  def run_cast_asset(%{type: :file, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## video is belongs_to Video
  def run_cast_asset(%{type: :video, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## embeds_many
  def run_cast_asset(%{type: :embeds_many, name: name, opts: opts}, changeset, _user) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        Changeset.put_embed(changeset, name, [])

      _ ->
        Changeset.cast_embed(
          changeset,
          name,
          Blueprint.Utils.to_changeset_opts(:embeds_many, opts)
        )
    end
  end

  def run_cast_asset(%{type: :gallery, name: name, opts: opts}, changeset, _user) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          Changeset.cast_assoc(changeset, name, required: true)
        else
          Changeset.put_assoc(changeset, name, nil)
        end

      _ ->
        Changeset.cast_assoc(
          changeset,
          name,
          Blueprint.Utils.to_changeset_opts(:belongs_to, opts)
        )
    end
  end

  ##
  ## catch all for non casted assets
  def run_cast_asset(asset, changeset, _user) do
    require Logger

    Logger.error("--> not casted: #{inspect(asset.name, pretty: true)}")
    changeset
  end

  def preloads_for(schema) do
    gallery_images_query =
      from gi in Brando.Images.GalleryImage,
        order_by: [asc: gi.sequence],
        preload: [:image]

    gallery_query =
      from g in Brando.Images.Gallery,
        preload: [gallery_images: ^gallery_images_query]

    Enum.reduce(Brando.Blueprint.Assets.__assets__(schema), [], fn asset, acc ->
      case asset.type do
        :file -> [asset.name | acc]
        :image -> [asset.name | acc]
        :gallery -> [{asset.name, gallery_query} | acc]
        _ -> acc
      end
    end)
  end
end
