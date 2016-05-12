defmodule Brando.Images.Upload do
  @moduledoc """
  Same principle as ImageField, only this one has its own table.
  We get the config from `image.series.cfg`
  """
  alias Brando.Exception.UploadError
  import Brando.Gettext
  import Brando.Utils
  import Brando.Images.Optimize, only: [optimize: 1]
  import Brando.Images.Utils, only: [create_image_sizes: 1]

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      @doc """
      Checks `params` for Plug.Upload fields and passes them on.
      Fields in the `put_fields` map are added to the model.
      Returns {:ok, model} or raises
      """
      def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
        Enum.reduce filter_plugs(params), [], fn (named_plug, _) ->
          handle_upload(named_plug, current_user, put_fields, __MODULE__, cfg)
        end
      end
    end
  end

  @doc """
  Handles Plug.Upload for our modules.
  """
  def handle_upload({name, plug}, current_user, put_fields, module, cfg) do
    {:ok, file} = do_upload(plug, cfg)
    params = Map.put(put_fields, name, file)
    apply(module, :create, [params, current_user])
  end

  @doc """
  Initiate the upload handling.
  Checks `plug` for filename, checks mimetype, creates upload path,
  copies files and creates all sizes of image according to `cfg`
  """
  def do_upload(plug, %Brando.Type.ImageConfig{} = cfg) do
    process_upload(plug, cfg)
  end
  def do_upload(plug, cfg) when is_map(cfg) do
    cfg_struct =
      if is_atom(List.first(Map.keys(cfg))) do
        struct(Brando.Type.ImageConfig, cfg)
      else
        stringy_struct(Brando.Type.ImageConfig, cfg)
      end
    process_upload(plug, cfg_struct)
  end
  def do_upload(_plug, cfg) when is_list(cfg) do
    raise "do_upload with cfg as list. Fix it!"
  end

  defp process_upload(plug, cfg_struct) do
    {plug, cfg_struct}
    |> get_valid_filename
    |> check_mimetype
    |> create_upload_path
    |> copy_uploaded_file
    |> create_image_sizes
    |> optimize
  end

  defp get_valid_filename({%{filename: ""}, _cfg}) do
    raise UploadError,
          message: gettext("Empty filename given. Make sure you have a valid filename.")
  end

  defp get_valid_filename({%{filename: filename} = plug, cfg}) do
    case Map.get(cfg, :random_filename, false) do
      true -> {Map.put(plug, :filename, random_filename(filename)), cfg}
      _    -> {Map.put(plug, :filename, slugify_filename(filename)), cfg}
    end
  end

  defp check_mimetype({%{content_type: content_type} = plug, cfg}) do
    if content_type in Map.get(cfg, :allowed_mimetypes) do
      {plug, cfg}
    else
      raise UploadError,
            message: gettext("File type not allowed") <> " -> #{content_type}"
    end
  end

  defp create_upload_path({plug, cfg}) do
    upload_path =
      Path.join(Brando.config(:media_path), Map.get(cfg, :upload_path))

    case File.mkdir_p(upload_path) do
      :ok ->
        {Map.put(plug, :upload_path, upload_path), cfg}
      {:error, reason} ->
        raise UploadError,
              message: gettext("Path creation failed") <> " -> #{inspect(reason)}"
    end
  end

  defp copy_uploaded_file({%{filename: filename, path: temp_path,
                          upload_path: upload_path} = plug, cfg}) do
    new_file = Path.join(upload_path, filename)

    if File.exists?(new_file) do
      new_file = Path.join(upload_path, unique_filename(filename))
    end

    case File.cp(temp_path, new_file, fn _, _ -> false end) do
      :ok ->
        {Map.put(plug, :uploaded_file, new_file), cfg}
      {:error, reason} ->
        raise UploadError,
              message: gettext("Error while copying") <>
                       " -> #{inspect(reason)}\n" <>
                       "src: #{temp_path}\n" <>
                       "dest: #{new_file}"
    end
  end

  @doc """
  Filters out all fields except `%Plug.Upload{}` fields.
  """
  def filter_plugs(params) do
    Enum.filter(params, fn (param) ->
      case param do
        {_, %Plug.Upload{}} -> true
        {_, _} -> false
      end
    end)
  end
end
