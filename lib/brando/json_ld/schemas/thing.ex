defmodule Brando.JSONLD.Schema.Thing do
  @moduledoc """
  A named thing of any schema.org type, for properties that point at
  something Brando has no schema for: the book a review is about, the
  country a remote job is open to.

      Thing.build(%{type: "Book", name: "Kristin Lavransdatter"})
      Thing.build(%{type: "Country", name: "NO"})
  """

  @derive Jason.Encoder
  defstruct "@type": "Thing",
            "@id": nil,
            name: nil,
            url: nil,
            image: nil

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      "@type": to_string(Map.get(data, :type, "Thing")),
      "@id": Map.get(data, :id),
      name: Map.get(data, :name),
      url: Map.get(data, :url),
      image: data |> Map.get(:image) |> image()
    }
  end

  defp image(nil), do: nil
  defp image(url) when is_binary(url), do: url
  defp image(image), do: Brando.JSONLD.Schema.ImageObject.build(image)
end
