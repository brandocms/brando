defmodule Brando.Images.Field.ImageField do
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
  import Brando.Images.Utils
  import Brando.Utils, only: [split_path: 1, random_filename: 1,
                              slugify_filename: 1, task_start: 1]
  alias Brando.Exception.UploadError
  require Logger

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :imagefields, accumulate: true)
      import Brando.Images.Utils
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @doc """
      Checks `form_fields` for Plug.Upload fields and passes them on to
      `handle_upload` to check if we have a handler for the field.
      Returns {:ok, model} or raises
      """
      def check_for_uploads(model, params) do
        params
        |> filter_plugs
        |> Enum.reduce([], fn (plug, acc) -> handle_upload(plug, acc, model, __MODULE__, &__MODULE__.get_image_cfg/1) end)
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    Brando.Images.Field.ImageField.compile(Module.get_attribute(
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
  def handle_upload({name, plug}, _acc, %{id: _id} = model, module, cfg_fun) do
    {:ok, file} = do_upload(plug, cfg_fun.(String.to_atom(name)))
    params = Map.put(%{}, name, file)
    apply(module, :update, [model, params])
  end

  def handle_upload({name, plug}, _acc, _model, module, cfg_fun) do
    {:ok, file} = do_upload(plug, cfg_fun.(String.to_atom(name)))
    params = Map.put(%{}, name, file)
    apply(module, :create, [params])
  end

  defp do_upload(plug, cfg) do
    {plug, cfg}
    |> get_valid_filename
    |> check_mimetype
    |> create_upload_path
    |> copy_uploaded_file
    |> create_image_sizes
  end

  defp get_valid_filename({%{filename: ""}, _cfg}) do
    raise UploadError, message: "Blankt filnavn!"
  end

  defp get_valid_filename({%{filename: filename} = plug, cfg}) do
    case cfg[:random_filename] do
      true -> {Map.put(plug, :filename, random_filename(filename)), cfg}
      nil  -> {Map.put(plug, :filename, slugify_filename(filename)), cfg}
    end
  end

  defp check_mimetype({%{content_type: content_type} = plug, cfg}) do
    if content_type in cfg[:allowed_mimetypes] do
      {plug, cfg}
    else
      raise UploadError, message: "Ikke tillatt filtype -> #{content_type}"
    end
  end

  defp create_upload_path({plug, cfg}) do
    upload_path = Path.join(get_media_abspath, cfg[:upload_path])
    case File.mkdir_p(upload_path) do
      :ok -> {Map.put(plug, :upload_path, upload_path), cfg}
      {:error, reason} -> raise UploadError, message: "Kunne ikke lage filbane -> #{inspect(reason)}"
    end
  end

  defp copy_uploaded_file({%{filename: filename, path: temp_path, upload_path: upload_path} = plug, cfg}) do
    new_file = Path.join(upload_path, filename)
    case File.cp(temp_path, new_file, fn _, _ -> false end) do
      :ok -> {Map.put(plug, :uploaded_file, new_file), cfg}
      {:error, reason} -> raise UploadError, message: "Feil under kopiering -> #{reason}"
    end
  end

  defp create_image_sizes({%{uploaded_file: file}, cfg}) do
    {file_path, filename} = split_path(file)
    for {size_name, size_cfg} <- cfg[:sizes] do
      size_dir = Path.join([file_path, Atom.to_string(size_name)])
      File.mkdir_p(size_dir)
      sized_image = Path.join([size_dir, filename])
      task_start(fn -> do_create_image_size(file, sized_image, size_cfg) end)
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

  defp delete_media(nil, _cfg), do: nil
  defp delete_media("", _cfg), do: nil
  defp delete_media(file, cfg) do
    file = Path.join([get_media_abspath, file])
    File.rm!(file)
    for {size, _} <- cfg[:sizes] do
      {file_path, filename} = split_path(file)
      sized_file = Path.join([file_path, Atom.to_string(size), filename])
      File.rm!(sized_file)
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

  @doc """
  Check if `to_strip` is an unhandled `Plug.Upload`.
  If it is, strip it. If not, return `params`.
  This is used to catch unhandled Plug.Uploads from forms.
  We usually handle these after the fact.
  """
  def strip_unhandled_upload(params, to_strip) do
    case params[to_strip] do
      %Plug.Upload{} -> Map.delete(params, to_strip)
      _ -> params
    end
  end
end