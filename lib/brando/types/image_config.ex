defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.
  """

  defstruct allowed_mimetypes: ["image/jpeg", "image/png"],
            default_size: :medium,
            upload_path: Path.join("images", "default"),
            size_limit: 10_240_000,
            sizes: %{small:  %{size: "300", quality: 100},
                     medium: %{size: "500", quality: 100},
                     large:  %{size: "700", quality: 100},
                     xlarge: %{size: "900", quality: 100},
                     thumb:  %{size: "150x150^ -gravity center -extent 150x150", quality: 100, crop: true}}

  @behaviour Ecto.Type

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: Brando.Type.ImageConfig, keys: :atoms!)
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
  def load(val) do
    val = Poison.decode!(val, as: Brando.Type.ImageConfig, keys: :atoms!)
    if val == nil, do: val = %Brando.Type.ImageConfig{}
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