defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.

  ### Options

    * random_filename - use filename given at upload, or create a random filename

  """

  use Ecto.Type

  @type t :: %__MODULE__{
          allowed_mimetypes: [binary],
          default_size: binary,
          random_filename: boolean,
          size_limit: non_neg_integer,
          sizes: %{optional(binary) => map},
          srcset: %{optional(binary) => map} | nil,
          formats: [atom],
          overwrite: boolean,
          upload_path: binary
        }

  @derive Jason.Encoder
  defstruct allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
            default_size: "medium",
            random_filename: false,
            size_limit: 10_240_000,
            sizes: %{},
            srcset: nil,
            formats: [:original],
            overwrite: false,
            upload_path: Path.join("images", "default")

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_map(val) do
    struct = Brando.Utils.map_to_struct(val, __MODULE__)
    formats = Enum.map(struct.formats, &ensure_atom/1)

    {:ok, Map.put(struct, :formats, formats)}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.ImageConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    cast(val)
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val), do: {:ok, val}

  defp ensure_atom(atom) when is_atom(atom), do: atom
  defp ensure_atom(binary) when is_binary(binary), do: String.to_existing_atom(binary)
end
