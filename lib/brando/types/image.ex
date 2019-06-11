defmodule Brando.Type.Image do
  @moduledoc """
  Defines a type for an image field.
  """

  @type t :: %__MODULE__{}
  @behaviour Ecto.Type

  @derive {Jason.Encoder, only: ~w(title credits path sizes optimized width height focal)a}

  defstruct title: nil,
            credits: nil,
            path: nil,
            sizes: %{},
            optimized: false,
            width: nil,
            height: nil,
            focal: %{"x" => 50, "y" => 50}

  @doc """
  Returns the internal type representation of our image type for pg
  """
  def type, do: :jsonb

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: %Brando.Type.Image{})
    {:ok, val}
  end

  def cast(%Brando.Type.Image{} = val) when is_map(val),
    do: {:ok, val}

  # if we get a Plug Upload, we pass it on.. it gets handled later!
  def cast(%Plug.Upload{} = val) when is_map(val),
    do: {:ok, val}

  # if we get a Focal struct, we pass it on.. it gets handled later!
  def cast(%Brando.Type.Focal{} = val) when is_map(val),
    do: {:ok, val}

  def cast(val) when is_map(val), do: {:ok, Brando.Utils.stringy_struct(Brando.Type.Image, val)}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.Image{}

  @doc """
  Load
  """
  def load(%Brando.Type.Image{} = val) when is_map(val),
    do: {:ok, val}

  def load(val) do
    {:ok, Brando.Utils.stringy_struct(Brando.Type.Image, val)}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) do
    {:ok, val}
  end
end
