defmodule Brando.Type.Video do
  @deprecated "Deprecate this in favor of Brando.Videos.Video (embeds_one)"
  @moduledoc """
  Defines a type for video field.
  """
  use Ecto.Type
  alias Brando.Utils

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct url: nil,
            source: nil,
            remote_id: nil,
            width: nil,
            height: nil,
            thumbnail_url: nil

  @doc """
  Returns the internal type representation of our cfg type for pg
  """
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(%__MODULE__{} = val), do: {:ok, val}
  def cast(val) when is_map(val), do: {:ok, Utils.map_to_struct(val, %__MODULE__{})}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.Video{}

  @doc """
  Load
  """
  def load(val) when is_map(val) do
    {:ok, Utils.map_to_struct(val, %__MODULE__{})}
  end

  @doc """
  When dumping data to the database we expect a map, but check for
  other options as well.
  """
  def dump(val) when is_map(val) do
    {:ok, val}
  end
end
