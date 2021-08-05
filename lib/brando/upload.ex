defmodule Brando.Upload do
  @moduledoc """
  Common functions for image and file upload.

  There are two distinct paths of travel within Brando for file uploading.

    1) `ImageField` and `FileField`.
        Called from the schema's changeset -> validate_upload

    2) `Brando.Image` / `Brando.Portfolio.Image`.
       Manually initiated from the controller by invoking `check_for_uploads` which is retrieved
       through `use Brando.Images.Upload`.

  This module contains helper functions for both paths.
  """
  defstruct upload_entry: nil,
            cfg: nil,
            meta: nil

  @type t :: %__MODULE__{}
  @type img_config :: Brando.Type.ImageConfig.t()
  @type upload_error_input :: :error | {:error, any}
  @type upload_error_result :: {:error, binary}

  import Brando.Gettext
  import Brando.Utils

  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Type.ImageConfig
  alias Brando.Type.FileConfig

  @doc """
  Initiate the upload handling.
  Checks `plug` for filename, checks mimetype,
  creates upload path and copies files
  """
  def handle_upload(meta, upload_entry, cfg, user) do
    with {:ok, upload} <- preprocess_upload(meta, upload_entry, cfg),
         {:ok, image_struct} <- handle_upload_type(upload),
         {:ok, operations} <- Images.Operations.create(image_struct, cfg, nil, user),
         {:ok, results} <- Images.Operations.perform(operations, user) do
      results
      |> List.first()
      |> Map.get(:image_struct)
    end
  end

  @doc """
  Handle upload by type.

  Image or file
  """
  def handle_upload_type(%{cfg: %ImageConfig{}} = upload) do
    media_path = upload.meta.media_path

    media_path
    |> Images.Utils.media_path()
    |> Fastimage.size()
    |> case do
      {:ok, %{width: width, height: height}} ->
        dominant_color = Images.Operations.Info.get_dominant_color(media_path)

        {:ok,
         %Image{
           path: media_path,
           width: width,
           height: height,
           dominant_color: dominant_color,
           focal: %{x: 50, y: 50},
           sizes: %{}
         }}

      {:error, _} ->
        # Progress.hide(user)
        {:error, {:create_image_type_struct, "Fastimage.size() failed."}}
    end
  end

  def handle_upload_type(%{cfg: %FileConfig{}} = _upload) do
    {:ok, nil}
  end

  @doc """
  Create an upload struct and preprocess the filename, check mimetype etc
  and copy the uploaded file to intended target destination
  """
  def preprocess_upload(meta, upload_entry, cfg) do
    with {:ok, upload} <- create_upload_struct(meta, upload_entry, cfg),
         {:ok, upload} <- get_valid_filename(upload),
         {:ok, upload} <- ensure_correct_ext(upload),
         {:ok, upload} <- check_mimetype(upload),
         {:ok, upload} <- create_upload_path(upload) do
      copy_uploaded_file(upload)
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
        {:error, {:create_image_type_struct, _}} ->
          gettext("Failed creating image type struct")

        {:error, :empty_filename} ->
          gettext("Empty filename given. Make sure you have a valid filename.")

        {:error, :content_type, content_type, allowed_content_types} ->
          gettext("File type not allowed: %{type}. Must be one of: %{allowed}",
            type: content_type,
            allowed: inspect(allowed_content_types)
          )

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

  defp create_upload_struct(meta, upload_entry, cfg_struct) do
    {:ok, %__MODULE__{meta: meta, upload_entry: upload_entry, cfg: cfg_struct}}
  end

  defp get_valid_filename(%__MODULE__{upload_entry: %{client_name: ""}}) do
    {:error, :empty_filename}
  end

  defp get_valid_filename(%__MODULE__{upload_entry: %{client_name: filename}, cfg: cfg} = upload) do
    upload =
      case Map.get(cfg, :random_filename, false) do
        true ->
          new_meta = Map.merge(upload.meta, %{filename: random_filename(filename)})
          put_in(upload.meta, new_meta)

        _ ->
          new_meta = Map.merge(upload.meta, %{filename: slugify_filename(filename)})
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
           cfg: %{upload_path: media_target_path}
         } = upload
       ) do
    joined_dest = Path.join(ul_path, fname)

    dest =
      (File.exists?(joined_dest) && Path.join(ul_path, unique_filename(fname))) || joined_dest

    case File.cp(src, dest, fn _, _ -> false end) do
      :ok ->
        {:ok,
         put_in(
           upload.meta,
           Map.merge(upload.meta, %{
             uploaded_file: dest,
             media_path: Path.join(media_target_path, Path.basename(dest))
           })
         )}

      {:error, reason} ->
        {:error, :cp, {reason, src, dest}}
    end
  end
end
