defmodule Brando.Type.Image do
  @moduledoc """
  Defines a type for an image field.
  """

  @type t :: %__MODULE__{}
  @behaviour Ecto.Type

  @derive {Poison.Encoder, only: ~w(title credits path sizes optimized width height thumb medium)a}
  @derive {Jason.Encoder, only: ~w(title credits path sizes optimized width height thumb medium)a}
  defstruct title: nil,
            credits: nil,
            path: nil,
            sizes: %{},
            optimized: false,
            width: nil,
            height: nil

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: %Brando.Type.Image{})
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
    val = Poison.decode!(val, as: %Brando.Type.Image{})
    val = if val == nil, do: %Brando.Type.Image{}, else: val
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
