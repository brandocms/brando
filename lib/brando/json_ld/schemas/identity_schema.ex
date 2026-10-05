defmodule Brando.JSONLD.Schema.IdentitySchema do
  @moduledoc """
  Shared builder for all identity-type JSON-LD schemas.

  Handles the common fields for all identity types.
  Type-specific fields are merged from `identity.type_config`.
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @employer_types ~w(organization educational_organization government_organization ngo)
  @storefront_types ~w(local_business art_gallery employment_agency)

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

  # A person carries none of the Organization properties below (legal name,
  # VAT, area served) — only what they know about and what they do.
  defp merge_type_config(base, %{type: "person", type_config: %{} = config}) do
    Map.merge(base, %{
      jobTitle: config.job_title,
      hasOccupation: occupation(config.occupation),
      additionalType: blank_to_nil(config.additional_type),
      knowsAbout: list_or_nil(config.knows_about)
    })
  end

  defp merge_type_config(base, %{type: type, type_config: %{} = config}) do
    type_fields = type_fields(type, config)

    # areaServed and knowsAbout are Organization properties, so every identity
    # type descends from something that can carry them. Applying them here
    # rather than per type is what stopped sites reaching for a LocalBusiness
    # subtype just to get at a field they already had.
    shared = %{
      legalName: config.legal_name,
      vatID: config.vat_id,
      areaServed: list_or_nil(config.area_served),
      knowsAbout: list_or_nil(config.knows_about)
    }

    base
    |> Map.merge(shared)
    |> Map.merge(type_fields)
  end

  defp merge_type_config(base, _), do: base

  defp type_fields(type, config) when type in @employer_types do
    %{
      foundingDate: format_date(config.founding_date),
      numberOfEmployees: config.number_of_employees
    }
  end

  defp type_fields("corporation", config) do
    %{
      foundingDate: format_date(config.founding_date),
      numberOfEmployees: config.number_of_employees,
      tickerSymbol: config.ticker_symbol
    }
  end

  defp type_fields("professional_service", config) do
    %{
      foundingDate: format_date(config.founding_date),
      openingHoursSpecification: build_opening_hours(config),
      priceRange: config.price_range,
      geo: build_geo(config)
    }
  end

  defp type_fields(type, config) when type in @storefront_types do
    %{
      openingHoursSpecification: build_opening_hours(config),
      priceRange: config.price_range,
      geo: build_geo(config)
    }
  end

  defp type_fields("restaurant", config) do
    %{
      openingHoursSpecification: build_opening_hours(config),
      priceRange: config.price_range,
      servesCuisine: config.serves_cuisine,
      hasMenu: config.has_menu,
      geo: build_geo(config)
    }
  end

  defp type_fields("medical_organization", config) do
    %{
      foundingDate: format_date(config.founding_date),
      numberOfEmployees: config.number_of_employees,
      medicalSpecialty: config.medical_specialty
    }
  end

  defp type_fields("sports_organization", config) do
    %{
      foundingDate: format_date(config.founding_date),
      numberOfEmployees: config.number_of_employees,
      sport: config.sport
    }
  end

  defp type_fields("architect", config) do
    %{
      foundingDate: format_date(config.founding_date),
      openingHoursSpecification: build_opening_hours(config),
      priceRange: config.price_range,
      geo: build_geo(config)
    }
  end

  defp type_fields(_type, _config), do: %{}

  defp occupation(name) when is_binary(name) and name != "", do: %{"@type": "Occupation", name: name}
  defp occupation(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(date), do: date

  @day_key_to_label %{
    "monday" => "Monday",
    "tuesday" => "Tuesday",
    "wednesday" => "Wednesday",
    "thursday" => "Thursday",
    "friday" => "Friday",
    "saturday" => "Saturday",
    "sunday" => "Sunday"
  }

  @doc """
  Builds `openingHoursSpecification` from structured opening hours data.

  Input format: `%{"monday" => %{"opens" => "09:00", "closes" => "17:00", "closed" => "false"}, ...}`
  Days with `"closed" => "true"` are excluded from the output.
  """
  def build_opening_hours(%{opening_hours_specification: specs})
      when is_map(specs) and map_size(specs) > 0 do
    specs
    |> Enum.reject(fn {_day, data} -> Map.get(data, "closed") in [true, "true"] end)
    |> Enum.map(fn {day_key, data} ->
      %{
        "@type": "OpeningHoursSpecification",
        dayOfWeek: Map.get(@day_key_to_label, day_key, day_key),
        opens: Map.get(data, "opens"),
        closes: Map.get(data, "closes")
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

  # Empty lists would encode as `[]`, which reads as "serves nowhere".
  defp list_or_nil(nil), do: nil
  defp list_or_nil([]), do: nil
  defp list_or_nil(list) when is_list(list), do: list

  defp list_or_nil(value) when is_binary(value),
    do: value |> String.split(",") |> Brando.Type.StringList.normalize() |> list_or_nil()
end
