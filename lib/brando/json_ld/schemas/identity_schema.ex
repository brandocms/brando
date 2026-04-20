defmodule Brando.JSONLD.Schema.IdentitySchema do
  @moduledoc """
  Shared builder for all identity-type JSON-LD schemas.

  Handles the common fields for all identity types.
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
        "organization" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees
          }

        "corporation" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees,
            tickerSymbol: config.ticker_symbol
          }

        "professional_service" ->
          %{
            foundingDate: format_date(config.founding_date),
            areaServed: config.area_served,
            knowsAbout: config.knows_about
          }

        "local_business" ->
          %{
            openingHoursSpecification: build_opening_hours(config),
            priceRange: config.price_range,
            areaServed: config.area_served,
            geo: build_geo(config)
          }

        "restaurant" ->
          %{
            openingHoursSpecification: build_opening_hours(config),
            priceRange: config.price_range,
            servesCuisine: config.serves_cuisine,
            hasMenu: config.has_menu,
            geo: build_geo(config)
          }

        "educational_organization" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees
          }

        "government_organization" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees
          }

        "ngo" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees
          }

        "medical_organization" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees,
            medicalSpecialty: config.medical_specialty
          }

        "sports_organization" ->
          %{
            foundingDate: format_date(config.founding_date),
            numberOfEmployees: config.number_of_employees,
            sport: config.sport
          }

        _ ->
          %{}
      end

    Map.merge(base, type_fields)
  end

  defp merge_type_config(base, _), do: base

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(date), do: date

  @doc """
  Builds `openingHoursSpecification` from structured opening hours data.

  Input format: `[%{"days" => ["Monday", ...], "opens" => "09:00", "closes" => "17:00"}, ...]`
  Entries with `"closed" => true` are excluded from the output.
  """
  def build_opening_hours(%{opening_hours_specification: specs})
      when is_list(specs) and specs != [] do
    specs
    |> Enum.reject(&(Map.get(&1, "closed") == true))
    |> Enum.map(fn spec ->
      %{
        "@type": "OpeningHoursSpecification",
        dayOfWeek: Map.get(spec, "days", []),
        opens: Map.get(spec, "opens"),
        closes: Map.get(spec, "closes")
      }
    end)
    |> case do
      [] -> nil
      result -> result
    end
  end

  def build_opening_hours(_), do: nil

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
