defmodule Brando.Type.Image do
  @moduledoc """
  Defines a type for an image field.
  """

  alias Brando.Images.Focal

  @behaviour Ecto.Type

  @type t :: %__MODULE__{
          title: binary | nil,
          credits: binary | nil,
          alt: binary | nil,
          path: binary | nil,
          sizes: map,
          width: non_neg_integer | nil,
          height: non_neg_integer | nil,
          focal: Focal.t(),
          cdn: boolean
        }

  @derive {Jason.Encoder,
           only: [:title, :credits, :alt, :path, :sizes, :width, :height, :focal, :cdn]}

  defstruct title: nil,
            credits: nil,
            alt: nil,
            path: nil,
            sizes: %{},
            width: nil,
            height: nil,
            focal: %Focal{x: 50, y: 50},
            cdn: false

  @doc """
  Returns the internal type representation of our image type for pg
  """
  @impl true
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  @impl true
  def cast(val) when is_binary(val) do
    {:ok, Poison.decode!(val, as: %Brando.Type.Image{})}
  end

  def cast(%{file: %Plug.Upload{}} = upload) do
    {:ok, {:upload, upload}}
  end

  def cast(%Brando.Type.Image{} = image) do
    {:ok, image}
  end

  # upload from KInputImageseries
  def cast(%Plug.Upload{} = upload) do
    {:ok, {:upload, %{file: upload}}}
  end

  def cast(update) when is_map(update) do
    {:ok, {:update, update}}
  end

  @doc """
  Load
  """
  @impl true
  def load(%Brando.Type.Image{} = val) when is_map(val), do: {:ok, val}

  def load(val) do
    type_struct = Brando.Utils.stringy_struct(__MODULE__, val)

    {:ok,
     put_in(
       type_struct,
       [Access.key(:focal)],
       Brando.Utils.stringy_struct(Brando.Images.Focal, type_struct.focal)
     )}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  @impl true
  def dump(val), do: {:ok, val}

  @impl true
  def embed_as(_), do: :dump

  @impl true
  def equal?(left, right), do: left == right
end
