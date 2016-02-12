defmodule Brando.Field.ImageField do
  @moduledoc """
  Assign a model's field as an image field.

  This means you can configure the field with different sizes that will be
  automatically created on file upload.

  ## Example

  In your `my_model.ex`:

      has_image_field :avatar,
        %{allowed_exts: ["jpg", "jpeg", "png"],
         default_size: :medium,
         random_filename: true,
         upload_path: Path.join("images", "default"),
         size_limit: 10240000,
         sizes: %{
           "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
           "small" =>  %{"size" => "300x",    "quality" => 100},
           "large" =>  %{"size" => "700x",    "quality" => 10},
        }
      }

  """
  import Brando.Images.Upload

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :imagefields, accumulate: true)
      import Brando.Images.Upload
      import Brando.Images.Utils
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @doc """
      Checks `params` for Plug.Upload fields and passes them on to
      `handle_upload` to check if we have a handler for the field.
      Returns {:ok, model} or raises
      """
      def check_for_uploads(model, params) do
        uploads = params
        |> filter_plugs
        |> Enum.reduce([], fn (plug, acc) ->
            [handle_upload_and_defer(plug, &__MODULE__.get_image_cfg/1)|acc]
          end)
        {:ok, uploads}
      end

      @doc """
      Cleans up old images on update
      """
      def cleanup_old_images(changeset) do
        imagefield_keys = Keyword.keys(__imagefields__())
        for key <- Map.keys(changeset.changes) do
          if key in imagefield_keys do
            Brando.Images.Utils.delete_original_and_sized_images(changeset.model, key)
          end
        end
        changeset
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    imagefields = Module.get_attribute(env.module, :imagefields)
    compile(imagefields)
  end

  @doc false
  def compile(imagefields) do
    imagefields_src =
      for {name, contents} <- imagefields, do: defcfg(name, contents)
    quote do
      def __imagefields__() do
        unquote(Macro.escape(imagefields))
      end

      unquote(imagefields_src)
    end
  end

  defp defcfg(name, contents) do
    escaped_contents = Macro.escape(contents)
    quote do
      @doc """
      Get `field_name`'s image field configuration
      """
      def get_image_cfg(field_name) when field_name == unquote(name), do:
        unquote(escaped_contents)
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
  This function handles upload when we have an image field on a model,
  not when the model itself represents an image. (See Brando.Images.Upload)

  ## Parameters

    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  def handle_upload_and_defer({name, plug}, cfg_fun) do
    {:ok, image_field} = do_upload(plug, cfg_fun.(String.to_atom(name)))
    {name, image_field}
  end
end
