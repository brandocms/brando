defmodule Brando.Blueprint.Assets do
  @moduledoc """
  Assets are media attachments for blueprints: images, files, videos, and galleries.

  Assets are declared in the `assets` block of a blueprint and create belongs_to
  relationships to the corresponding media schemas (`Brando.Images.Image`,
  `Brando.Files.File`, `Brando.Videos.Video`, `Brando.Galleries.Gallery`).

  ## Asset Types

  ### File

  File assets store uploaded files (PDFs, documents, etc.) with configurable behavior.

  #### Configuration Options

  See `Brando.Type.FileConfig` for all available options. Key options include:

    * `:allowed_mimetypes` - List of allowed MIME types
    * `:upload_path` - Storage path within media directory
    * `:content_disposition` - Browser behavior (`:inline` to display, `:attachment` to download)
    * `:size_limit` - Maximum file size in bytes

  #### Example

      assets do
        asset :pdf, :file, required: true, cfg: %{
          allowed_mimetypes: ["application/pdf"],
          content_disposition: :inline,
          upload_path: Path.join("files", "pdfs"),
          size_limit: 16_000_000
        }
      end

  ### Gallery

  Gallery assets store collections of images and/or videos.

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

  Image assets store single images with automatic resizing and srcset generation.

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

  ### Video

  Video assets store uploaded or embedded videos.

  #### Example

      asset :promo_video, :video, cfg: %{
        upload_path: Path.join(["videos", "promos"])
      }
  """
  import Ecto.Query

  alias Brando.Blueprint
  alias Ecto.Changeset
  alias Spark.Dsl.Extension

  def __assets__(module) do
    module
    |> Extension.get_entities([:assets])
    |> Enum.map(&Brando.Blueprint.Assets.Dsl.normalize_runtime_config/1)
  end

  def __asset__(module, name) do
    module
    |> Extension.get_persisted({:asset, name})
    |> Brando.Blueprint.Assets.Dsl.normalize_runtime_config()
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

  def run_cast_asset(%{type: :gallery, name: name, opts: opts}, changeset, user) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          Changeset.cast_assoc(changeset, name, required: true)
        else
          Changeset.put_assoc(changeset, name, nil)
        end

      _ ->
        gallery_module = Brando.Galleries.Gallery

        cast_opts =
          Blueprint.Utils.to_changeset_opts(:belongs_to, opts)
          |> Keyword.put(:with, &gallery_module.changeset(&1, &2, user))

        Changeset.cast_assoc(changeset, name, cast_opts)
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
    gallery_objects_query =
      from go in Brando.Galleries.GalleryObject,
        order_by: [asc: go.sequence],
        preload: [:image, :video]

    gallery_query =
      from g in Brando.Galleries.Gallery,
        preload: [gallery_objects: ^gallery_objects_query]

    Enum.reduce(Brando.Blueprint.Assets.__assets__(schema), [], fn asset, acc ->
      case asset.type do
        :file -> [asset.name | acc]
        :image -> [asset.name | acc]
        :video -> [asset.name | acc]
        :gallery -> [{asset.name, gallery_query} | acc]
        _ -> acc
      end
    end)
  end
end
