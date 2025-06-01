defmodule Brando.Type.VideoConfig do
  @moduledoc """
  Defines a type for a video configuration field.
  """
  use Ecto.Type
  import Brando.Utils, only: [stringy_struct: 2]

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct accept: :any,
            cdn: nil,
            allow_uploads: true,
            allow_external_urls: true,
            allowed_mimetypes: ["video/mp4", "video/webm", "video/ogg", "video/quicktime", "video/x-msvideo"],
            upload_path: Path.join("videos", "default"),
            random_filename: false,
            slugify_filename: true,
            force_filename: nil,
            overwrite: false,
            size_limit: 100_000_000,
            completed_callback: nil

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
  def blank?(_), do: %Brando.Type.VideoConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    string_struct = stringy_struct(Brando.Type.VideoConfig, val)
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
    %Brando.Type.VideoConfig{
      size_limit: 100_000_000,
      allowed_mimetypes: ["video/mp4", "video/webm", "video/ogg"],
      random_filename: false,
      allow_uploads: true,
      allow_external_urls: true
    }
  end
end
