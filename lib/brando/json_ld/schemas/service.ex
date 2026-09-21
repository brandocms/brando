defmodule Brando.JSONLD.Schema.Service do
  @moduledoc """
  Service schema

  Describes a service an organization provides. Useful for naming what a site's
  business actually does, which the identity schema alone does not express.

  `alternateName` is the field that earns its keep on a bilingual site: it
  carries the other language's phrasing — and common industry synonyms —
  without forcing that vocabulary into visible copy.

  Note there is no Google rich result for `Service`. The value is entity
  understanding, so keep the nodes honest: Google asks that structured data
  describe content actually present on the page. Do not list services the site
  does not talk about.

      Service.build(%{
        id: "https://example.com/#identity-design",
        name: "Identitetsdesign",
        alternate_names: ["Brand Identity Design", "visuell identitet"],
        description: "...",
        provider: "https://example.com/#identity",
        area_served: "Worldwide"
      })
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Service",
            "@id": nil,
            name: nil,
            alternateName: nil,
            description: nil,
            serviceType: nil,
            provider: nil,
            areaServed: nil,
            url: nil

  @doc """
  Builds a Service node.

  `provider` accepts a string, which is wrapped as an `@id` reference so the
  node joins the graph instead of duplicating the organization.
  """
  @spec build(map()) :: %__MODULE__{}
  def build(attrs) when is_map(attrs) do
    %__MODULE__{
      "@id": Map.get(attrs, :id),
      name: Map.get(attrs, :name),
      alternateName: attrs |> Map.get(:alternate_names) |> presence(),
      description: Map.get(attrs, :description),
      serviceType: Map.get(attrs, :service_type),
      provider: attrs |> Map.get(:provider) |> reference(),
      areaServed: Map.get(attrs, :area_served),
      url: Map.get(attrs, :url)
    }
  end

  @doc """
  Builds a list of Service nodes that share a provider and area served.
  """
  @spec build_all([map()], keyword()) :: [%__MODULE__{}]
  def build_all(services, opts \\ []) when is_list(services) do
    defaults = Map.new(opts)
    Enum.map(services, &build(Map.merge(defaults, &1)))
  end

  defp reference(nil), do: nil
  defp reference(%{} = provider), do: provider
  defp reference(id) when is_binary(id), do: %{"@id": id}

  defp presence(nil), do: nil
  defp presence([]), do: nil
  defp presence(list), do: list
end
