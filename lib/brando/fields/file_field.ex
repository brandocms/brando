defmodule Brando.Field.FileField do
  @moduledoc """
  Assign a schema's field as a file field.

  ## Example

  In your `my_schema.ex`:

      has_file_field :pdf_report,
        %{allowed_mimetypes: ["application/pdf"],
          random_filename: true,
          upload_path: Path.join("pdfs", "reports"),
          size_limit: 10_240_000,
        }
      }

  """
  import Brando.Files.Upload
  import Brando.Upload

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :filefields, accumulate: true)
      import Brando.Files.Upload
      import Brando.Files.Utils
      import Brando.Upload
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @doc """
      Checks `params` for Plug.Upload fields and passes them on to
      `handle_upload` to check if we have a handler for the field.
      Returns {:ok, schema} or raises
      """
      def check_for_uploads(schema, params) do
        uploads = params
        |> filter_plugs
        |> Enum.reduce([], fn (plug, acc) ->
            [handle_upload_and_defer(plug, &__MODULE__.get_file_cfg/1)|acc]
          end)
        {:ok, uploads}
      end

      @doc """
      Cleans up old images on update
      """
      def cleanup_old_images(changeset) do
        filefield_keys = Keyword.keys(__filefields__())
        for key <- Map.keys(changeset.changes) do
          if key in filefield_keys do
            Brando.Files.Utils.delete_original(changeset.data, key)
          end
        end
        changeset
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    filefields = Module.get_attribute(env.module, :filefields)
    compile(filefields)
  end

  @doc false
  def compile(filefields) do
    filefields_src =
      for {name, contents} <- filefields, do: defcfg(name, contents)

    quote do
      def __filefields__ do
        unquote(Macro.escape(filefields))
      end

      unquote(filefields_src)
    end
  end

  defp defcfg(name, cfg) do
    escaped_contents = Macro.escape(cfg)
    quote do
      @doc """
      Get `field_name`'s file field configuration
      """
      def get_file_cfg(field_name) when field_name == unquote(name), do:
        unquote(escaped_contents)
    end
  end

  @doc """
  Set the form's `field_name` as being an file_field, and store
  it to the module's @filefields.

  Converts the `opts` map to an FileConfig struct.

  ## Options

    * `allowed_exts`:
      A list of allowed file extensions.
      Example: `["pdf", "txt"]`
    * `random_filename`:
      Give the uploaded file a random filename
    * `upload_path`:
      The path used when uploading. This is appended to the base
      `priv/media` directory.
      Example: `Path.join("pdfs", "reports")`
    * `size_limit`:
      Enforce a size limit when uploading files.
      Example: `10_240_000`

  """
  defmacro has_file_field(field_name, opts) do
    quote do
      filefields = Module.get_attribute(__MODULE__, :filefields)
      cfg_struct  = struct!(%Brando.Type.FileConfig{}, unquote(opts))

      Module.put_attribute(__MODULE__, :filefields, {unquote(field_name), cfg_struct})
    end
  end

  @doc """
  Handles the upload by starting a chain of operations on the plug.
  This function handles upload when we have an file field on a schema.

  ## Parameters

    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  def handle_upload_and_defer({name, plug}, cfg_fun) do
    with {:ok, upload} <- process_upload(plug, cfg_fun.(String.to_atom(name))),
         {:ok, field}  <- create_file_struct(upload)
    do
      {name, field}
    else
      err -> handle_upload_error(err)
    end
  end
end
