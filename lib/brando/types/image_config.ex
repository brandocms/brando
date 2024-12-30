defmodule Brando.Type.ImageConfig do
  @moduledoc """
  Defines a type for an image configuration field.

  ### Options

    * random_filename - use filename given at upload, or create a random filename

  """

  use Ecto.Type

  @type cdn_config :: Brando.CDN.Config
  @type t :: %__MODULE__{
          allowed_mimetypes: [binary],
          default_size: binary,
          random_filename: boolean,
          size_limit: non_neg_integer,
          sizes: %{optional(binary) => map},
          srcset: %{optional(binary) => map} | nil,
          cdn: cdn_config | nil,
          formats: [atom],
          overwrite: boolean,
          upload_path: binary
        }

  @derive Jason.Encoder
  defstruct allowed_mimetypes: [
              "image/jpeg",
              "image/png",
              "image/webp",
              "image/avif",
              "image/gif",
              "image/svg+xml"
            ],
            default_size: "medium",
            random_filename: false,
            size_limit: 10_240_000,
            sizes: %{},
            srcset: nil,
            cdn: nil,
            formats: [:original],
            overwrite: false,
            upload_path: Path.join("images", "default"),
            completed_callback: nil

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

  def default_config do
    %Brando.Type.ImageConfig{
      allowed_mimetypes: [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/avif",
        "image/gif",
        "image/svg+xml"
      ],
      upload_path: Path.join(["images", "site", "default"]),
      default_size: :xlarge,
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
        "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
        "small" => %{"size" => "700", "quality" => 75},
        "medium" => %{"size" => "1100", "quality" => 75},
        "large" => %{"size" => "1700", "quality" => 75},
        "xlarge" => %{"size" => "2100", "quality" => 75}
      },
      srcset: %{
        default: [
          {"small", "700w"},
          {"medium", "1100w"},
          {"large", "1700w"},
          {"xlarge", "2100w"}
        ]
      }
    }
  end
end
