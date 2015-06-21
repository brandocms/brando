defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.
  """

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
    val = Poison.decode!(val, keys: :atoms)
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
  When loading `roles` from the database, we are guaranteed to
  receive an integer (as database are stricts) and we will
  just return it to be stored in the model struct.
  """
  def load(val) when is_binary(val) do
    val = Poison.decode!(val, keys: :atoms)
    if val == nil, do: val = %Brando.Type.ImageConfig{}
    {:ok, val}
  end

  def load(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val) do
    {:ok, val}
  end
end