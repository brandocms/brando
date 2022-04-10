defmodule Brando.Type.FileConfig do
  @moduledoc """
  Defines a type for an image configuration field.
  """
  use Ecto.Type
  import Brando.Utils, only: [stringy_struct: 2]

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct accept: :any,
            allowed_mimetypes: ["application/pdf", "text/plain"],
            upload_path: Path.join("files", "default"),
            random_filename: false,
            overwrite: false,
            size_limit: 10_240_000

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
end
