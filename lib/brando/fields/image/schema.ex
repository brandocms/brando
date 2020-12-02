defmodule Brando.Field.Image.Schema do
  @moduledoc """
  Assign a schema's field as an image field.

  This means you can configure the field with different sizes that will be
  automatically created on file upload.

  ## Example

  In your `my_schema.ex`:

      has_image_field :avatar,
        %{allowed_exts: ["jpg", "jpeg", "png"],
         default_size: "medium",
         random_filename: true,
         upload_path: Path.join("images", "default"),
         size_limit: 10_240_000,
         target_format: :jpg,
         sizes: %{
           "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
           "small" =>  %{"size" => "300x", "quality" => 100},
           "large" =>  %{"size" => "700x", "quality" => 10},
        }
      }

  """
  import Ecto.Changeset

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :imagefields, accumulate: true)
      alias Brando.Images
      import Brando.Images.Utils
      import Brando.Upload
      import Ecto.Changeset
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @doc """
      Cleans up old images on update
      """
      defmacro cleanup_old_images(_) do
        raise "cleanup_old_images() should not be used in changesets anymore, just remove it."
      end

      def cleanup_old_images(changeset, :safe) do
        imagefield_keys = Keyword.keys(__image_fields__())

        for key <- Map.keys(changeset.changes) do
          if key in imagefield_keys do
            delete_original_and_sized_images(changeset.data, key)
          end
        end

        changeset
      end

      @doc """
      Validates upload in changeset
      """
      def validate_upload(changeset, {:image, field_name}, user, cfg),
        do: do_validate_upload(changeset, {:image, field_name}, user, cfg)

      def validate_upload(changeset, {:image, field_name}, user),
        do: do_validate_upload(changeset, {:image, field_name}, user, nil)

      def validate_upload(changeset, {:image, field_name}),
        do: do_validate_upload(changeset, {:image, field_name}, :system, nil)

      defp do_validate_upload(changeset, {:image, field_name}, user, cfg) do
        case Brando.Utils.field_has_changed(changeset, field_name) do
          :unchanged ->
            changeset

          {:ok, {:update, update_params}} ->
            with {:ok, _} <- Brando.Utils.changeset_has_no_errors(changeset),
                 {:ok, image_data} <- get_image_data(changeset, field_name),
                 {:ok, changeset} <-
                   maybe_update_focal(update_params, image_data, changeset, field_name, user) do
              changeset
            else
              :has_errors ->
                changeset
            end

          {:ok, {:upload, upload_params}} ->
            with {:ok, _} <- Brando.Utils.changeset_has_no_errors(changeset),
                 {:ok, cfg} <- grab_cfg(cfg, field_name, changeset),
                 {:ok, {:handled, name, field}} <-
                   Images.Upload.Field.handle_upload(field_name, upload_params, cfg, user) do
              cleanup_old_images(changeset, :safe)
              if Brando.CDN.enabled?(), do: Brando.CDN.upload_file(changeset, name, field)
              put_change(changeset, name, field)
            else
              :has_errors ->
                changeset

              {:ok, {:unhandled, name, field}} ->
                changeset

              {:error, {:image_series, :not_found}} ->
                add_error(changeset, :image_series, "Image series not found!")

              {:error, {name, {:error, error_msg}}} ->
                add_error(changeset, name, error_msg)
            end

          {:ok, %Brando.Type.Image{}} ->
            # image from API - villain gallery/image
            changeset
        end
      end

      defp maybe_update_focal(%{focal: focal} = params, image_data, changeset, field_name, user) do
        changeset = put_change(changeset, field_name, Map.merge(image_data, params))
        Images.Processing.recreate_sizes_for_image_field_record(changeset, field_name, user)
      end

      defp maybe_update_focal(params, image_data, changeset, field_name, _) do
        changeset = put_change(changeset, field_name, Map.merge(image_data, params))
        {:ok, changeset}
      end

      defp grab_cfg(nil, field_name, _), do: get_image_cfg(field_name)

      defp grab_cfg(:db, _, changeset) do
        image_series_id = get_field(changeset, :image_series_id)
        Brando.Images.get_series_config(image_series_id)
      end

      defp grab_cfg(cfg, _, _) do
        {:ok, cfg}
      end

      defp get_image_data(changeset, field_name) do
        case Map.get(changeset.data, field_name, nil) do
          nil ->
            raise "Wanted to update image field, but no data was found!"

          image_data ->
            {:ok, image_data}
        end
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
    imagefields_src = for {name, contents} <- imagefields, do: defcfg(name, contents)

    quote do
      def __image_fields__ do
        unquote(Macro.escape(imagefields))
      end

      unquote(imagefields_src)
    end
  end

  defp defcfg(name, cfg) do
    escaped_contents = Macro.escape(cfg)

    quote do
      @doc """
      Get `field_name`'s image field configuration
      """
      def get_image_cfg(field_name) when field_name == unquote(name),
        do: {:ok, unquote(escaped_contents)}
    end
  end

  @doc """
  Set the form's `field_name` as being an image_field, and store
  it to the module's @imagefields.

  Converts the `opts` map to an ImageConfig struct.

  ## Options

    * `allowed_exts`:
      A list of allowed image extensions.
      Example: `["jpg", "jpeg", "png"]`
    * `default_size`:
      If no size is provided to the image helpers, use this size.
      Example: `"medium"`
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

      val =
        case is_map(unquote(opts)) do
          true ->
            struct!(%Brando.Type.ImageConfig{}, unquote(opts))

          false ->
            unquote(opts)
        end

      Module.put_attribute(__MODULE__, :imagefields, {unquote(field_name), val})
    end
  end

  @doc """
  List all registered image fields
  """
  def list_image_fields do
    app_modules = Application.spec(Brando.otp_app(), :modules)
    modules = app_modules

    modules
    |> Enum.filter(&({:__image_fields__, 0} in &1.__info__(:functions)))
    |> Enum.map(fn module ->
      %{
        source: module.__schema__(:source),
        fields: module.__image_fields__() |> Keyword.keys()
      }
    end)
  end

  def generate_image_fields_migration do
    img_fields = list_image_fields()

    Enum.map(img_fields, fn %{source: source, fields: fields} ->
      Enum.map(fields, fn field ->
        ~s(
          execute """
          alter table #{source} alter column #{field} type jsonb using #{field}::JSON
          """
          )
      end)
      |> Enum.join("\n")
    end)
    |> Enum.join("\n")
  end
end
