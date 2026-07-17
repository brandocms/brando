defmodule Brando.Type.FileConfig do
  @moduledoc """
  Defines a configuration type for file uploads.

  ## Options

    * `:allowed_mimetypes` - List of allowed MIME types.
      Default: `["application/pdf", "text/plain"]`

    * `:upload_path` - Path within media directory for storing files.
      Default: `"files/default"`

    * `:random_filename` - Generate a random filename instead of using the original.
      Default: `false`

    * `:slugify_filename` - Slugify the filename (sanitize special characters).
      Default: `true`

    * `:force_filename` - Force a specific filename for all uploads.
      Default: `nil`

    * `:overwrite` - Allow overwriting existing files with the same name.
      Default: `false`

    * `:size_limit` - Maximum file size in bytes.
      Default: `10_240_000` (10MB)

    * `:content_disposition` - Controls browser behavior when file is accessed via CDN.
      * `nil` - No header set (browser default, typically downloads)
      * `:inline` - Display in browser (e.g., PDFs open in browser tab)
      * `:attachment` - Force download with filename

    * `:completed_callback` - Function or `{module, function, extra_args}` called
      after the upload is stored. Receives `(file, user)` before configured MFA
      arguments. Completion work may retry, so side effects should be idempotent.
      Default: `nil`

  ## Example

      assets do
        asset :pdf, :file, cfg: %{
          allowed_mimetypes: ["application/pdf"],
          content_disposition: :inline,
          upload_path: Path.join("files", "pdfs")
        }
      end

  ## Updating Existing CDN Files

  For files already uploaded to CDN, use the mix task to update Content-Disposition:

      # Dry run
      mix brando.files.update_content_disposition "file:MyApp.Schema:pdf_field" --dry-run

      # Apply changes
      mix brando.files.update_content_disposition "file:MyApp.Schema:pdf_field" --disposition inline

  """
  use Ecto.Type
  import Brando.Utils, only: [stringy_struct: 2]

  @type t :: %__MODULE__{
          accept: term(),
          allowed_mimetypes: [String.t()],
          cdn: %Brando.CDN.Config{} | nil,
          completed_callback: Brando.Assets.CompletedCallback.t(struct()),
          content_disposition: nil | :attachment | :inline,
          force_filename: String.t() | nil,
          overwrite: boolean(),
          random_filename: boolean(),
          size_limit: pos_integer(),
          slugify_filename: boolean(),
          upload_path: String.t()
        }

  @derive Jason.Encoder
  defstruct accept: :any,
            cdn: nil,
            allowed_mimetypes: ["application/pdf", "text/plain"],
            upload_path: Path.join("files", "default"),
            random_filename: false,
            slugify_filename: true,
            force_filename: nil,
            overwrite: false,
            size_limit: 10_240_000,
            completed_callback: nil,
            content_disposition: nil

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """

  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.FileConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    string_struct = stringy_struct(Brando.Type.FileConfig, val)
    {:ok, string_struct}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val) do
    {:ok, val}
  end

  def default_config do
    %Brando.Type.FileConfig{
      size_limit: 100_000_000,
      allowed_mimetypes: ["*"],
      random_filename: false
    }
  end
end
