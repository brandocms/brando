defmodule Brando.Field.File.Schema do
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
  alias Brando.Images
  alias Brando.Utils

  import Ecto.Changeset
  import Brando.Field.File.Utils
  import Brando.Upload

  defmacro __using__(_) do
    # IO.warn("""
    # Using `Brando.Field.File.Schema` is deprecated.
    # It is recommended to move to Blueprints instead.
    # """)

    quote do
      Module.register_attribute(__MODULE__, :filefields, accumulate: true)

      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    filefields = Module.get_attribute(env.module, :filefields)
    compile(filefields)
  end

  @doc false
  def compile(filefields) do
    filefields_src = for {name, contents} <- filefields, do: defcfg(name, contents)

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
      def get_file_cfg(field_name) when field_name == unquote(name),
        do: {:ok, unquote(escaped_contents)}
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
      cfg_struct = struct!(%Brando.Type.FileConfig{}, unquote(opts))

      Module.put_attribute(__MODULE__, :filefields, {unquote(field_name), cfg_struct})
    end
  end
end
