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
  import Ecto.Changeset
  import Brando.Files.Upload
  import Brando.Upload
  import Brando.Upload.Utils
  import Brando.Files.Upload
  import Brando.Files.Utils

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :filefields, accumulate: true)

      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @doc """
      Validates upload in changeset
      """
      def validate_upload(changeset, {:file, field_name}, user),
        do: do_validate_upload(changeset, {:file, field_name}, user)

      def validate_upload(changeset, {:file, field_name}),
        do: do_validate_upload(changeset, {:file, field_name}, :system)

      defp do_validate_upload(changeset, {:file, field_name}, _user) do
        with {:ok, plug} <- field_has_changed(changeset, field_name),
             {:ok, _} <- changeset_has_no_errors(changeset),
             {:ok, cfg} <- get_file_cfg(field_name),
             {:ok, {:handled, name, field}} <- handle_file_upload(field_name, plug, cfg) do
          put_change(changeset, name, field)
        else
          :unchanged ->
            changeset

          :has_errors ->
            changeset

          {:error, {name, {:error, error_msg}}} ->
            add_error(changeset, name, error_msg)
        end
      end

      @doc """
      Cleans up old files on update
      """
      def cleanup_old_files(changeset) do
        filefield_keys = Keyword.keys(__filefields__())

        for key <- Map.keys(changeset.changes) do
          if key in filefield_keys do
            delete_original(changeset.data, key)
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

  @doc """
  Handles the upload by starting a chain of operations on the plug.
  This function handles upload when we have an file field on a schema.

  ## Parameters

    * `name`:
    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  @spec handle_file_upload(atom, Plug.Upload.t() | Map.t(), Brando.Type.FileConfig.t()) ::
          {:ok, {:handled, Brando.Type.File}}
          | {:ok, {:unhandled, atom, term}}
          | {:error, {atom, {:error, String.t()}}}
  def handle_file_upload(name, %Plug.Upload{} = plug, cfg) do
    with {:ok, upload} <- process_upload(plug, cfg),
         {:ok, field} <- create_file_struct(upload) do
      {:ok, {:handled, name, field}}
    else
      err -> {:error, {name, handle_upload_error(err)}}
    end
  end

  def handle_file_upload(name, file, _) do
    {:ok, {:unhandled, name, file}}
  end
end
