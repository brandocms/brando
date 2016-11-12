defmodule Brando.Upload do
  @moduledoc """
  Common functions for image and file upload through plug.

  ## Options

    * `process_fn` - Required. This is the function at the end of the Upload line. For images
                     this could create thumbnails etc.
  """
  defstruct plug: nil,
            cfg:  nil

  @type t :: %__MODULE__{}

  import Brando.Gettext
  import Brando.Utils

  defmacro __using__(opts) do
    quote do
      require Logger

      opts = unquote(opts)
      if !opts do
        raise "No options passed to Brando.Upload"
      end

      @process_fn Keyword.fetch!(opts, :process_fn)
      import unquote(__MODULE__)

      @doc """
      Checks `params` for Plug.Upload fields and passes them on.
      Fields in the `put_fields` map are added to the schema.
      Returns {:ok, schema} or raises
      """
      def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
        Enum.reduce filter_plugs(params), [], fn (named_plug, _) ->
          handle_upload(
            named_plug,
            @process_fn,
            current_user,
            put_fields,
            __MODULE__,
            cfg
          )
        end
      end
    end
  end

  @doc """
  Handles Plug.Upload for our modules.
  """
  def handle_upload({name, plug}, process_fn, user, put_fields, schema, cfg) do
    {:ok, upload} = process_upload(plug, cfg)

    case process_fn.(upload) do
      {:ok, processed_field} ->
        params = Map.put(put_fields, name, processed_field)
        apply(schema, :create, [params, user])
      err ->
        handle_upload_error(err)
    end
  end

  @doc """
  Initiate the upload handling.
  Checks `plug` for filename, checks mimetype, creates upload path,
  copies files and creates all sizes of image according to `cfg`
  """
  def process_upload(plug, cfg_struct) do
    with {:ok, upload} <- create_upload_struct(plug, cfg_struct),
         {:ok, upload} <- get_valid_filename(upload),
         {:ok, upload} <- check_mimetype(upload),
         {:ok, upload} <- create_upload_path(upload),
         {:ok, upload} <- copy_uploaded_file(upload)
    do
      {:ok, upload}
    else
      error -> error
    end
  end

  defp create_upload_struct(plug, cfg_struct) do
    {:ok, %__MODULE__{plug: plug, cfg: cfg_struct}}
  end

  defp get_valid_filename(%__MODULE__{plug: %{filename: ""}}) do
    {:error, :empty_filename}
  end

  defp get_valid_filename(%__MODULE__{plug: %{filename: filename} = plug, cfg: cfg} = upload) do
    upload =
      case Map.get(cfg, :random_filename, false) do
        true -> put_in(upload.plug.filename, random_filename(filename))
        _    -> put_in(upload.plug.filename, slugify_filename(filename))
      end
    {:ok, upload}
  end

  defp check_mimetype(%__MODULE__{plug: %{content_type: content_type}, cfg: cfg} = upload) do
    if content_type in Map.get(cfg, :allowed_mimetypes) do
      {:ok, upload}
    else
      {:error, :content_type, content_type}
    end
  end

  defp create_upload_path(%__MODULE__{plug: plug, cfg: cfg} = upload) do
    upload_path = Path.join(Brando.config(:media_path), Map.get(cfg, :upload_path))

    case File.mkdir_p(upload_path) do
      :ok ->
        {:ok, put_in(upload.plug, Map.put(upload.plug, :upload_path, upload_path))}
      {:error, reason} ->
        {:error, :mkdir, reason}
    end
  end

  defp copy_uploaded_file(%__MODULE__{plug: %{filename: fname, path: src, upload_path: ul_path}} = upload) do
    joined_dest = Path.join(ul_path, fname)
    dest = File.exists?(joined_dest) && Path.join(ul_path, unique_filename(fname))
                                     || joined_dest

    case File.cp(src, dest, fn _, _ -> false end) do
      :ok ->
        {:ok, put_in(upload.plug, Map.put(upload.plug, :uploaded_file, dest))}
      {:error, reason} ->
        {:error, :cp, {reason, src, dest}}
    end
  end

  @doc """
  Filters out all fields except `%Plug.Upload{}` fields.
  """
  def filter_plugs(params) do
    Enum.filter(params, fn (param) ->
      case param do
        {_, %Plug.Upload{}} -> true
        {_, _}              -> false
      end
    end)
  end

  def handle_upload_error(err) do
    case err do
      {:error, :empty_filename} ->
        raise Brando.Exception.UploadError,
          message: gettext("Empty filename given. Make sure you have a valid filename.")
      {:error, :content_type, content_type} ->
        raise Brando.Exception.UploadError,
          message: gettext("File type not allowed") <> " -> #{content_type}"
      {:error, :mkdir, reason} ->
        raise Brando.Exception.UploadError,
          message: gettext("Path creation failed") <> " -> #{inspect(reason)}"
      {:error, :cp, {reason, src, dest}} ->
        raise Brando.Exception.UploadError,
          message: gettext("Error while copying") <> " -> #{inspect(reason)}\n"
                                                     "src..: #{src}\n" <>
                                                     "dest.: #{dest}"
    end
  end
end
