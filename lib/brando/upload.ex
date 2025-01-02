defmodule Brando.Upload do
  @moduledoc """
  Common functions for image and file upload.

  There are two distinct paths of travel within Brando for file uploading.

    1) LiveView uploads for image fields within the Blueprint

    2) Villain content block uploads

  This module contains helper functions for both paths.
  """
  defstruct upload_entry: nil,
            cfg: nil,
            meta: nil

  @type t :: %__MODULE__{}
  @type img_config :: Brando.Type.ImageConfig.t()
  @type upload_error_input :: :error | {:error, any}
  @type upload_error_result :: {:error, binary}

  use Gettext, backend: Brando.Gettext
  import Brando.Utils

  alias Brando.Files
  alias Brando.Images
  alias Brando.Type.FileConfig
  alias Brando.Type.ImageConfig

  @doc """
  Initiate the upload handling.

  Create an upload struct and preprocess the filename, check mimetype etc
  and copy the uploaded file to intended target destination

  Finally returns an image struct
  """
  def handle_upload(%{uploader: "S3"} = meta, upload_entry, cfg, user) do
    with {:ok, upload} <- create_upload_struct(meta, upload_entry, cfg) do
      handle_upload_type(upload, user, :direct_to_s3)
    end
  end

  def handle_upload(meta, upload_entry, cfg, user) do
    with {:ok, upload} <- create_upload_struct(meta, upload_entry, cfg),
         {:ok, upload} <- get_valid_filename(upload),
         {:ok, upload} <- ensure_correct_ext(upload),
         {:ok, upload} <- check_mimetype(upload),
         {:ok, upload} <- create_upload_path(upload),
         {:ok, upload} <- copy_uploaded_file(upload) do
      handle_upload_type(upload, user)
    end
  end

  def process_upload(%{status: :processed} = image, _, _) do
    {:ok, image}
  end

  def process_upload(%{id: image_id} = image, cfg, user) do
    with {:ok, ops} <- Images.Operations.create(image, cfg, user),
         {:ok, %{^image_id => result}} <- Images.Operations.perform(ops, user) do
      Images.update_image(
        image,
        %{sizes: result.sizes, formats: result.formats, status: :processed},
        user
      )
    end
  end

  @doc """
  Handle upload by type.

  Image or file
  """
  def handle_upload_type(%{cfg: %FileConfig{}} = upload, user, :direct_to_s3) do
    file_params = %{
      title: upload.upload_entry.client_name,
      mime_type: upload.upload_entry.client_type,
      filesize: upload.upload_entry.client_size,
      filename: extract_filename_from_key(upload.meta.key),
      config_target: upload.meta.config_target,
      cdn: true
    }

    Files.create_file(file_params, user)
  end

  def handle_upload_type(
        %{cfg: %ImageConfig{}, upload_entry: %{client_type: "image/svg+xml"}} = upload,
        user
      ) do
    svg_size = Brando.Images.Utils.svg_size(upload.meta.uploaded_file)
    dominant_color = Images.Operations.Info.get_dominant_color(upload.meta.media_path)

    image_params = %{
      config_target: upload.meta.config_target,
      path: upload.meta.media_path,
      width: svg_size.width,
      height: svg_size.height,
      dominant_color: dominant_color,
      focal: %{x: 50, y: 50},
      sizes: %{},
      status: :processed
    }

    Images.create_image(image_params, user)
  end

  def handle_upload_type(%{cfg: %FileConfig{}} = upload, user) do
    file_params = %{
      title: upload.upload_entry.client_name,
      mime_type: upload.upload_entry.client_type,
      filesize: upload.upload_entry.client_size,
      filename: upload.meta.filename,
      config_target: upload.meta.config_target,
      cdn: false
    }

    Files.create_file(file_params, user)
  end

  def handle_upload_type(%{meta: meta, upload_entry: _upload_entry, cfg: _cfg}, user) do
    media_path = meta.media_path

    media_path
    |> Images.Utils.media_path()
    |> Fastimage.size()
    |> case do
      {:ok, %{width: width, height: height}} ->
        dominant_color = Images.Operations.Info.get_dominant_color(media_path)

        image_params = %{
          config_target: meta.config_target,
          path: media_path,
          width: width,
          height: height,
          dominant_color: dominant_color,
          focal: %{x: 50, y: 50},
          sizes: %{},
          status: :unprocessed
        }

        Images.create_image(image_params, user)

      {:error, _} ->
        {:error, {:handle_upload_type, "Fastimage.size() failed."}}
    end
  end

  @doc """
  Filters out all fields except `%Plug.Upload{}` fields.
  """
  def filter_plugs(params) do
    Enum.filter(params, fn param ->
      case param do
        {_, %Plug.Upload{}} -> true
        {_, _} -> false
      end
    end)
  end

  @spec handle_upload_error(upload_error_input) :: upload_error_result
  def handle_upload_error(err) do
    message =
      case err do
        {:error, {:create_image_sizes, reason}} ->
          gettext("Error while creating image sizes") <> " -> #{inspect(reason)}"

        {:error, :mkdir, reason} ->
          gettext("Path creation failed") <> " -> #{inspect(reason)}"

        {:error, :cp, {reason, src, dest}} ->
          gettext("Error while copying") <>
            " -> #{inspect(reason)}\nsrc..: #{src}\ndest.: #{dest}"

        :error ->
          gettext("Unknown error while creating image sizes.")
      end

    {:error, message}
  end

  def error_to_string(:too_large), do: gettext("File is too large")
  def error_to_string(:too_many_files), do: gettext("You have selected too many files")
  def error_to_string(:not_accepted), do: gettext("You have selected an unacceptable file type")

  defp create_upload_struct(meta, upload_entry, cfg_struct) do
    {:ok, %__MODULE__{meta: meta, upload_entry: upload_entry, cfg: cfg_struct}}
  end

  defp get_valid_filename(%__MODULE__{upload_entry: %{client_name: ""}}) do
    {:error, :empty_filename}
  end

  defp get_valid_filename(
         %__MODULE__{
           upload_entry: %{client_name: _},
           cfg: %{force_filename: forced_filename, overwrite: true}
         } = upload
       )
       when is_binary(forced_filename) do
    new_meta = Map.merge(upload.meta, %{filename: forced_filename})
    upload = put_in(upload.meta, new_meta)

    {:ok, upload}
  end

  defp get_valid_filename(%__MODULE__{upload_entry: %{client_name: filename}, cfg: cfg} = upload) do
    random_filename? = Map.get(cfg, :random_filename, false)
    slugify_filename? = Map.get(cfg, :slugify_filename, false)

    upload =
      case random_filename? do
        true ->
          new_meta = Map.merge(upload.meta, %{filename: random_filename(filename)})
          put_in(upload.meta, new_meta)

        _ ->
          new_filename = (slugify_filename? && slugify_filename(filename)) || filename
          new_meta = Map.merge(upload.meta, %{filename: new_filename})
          put_in(upload.meta, new_meta)
      end

    {:ok, upload}
  end

  defp ensure_correct_ext(%__MODULE__{meta: %{filename: ""}}) do
    {:error, :empty_filename}
  end

  # make sure jpeg's extension are jpg to avoid headaches w/sharp-cli
  defp ensure_correct_ext(%__MODULE__{meta: %{filename: filename}} = upload) do
    upload = put_in(upload.meta.filename, ensure_correct_extension(filename))

    {:ok, upload}
  end

  defp check_mimetype(%__MODULE__{upload_entry: %{client_type: content_type}, cfg: cfg} = upload) do
    if content_type in Map.get(cfg, :allowed_mimetypes) do
      {:ok, upload}
    else
      if Map.get(cfg, :allowed_mimetypes) == ["*"] do
        {:ok, upload}
      else
        {:error, :content_type, content_type, Map.get(cfg, :allowed_mimetypes)}
      end
    end
  end

  defp create_upload_path(%__MODULE__{cfg: cfg} = upload) do
    upload_path = Path.join(Brando.config(:media_path), Map.get(cfg, :upload_path))

    case File.mkdir_p(upload_path) do
      :ok ->
        {:ok, put_in(upload.meta, Map.put(upload.meta, :upload_path, upload_path))}

      {:error, reason} ->
        {:error, :mkdir, reason}
    end
  end

  defp copy_uploaded_file(
         %__MODULE__{
           meta: %{filename: fname, path: src, upload_path: ul_path},
           cfg: %{upload_path: media_target_path} = cfg
         } = upload
       ) do
    joined_dest = Path.join(ul_path, fname)

    dest =
      if Map.get(cfg, :overwrite) do
        joined_dest
      else
        (File.exists?(joined_dest) && Path.join(ul_path, unique_filename(fname))) || joined_dest
      end

    case File.cp(src, dest, fn _, _ -> cfg.overwrite end) do
      :ok ->
        {:ok,
         put_in(
           upload.meta,
           Map.merge(upload.meta, %{
             filename: Path.basename(dest),
             uploaded_file: dest,
             media_path: Path.join(media_target_path, Path.basename(dest))
           })
         )}

      {:error, reason} ->
        {:error, :cp, {reason, src, dest}}
    end
  end

  defp extract_filename_from_key(key) do
    {_, filename} = Brando.Utils.split_path(key)
    filename
  end
end
