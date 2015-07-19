defmodule Brando.Images.Utils do
  @moduledoc """
  General utilities pertaining to the Images module
  """

  import Brando.Utils
  alias Brando.Exception.UploadError

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
    # do_upload(plug, Enum.into(cfg, %{}))
  end

  defp process_upload(upload) do
    upload
    |> get_valid_filename
    |> check_mimetype
    |> create_upload_path
    |> copy_uploaded_file
    |> create_image_sizes
  end

  defp get_valid_filename({%{filename: ""}, _cfg}) do
    raise UploadError, message: "Blankt filnavn gitt under opplasting. Pass på at du har et gyldig filnavn."
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
    upload_path = Path.join(Brando.config(:media_path), Map.get(cfg, :upload_path))
    case File.mkdir_p(upload_path) do
      :ok -> {Map.put(plug, :upload_path, upload_path), cfg}
      {:error, reason} -> raise UploadError, message: "Kunne ikke lage filbane -> #{inspect(reason)}"
    end
  end

  defp copy_uploaded_file({%{filename: filename, path: temp_path, upload_path: upload_path} = plug, cfg}) do
    new_file = Path.join(upload_path, filename)
    if File.exists?(new_file) do
      new_file = Path.join(upload_path, unique_filename(filename))
    end
    case File.cp(temp_path, new_file, fn _, _ -> false end) do
      :ok -> {Map.put(plug, :uploaded_file, new_file), cfg}
      {:error, reason} -> raise UploadError, message: "Feil under kopiering -> #{inspect(reason)}"
    end
  end

  defp create_image_sizes({%{uploaded_file: file}, cfg}) do
    sizes = %{}
    {file_path, filename} = split_path(file)
    upload_path = Map.get(cfg, :upload_path)

    sizes = for {size_name, size_cfg} <- Map.get(cfg, :sizes) do
      size_dir = Path.join([file_path, to_string(size_name)])
      File.mkdir_p(size_dir)
      sized_image = Path.join([size_dir, filename])
      create_image_size(file, sized_image, size_cfg)
      sized_path = Path.join([upload_path, to_string(size_name), filename])
      {size_name, sized_path}
    end

    {:ok, %Brando.Type.Image{}
    |> Map.put(:sizes, Enum.into(sizes, %{}))
    |> Map.put(:path, Path.join([upload_path, filename]))}
  end


  def create_image_size(file, sized_image, size_cfg) do
    modifier = if String.ends_with?(size_cfg["size"], ["<", ">", "^", "%", "!", "@"]) do
      ""
    else
      "^"
    end
    fill = if size_cfg["fill"] do
      "-background #{size_cfg["fill"]} "
    else
      ""
    end
    if size_cfg["crop"] do
      Mogrify.open(file)
      |> Mogrify.copy
      |> Mogrify.thumbnail("#{size_cfg["size"]}#{modifier} #{fill}-gravity center -extent #{size_cfg["size"]}")
      |> Mogrify.save(sized_image)
    else
      Mogrify.open(file)
      |> Mogrify.copy
      |> Mogrify.resize(size_cfg["size"])
      |> Mogrify.save(sized_image)
    end
  end

  @doc """
  Goes through `image`, which is a model with a :sizes field
  then passing to `delete_media/2` for removal

  ## Example:

      delete_original_and_sized_images(record.cover)

  """
  def delete_original_and_sized_images(nil) do
    nil
  end
  def delete_original_and_sized_images(image) do
    sizes = Map.get(image, :sizes)
    for {_size, file} <- sizes do
      delete_media(file)
    end
    delete_media(Map.get(image, :path))
  end

  @doc """
  Deletes `file` after joining it with `media_path`
  """
  def delete_media(nil), do: nil
  def delete_media(""), do: nil
  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    File.rm(file)
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

  @doc """
  Splits `file` with `split_path/1`, adds `size` to the path before
  concatenating it with the filename.

  ## Example

      iex> size_dir("test/dir/filename.jpg", :thumb)
      "test/dir/thumb/filename.jpg"

  """
  def size_dir(file, size) when is_binary(size) do
    {path, filename} = split_path(file)
    Path.join([path, size, filename])
  end

  def size_dir(file, size) when is_atom(size) do
    {path, filename} = split_path(file)
    Path.join([path, Atom.to_string(size), filename])
  end
end