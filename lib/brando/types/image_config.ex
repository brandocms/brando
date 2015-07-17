defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.
  """

  import Brando.Utils, only: [stringy_struct: 2]

  defstruct allowed_mimetypes: ["image/jpeg", "image/png"],
            default_size: :medium,
            upload_path: Path.join("images", "default"),
            random_filename: false,
            size_limit: 10_240_000,
            sizes: %{}

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: Brando.Type.ImageConfig)
    {:ok, val}
  end
  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.ImageConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    struct = stringy_struct(Brando.Type.ImageConfig, val)
    {:ok, struct}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val) do
    {:ok, val}
  end
end