defmodule Brando.Images.Upload do
  @moduledoc """
  Same principle as ImageField, only this one has its own table.
  We get the config from `image.series.cfg`
  """

  import Brando.Utils
  import Brando.Images.Optimize, only: [optimize: 1]
  alias Brando.Exception.UploadError

  defmacro __using__(_) do
    quote do
      import Brando.Images.Utils
      import unquote(__MODULE__)
      @doc """
      Checks `params` for Plug.Upload fields and passes them on.
      Fields in the `put_fields` map are added to the model.
      Returns {:ok, model} or raises
      """
      def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
        Enum.reduce filter_plugs(params), [], fn (plug, acc) ->
          handle_upload(plug, acc, current_user, put_fields, __MODULE__, cfg)
        end
      end
    end
  end

  @doc """
  Handles Plug.Upload for our modules.
  """
  def handle_upload({name, plug}, _, current_user, put_fields, module, cfg) do
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
    process_upload({plug, cfg})
  end
  def do_upload(plug, cfg) when is_map(cfg) do
    cfg_struct =
      if is_atom(List.first(Map.keys(cfg))) do
        struct(Brando.Type.ImageConfig, cfg)
      else
        stringy_struct(Brando.Type.ImageConfig, cfg)
      end
    process_upload({plug, cfg_struct})
  end
  def do_upload(_plug, cfg) when is_list(cfg) do
    raise "do_upload with cfg as list. Fix it!"
  end

  defp process_upload(upload) do
    upload
    |> get_valid_filename
    |> check_mimetype
    |> create_upload_path
    |> copy_uploaded_file
    |> create_image_sizes
    |> optimize
  end

  defp get_valid_filename({%{filename: ""}, _cfg}) do
    raise UploadError,
          message: "Blankt filnavn gitt under opplasting. " <>
                   "Pass på at du har et gyldig filnavn."
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
      raise UploadError, message: "Ikke tillatt filtype -> #{content_type}"
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
              message: "Kunne ikke lage filbane -> #{inspect(reason)}"
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
        raise UploadError, message: "Feil under kopiering -> #{inspect(reason)}"
    end
  end

  defp create_image_sizes({%{uploaded_file: file}, cfg}) do
    {file_path, filename} = split_path(file)
    upload_path = Map.get(cfg, :upload_path)

    sizes = for {size_name, size_cfg} <- Map.get(cfg, :sizes) do
      size_dir = Path.join([file_path, to_string(size_name)])
      sized_image = Path.join([size_dir, filename])
      sized_path = Path.join([upload_path, to_string(size_name), filename])

      File.mkdir_p(size_dir)
      create_image_size(file, sized_image, size_cfg)
      {size_name, sized_path}
    end

    size_struct =
      %Brando.Type.Image{}
      |> Map.put(:sizes, Enum.into(sizes, %{}))
      |> Map.put(:path, Path.join([upload_path, filename]))

    {:ok, size_struct}
  end

  @doc """
  Creates a sized version of `image_src`.
  """
  def create_image_size(image_src, image_dest, size_cfg) do
    modifier = String.ends_with?(size_cfg["size"], ~w(< > ^ % ! @)) && "" || "^"
    fill = size_cfg["fill"] && "-background #{size_cfg["fill"]} " || ""
    crop_string = "#{size_cfg["size"]}#{modifier} " <>
                  "#{fill}-gravity center -extent #{size_cfg["size"]}"

    if size_cfg["crop"] do
      image_src
      |> Mogrify.open
      |> Mogrify.copy
      |> Mogrify.resize(crop_string)
      |> Mogrify.save(image_dest)
    else
      image_src
      |> Mogrify.open
      |> Mogrify.copy
      |> Mogrify.resize(size_cfg["size"])
      |> Mogrify.save(image_dest)
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
