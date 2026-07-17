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
  alias Brando.Blueprint.AssetConfigNormalizer
  alias Brando.Blueprint.Utils
  alias Ecto.Changeset
  alias Spark.Dsl.Extension

  @gallery_module Module.concat(["Brando", "Galleries", "Gallery"])

  @doc """
  Returns the compiled and normalized asset declarations for `module`.
  """
  def __assets__(module) do
    module
    |> Extension.get_entities([:assets])
    |> Enum.map(&AssetConfigNormalizer.normalize/1)
  end

  @doc """
  Returns the compiled and normalized asset named `name` for `module`.
  """
  def __asset__(module, name) do
    module
    |> Extension.get_persisted({:asset, name})
    |> AssetConfigNormalizer.normalize()
  end

  @doc """
  Returns the options for the compiled asset named `name`.
  """
  def __asset_opts__(module, name) do
    module
    |> __asset__(name)
    |> Map.get(:opts, [])
  end

  @doc """
  Applies every compiled asset's casting contract to `changeset`.
  """
  def run_cast_assets(changeset, assets, user) do
    Enum.reduce(assets, changeset, fn asset, current_changeset ->
      run_cast_asset(asset, current_changeset, user)
    end)
  end

  @doc """
  Applies one compiled asset's casting contract to `changeset`.

  Image, file, and video foreign keys are cast with ordinary Blueprint fields.
  Galleries cast their nested association so edits and selection changes remain
  part of the owning entry's changeset.
  """

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
    case asset_param(changeset, name) do
      "" ->
        Changeset.put_embed(changeset, name, [])

      _ ->
        Changeset.cast_embed(
          changeset,
          name,
          Utils.to_changeset_opts(:embeds_many, opts)
        )
    end
  end

  def run_cast_asset(%{type: :gallery, name: name, opts: opts}, changeset, user) do
    gallery_module = @gallery_module

    cast_opts =
      Utils.to_changeset_opts(:belongs_to, opts)
      |> Keyword.put(:with, &gallery_module.changeset(&1, &2, user))

    case asset_param(changeset, name) do
      "" ->
        clear_or_require_gallery(changeset, name, opts)

      _ ->
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

  defp asset_param(%{params: params}, name) when is_map(params) do
    Map.get(params, to_string(name), Map.get(params, name))
  end

  defp asset_param(_changeset, _name), do: nil

  defp clear_or_require_gallery(changeset, name, opts) do
    if Map.get(opts, :required, false) do
      Changeset.add_error(
        changeset,
        name,
        Map.get(opts, :required_message, "can't be blank"),
        validation: :required
      )
    else
      Changeset.put_assoc(changeset, name, nil)
    end
  end

  @doc """
  Returns the association preloads derived from `schema`'s assets.
  """
  def preloads_for(schema) do
    asset_preloads = Module.concat(["Brando", "Blueprint", "AssetPreloads"])
    asset_preloads.for_schema(schema)
  end
end
