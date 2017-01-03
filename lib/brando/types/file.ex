defmodule Brando.Type.File do
  @moduledoc """
  Defines a type for an file field.
  """

  @type t :: %__MODULE__{}

  @behaviour Ecto.Type

  defstruct path: nil,
            mimetype: nil,
            size: nil

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

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
    val = Poison.encode!(val)
    {:ok, val}
  end
end
