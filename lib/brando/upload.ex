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
  defstruct plug: nil,
            cfg: nil,
            extra_info: nil

  @type t :: %__MODULE__{}

  import Brando.Gettext
  import Brando.Utils

  @doc """
  Initiate the upload handling.
  Checks `plug` for filename, checks mimetype, creates upload path,
  copies files and creates all sizes of image according to `cfg`
  """
  def process_upload(plug, cfg_struct) do
    with {:ok, upload} <- create_upload_struct(plug, cfg_struct),
         {:ok, upload} <- extract_focal_info(upload),
         {:ok, upload} <- get_valid_filename(upload),
         {:ok, upload} <- check_mimetype(upload),
         {:ok, upload} <- create_upload_path(upload),
         {:ok, upload} <- copy_uploaded_file(upload) do
      {:ok, upload}
    else
      error -> error
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

  def handle_upload_error(err) do
    case err do
      {:error, :empty_filename} ->
        {:error, gettext("Empty filename given. Make sure you have a valid filename.")}

      {:error, :content_type, content_type, allowed_content_types} ->
        {:error,
         gettext("File type not allowed: %{type}. Must be one of: %{allowed}",
           type: content_type,
           allowed: inspect(allowed_content_types)
         )}

      {:error, :mkdir, reason} ->
        {:error, gettext("Path creation failed") <> " -> #{inspect(reason)}"}

      {:error, :cp, {reason, src, dest}} ->
        {:error,
         gettext("Error while copying") <> " -> #{inspect(reason)}\nsrc..: #{src}\ndest.: #{dest}"}
    end
  end

  defp create_upload_struct(plug, cfg_struct) do
    {:ok, %__MODULE__{plug: plug, cfg: cfg_struct}}
  end

  defp extract_focal_info(%__MODULE__{plug: %Plug.Upload{filename: filename}} = upload) do
    case Regex.named_captures(~r/(?<cleaned_filename>.*)\%\%\%(?<x>.+)\:(?<y>.+)\%\%\%/, filename) do
      nil ->
        upload = Map.put(upload, :extra_info, %{focal: %{"x" => 50, "y" => 50}})
        {:ok, upload}

      %{"x" => x, "y" => y, "cleaned_filename" => cleaned_filename} ->
        upload = Map.put(upload, :extra_info, %{focal: %{"x" => x, "y" => y}})
        upload = put_in(upload.plug.filename, cleaned_filename)
        {:ok, upload}
    end
  end

  defp get_valid_filename(%__MODULE__{plug: %Plug.Upload{filename: ""}}) do
    {:error, :empty_filename}
  end

  defp get_valid_filename(%__MODULE__{plug: %Plug.Upload{filename: filename}, cfg: cfg} = upload) do
    upload =
      case Map.get(cfg, :random_filename, false) do
        true -> put_in(upload.plug.filename, random_filename(filename))
        _ -> put_in(upload.plug.filename, slugify_filename(filename))
      end

    {:ok, upload}
  end

  defp check_mimetype(%__MODULE__{plug: %{content_type: content_type}, cfg: cfg} = upload) do
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
        {:ok, put_in(upload.plug, Map.put(upload.plug, :upload_path, upload_path))}

      {:error, reason} ->
        {:error, :mkdir, reason}
    end
  end

  defp copy_uploaded_file(
         %__MODULE__{plug: %{filename: fname, path: src, upload_path: ul_path}} = upload
       ) do
    joined_dest = Path.join(ul_path, fname)

    dest =
      (File.exists?(joined_dest) && Path.join(ul_path, unique_filename(fname))) || joined_dest

    case File.cp(src, dest, fn _, _ -> false end) do
      :ok ->
        {:ok, put_in(upload.plug, Map.put(upload.plug, :uploaded_file, dest))}

      {:error, reason} ->
        {:error, :cp, {reason, src, dest}}
    end
  end
end
