defmodule Brando.Type.Video do
  @moduledoc """
  Defines a type for video field.
  """

  use Ecto.Type

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct url: nil,
            source: nil,
            remote_id: nil,
            width: nil,
            height: nil,
            thumbnail_url: nil

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: %Brando.Type.Video{})
    {:ok, val}
  end

  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.Video{}

  @doc """
  Load
  """
  def load(val) do
    val = Poison.decode!(val, as: %Brando.Type.Video{})
    val = if val == nil, do: %Brando.Type.Video{}, else: val
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
end
