defmodule Brando.JSONLD.Schema.IdentitySchema do
  @moduledoc """
  Shared builder for all identity-type JSON-LD schemas.

  Handles the common fields for Organization, Corporation,
  ProfessionalService, LocalBusiness, and Restaurant.
  Type-specific fields are merged from `identity.type_config`.
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @doc """
  Builds a map of shared identity fields from cached Identity and SEO data.
  """
  def build_base({%Sites.Identity{} = identity, %Sites.SEO{} = seo}) do
    base = %{
      "@id": Path.join(Brando.Utils.hostname(), "#identity"),
      address: Schema.PostalAddress.build(identity),
      alternateName: identity.alternate_name,
      description: seo.fallback_meta_description,
      email: identity.email,
      telephone: identity.phone,
      image: Schema.ImageObject.build(seo.fallback_meta_image),
      logo: Schema.ImageObject.build(identity.logo),
      name: identity.name,
      sameAs: build_social_media(identity),
      url: seo.base_url
    }

    merge_type_config(base, identity)
  end

  defp merge_type_config(base, %{type: type, type_config: %{} = config}) do
    type_fields =
      case type do
        t when t in ["organization", "corporation"] ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees
          }

        "professional_service" ->
          %{
            foundingDate: format_date(config.founding_date),
            areaServed: config.area_served,
            knowsAbout: config.knows_about
          }

        "local_business" ->
          %{
            openingHours: config.opening_hours,
            priceRange: config.price_range,
            areaServed: config.area_served,
            geo: build_geo(config)
          }

        "restaurant" ->
          %{
            openingHours: config.opening_hours,
            priceRange: config.price_range,
            servesCuisine: config.serves_cuisine,
            hasMenu: config.has_menu,
            geo: build_geo(config)
          }

        _ ->
          %{}
      end

    # Corporation also gets tickerSymbol
    type_fields =
      if type == "corporation" do
        Map.put(type_fields, :tickerSymbol, config.ticker_symbol)
      else
        type_fields
      end

    Map.merge(base, type_fields)
  end

  defp merge_type_config(base, _), do: base

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(date), do: date

  defp build_geo(%{geo_latitude: lat, geo_longitude: lng})
       when not is_nil(lat) and not is_nil(lng) do
    %{
      "@type": "GeoCoordinates",
      latitude: lat,
      longitude: lng
    }
  end

  defp build_geo(_), do: nil

  @doc """
  Extracts social media URLs from identity links.
  """
  def build_social_media(%{links: links}) when is_list(links) and links != [],
    do: Enum.map(links, & &1.url)

  def build_social_media(_), do: nil
end
