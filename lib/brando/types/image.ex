defmodule Brando.Type.Image do
  @moduledoc """
  Defines a type for an image field.
  """

  defstruct title: nil,
            credits: nil,
            path: nil,
            sizes: %{},
            optimized: false

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: Brando.Type.Image)
    {:ok, val}
  end
  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.Image{}

  @doc """
  Load
  """
  def load(val) do
    val = Poison.decode!(val, as: Brando.Type.Image)
    if val == nil, do: val = %Brando.Type.Image{}
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
