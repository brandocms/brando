defmodule Brando.JSONLD.Schema.VisualArtwork do
  @moduledoc """
  An artwork as a schema.org `VisualArtwork`, by the site identity.

  Built from an artwork entry, reading the usual field names: `name` or
  `title`, `date_created` or `year`, `art_medium` or `medium`, `image`, and
  `dimensions`. Dimensions written "height x width unit" ("102 x 82 cm", the
  convention for works on a wall) become `height` and `width`; anything else
  is left out rather than guessed. Use it for a project's or exhibition's
  works:

      json_ld_schema Brando.JSONLD.Schema.CreativeWork do
        field :hasPart, {:list, Brando.JSONLD.Schema.VisualArtwork}, & &1.artworks
      end
  """
  @derive Jason.Encoder
  defstruct "@type": "VisualArtwork",
            name: nil,
            image: nil,
            artist: nil,
            dateCreated: nil,
            artMedium: nil,
            height: nil,
            width: nil

  alias Brando.JSONLD.Schema.ImageObject

  @dimensions ~r/^\s*(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(mm|cm|m|in)\s*$/i

  def build(%{} = artwork) do
    {height, width} = artwork |> first_of([:dimensions]) |> dimensions()

    %__MODULE__{
      name: first_of(artwork, [:name, :title]),
      image: image(Map.get(artwork, :image)),
      artist: %{"@id": "#{Brando.Utils.hostname()}/#identity"},
      dateCreated: first_of(artwork, [:date_created, :year]),
      artMedium: first_of(artwork, [:art_medium, :medium]),
      height: height,
      width: width
    }
  end

  def build(_), do: nil

  defp first_of(map, keys), do: Enum.find_value(keys, &present(Map.get(map, &1)))

  defp present(""), do: nil
  defp present(value), do: value

  defp image(%Brando.Images.Image{} = image), do: ImageObject.build(image)
  defp image(_), do: nil

  defp dimensions(text) when is_binary(text) do
    case Regex.run(@dimensions, text) do
      [_, height, width, unit] -> {distance(height, unit), distance(width, unit)}
      _ -> {nil, nil}
    end
  end

  defp dimensions(_), do: {nil, nil}

  defp distance(value, unit), do: %{"@type": "Distance", name: "#{value} #{String.downcase(unit)}"}
end
