defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.

  ### Options

    * random_filename - use filename given at upload, or create a random filename
    * target_format - if set, forces conversion to this format. Master image is kept in its original format.

  """

  use Ecto.Type

  @type t :: %__MODULE__{
          allowed_mimetypes: [binary],
          default_size: binary,
          random_filename: boolean,
          size_limit: non_neg_integer,
          sizes: %{optional(binary) => map},
          srcset: %{optional(binary) => map} | nil,
          target_format: atom | nil,
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
            target_format: nil,
            overwrite: false,
            upload_path: Path.join("images", "default")

  import Brando.Utils, only: [stringy_struct: 2]

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_map(val), do: {:ok, Brando.Utils.map_to_struct(val, __MODULE__)}

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.ImageConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    string_struct = stringy_struct(Brando.Type.ImageConfig, val)
    {:ok, string_struct}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val), do: {:ok, val}
end
