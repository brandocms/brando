defmodule Brando.Type.File do
  @moduledoc """
  Defines a type for an file field.
  """

  use Ecto.Type

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct path: nil,
            mimetype: nil,
            size: nil,
            cdn: false

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: %Brando.Type.File{})
    {:ok, val}
  end

  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.File{}

  @doc """
  Load
  """
  def load(val) do
    val = Poison.decode!(val, as: %Brando.Type.File{})
    val = if val == nil, do: %Brando.Type.File{}, else: val
    {:ok, val}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) do
    val = Jason.encode!(val)
    {:ok, val}
  end

  defimpl String.Chars, for: __MODULE__ do
    def to_string(%Brando.Type.File{path: path}) do
      Brando.Utils.media_url(path)
    end
  end
end
