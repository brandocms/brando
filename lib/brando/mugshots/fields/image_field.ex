defmodule Brando.Mugshots.Fields.ImageField do
  @moduledoc """
  Makes it possible to assign a field as an image field. This means
  you can configure the field with different sizes that will be
  automatically created on file upload.

  ## Example

  In your `my_model.ex`:

      has_image_field :avatar,
        [allowed_exts: ["jpg", "jpeg", "png"],
         default_size: :medium,
         random_filename: true,
         upload_path: Path.join("images", "default"),
         size_limit: 10240000,
         sizes: [
           thumb:  [size: "150x150", quality: 100, crop: true],
           small:  [size: "300x",    quality: 100],
           large:  [size: "700x",    quality: 100]
        ]
      ]
  """
  import Brando.Util, only: [split_path: 1]
  import Brando.Mugshots.Utils
  require Logger

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :imagefields, accumulate: true)
      require Logger
      import Brando.Mugshots.Utils
      import Brando.Mugshots.Fields.ImageField
      @before_compile Brando.Mugshots.Fields.ImageField
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    Brando.Mugshots.Fields.ImageField.compile(Module.get_attribute(
                                              env.module, :imagefields))
  end

  @doc false
  def compile(imagefields) do
    imagefields =
     for {name, contents} <- imagefields do
       defcfg(name, contents)
     end

    quote do
      unquote(imagefields)
    end
  end

  defp defcfg(name, contents) do
    quote do
      @doc """
      Get `field_name`'s image field configuration
      """
      def get_image_cfg(field_name) when field_name == unquote(name) do
        unquote(contents)
      end
    end
  end

  @doc """
  Set the form's `field_name` as being an image_field, and store
  it to the module's @imagefields

  ## Options

    * `allowed_exts`:
      A list of allowed image extensions.
      Example: `["jpg", "jpeg", "png"]`
    * `default_size`:
      If no size is provided to the image helpers, use this size.
      Example: `:medium`
    * random_filename
    * `upload_path`:
      The path used when uploading. This is appended to the base
      `priv/media` directory.
      Example: `Path.join("images", "default")`
    * `size_limit`:
      Enforce a size limit when uploading images.
      Example: `10_240_000`
    * `sizes`:
      A list of different sizes to be created. Each list entry needs a
      list with `size`, `quality` and optional `crop` keys.
      Example:
         sizes: [
           thumb:  [size: "150x150", quality: 100, crop: true],
           small:  [size: "300x",    quality: 100],
           large:  [size: "700x",    quality: 100]
        ]

  """
  defmacro has_image_field(field_name, opts) do
    quote do
      imagefields = Module.get_attribute(__MODULE__, :imagefields)
      Module.put_attribute(__MODULE__, :imagefields,
                           {unquote(field_name), unquote(opts)})
    end
  end

  @doc """
  Handles the upload by starting a chain of operations on the plug.

  ## Parameters

    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  def handle_upload(plug, cfg) do
    case plug.filename |> is_valid_filename?(cfg) do
      {:ok, filename} ->
        case plug.content_type |> is_allowed_mimetype?(cfg[:allowed_mimetypes]) do
          true  -> create_upload_path(filename, plug.path, cfg)
          false -> {:error, "Ikke gyldig filformat (#{plug.content_type})"}
        end
      {:error, error} -> {:error, error}
    end
  end

  defp is_valid_filename?("", _cfg) do
    {:error, :blank_filename}
  end
  defp is_valid_filename?(filename, cfg) do
    case cfg[:random_filename] do
      true -> {:ok, Brando.Util.random_filename(filename)}
      nil  -> {:ok, Brando.Util.slugify_filename(filename)}
    end
  end

  defp is_allowed_mimetype?(content_type, allowed_mimetypes) do
    content_type in allowed_mimetypes
  end

  defp create_upload_path(filename, temp_path, cfg) do
    upload_path = Path.join(get_media_abspath, cfg[:upload_path])
    case File.mkdir_p(upload_path) do
      :ok -> copy_uploaded_file(filename, temp_path, upload_path, cfg)
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_uploaded_file(filename, temp_path, upload_path, cfg) do
    new_file = Path.join(upload_path, filename)
    case File.cp(temp_path, new_file, fn _, _ -> false end) do
      :ok -> create_image_sizes(new_file, cfg)
      {:error, reason} -> Logger.error("copy_uploaded_file: #{new_file} -> #{reason}")
    end
  end

  defp create_image_sizes(file, cfg) do
    {file_path, filename} = split_path(file)
    for {size_name, size_cfg} <- cfg[:sizes] do
      size_dir = Path.join([file_path, Atom.to_string(size_name)])
      File.mkdir_p(size_dir)
      sized_image = Path.join([size_dir, filename])
      Task.start_link(fn -> do_create_image_size(file, sized_image, size_cfg) end)
    end
    {:ok, Path.join([cfg[:upload_path], filename])}
  end

  defp do_create_image_size(file, sized_image, size_cfg) do
    if size_cfg[:crop] do
      Mogrify.open(file)
      |> Mogrify.copy
      |> Mogrify.thumbnail(size_cfg[:size])
      |> Mogrify.save(sized_image)
    else
      Mogrify.open(file)
      |> Mogrify.copy
      |> Mogrify.resize(size_cfg[:size])
      |> Mogrify.save(sized_image)
    end
  end

  @doc """
  Goes through `user`'s fields, matching them to `imagefields`,
  then passing to `delete_media/2` for removal

  ## Example:

      delete_connected_images(user, @imagefields)

  """
  def delete_connected_images(user, imagefields) do
    for {field, cfg} <- imagefields do
      delete_media(Map.get(user, field), cfg)
    end
  end

  @doc """
  Deletes `file` by joining it to `get_media_abspath/0` and
  File.rm!'ing it. Loops through the field's config :sizes entries,
  deleting all generated images. If `file` is nil, do nothing.

  ## Parameters

    * `file`: file to be deleted. Includes partial path.
    * `cfg`: the field's cfg list.

  """
  def delete_media(nil, _cfg), do: nil
  def delete_media("", _cfg), do: nil
  def delete_media(file, cfg) do
    file = Path.join([get_media_abspath, file])
    File.rm!(file)
    for {size, _} <- cfg[:sizes] do
      {file_path, filename} = split_path(file)
      sized_file = Path.join([file_path, Atom.to_string(size), filename])
      File.rm!(sized_file)
    end
  end
end