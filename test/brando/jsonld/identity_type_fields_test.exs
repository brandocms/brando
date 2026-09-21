defmodule Brando.JSONLD.Schema.IdentityTypeFieldsTest do
  @moduledoc """
  Two gaps, found while a ProfessionalService site was reporting a missing
  priceRange in Google's Rich Results Test.

  ProfessionalService and Architect sit under LocalBusiness, so Google grades
  them against the local-business rich result — but they were built as if they
  were plain Organizations, and `struct/2` would have dropped the fields anyway
  since the structs had no matching keys.

  areaServed and knowsAbout are plain Organization properties. Wiring them only
  into the LocalBusiness subtypes pushed sites towards a Place-flavoured type
  to reach fields they were entitled to as an Organization.
  """
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @local_business [
    {"professional_service", Schema.ProfessionalService},
    {"architect", Schema.Architect}
  ]

  @organization [
    {"organization", Schema.Organization},
    {"corporation", Schema.Corporation}
  ]

  # ImageObject.build/1 walks unloaded assocs otherwise.
  defp seo, do: %Sites.SEO{fallback_meta_image: nil}

  defp identity(type, config \\ []) do
    %Sites.Identity{
      type: type,
      name: "Bielke&Yang",
      logo: nil,

      type_config: struct(Sites.Identity.TypeConfig, config)
    }
  end

  for {type, mod} <- @local_business do
    test "#{type} has somewhere to put the LocalBusiness fields" do
      keys = Map.keys(unquote(mod).__struct__())

      for field <- [:priceRange, :geo, :openingHoursSpecification] do
        assert field in keys, "#{unquote(inspect(mod))} is missing #{field}"
      end
    end

    test "#{type} carries priceRange and geo through to the built node" do
      config = [
        price_range: "$$$",
        geo_latitude: Decimal.new("59.9226"),
        geo_longitude: Decimal.new("10.7589")
      ]

      built = unquote(mod).build({identity(unquote(type), config), seo()})

      assert built.priceRange == "$$$"
      assert built.geo[:"@type"] == "GeoCoordinates"
      assert built.geo.latitude == Decimal.new("59.9226")
    end

    test "#{type} omits the LocalBusiness fields when unconfigured" do
      built = unquote(mod).build({identity(unquote(type)), seo()})

      assert built.priceRange == nil
      assert built.geo == nil
      refute Brando.JSONLD.to_graph_json([built]) =~ "priceRange"
    end
  end

  for {type, mod} <- @organization do
    test "#{type} stays out of LocalBusiness territory" do
      keys = Map.keys(unquote(mod).__struct__())

      for field <- [:priceRange, :geo, :openingHoursSpecification] do
        refute field in keys, "#{unquote(inspect(mod))} should not carry #{field}"
      end
    end
  end

  @all_types [
    {"organization", Schema.Organization},
    {"corporation", Schema.Corporation},
    {"professional_service", Schema.ProfessionalService},
    {"local_business", Schema.LocalBusiness},
    {"restaurant", Schema.Restaurant},
    {"educational_organization", Schema.EducationalOrganization},
    {"government_organization", Schema.GovernmentOrganization},
    {"ngo", Schema.NGO},
    {"medical_organization", Schema.MedicalOrganization},
    {"sports_organization", Schema.SportsOrganization},
    {"art_gallery", Schema.ArtGallery},
    {"architect", Schema.Architect},
    {"employment_agency", Schema.EmploymentAgency}
  ]

  for {type, mod} <- @all_types do
    test "#{type} carries areaServed and knowsAbout" do
      config = [area_served: "Worldwide", knows_about: "Merkevarebygging, identitetsdesign"]
      built = unquote(mod).build({identity(unquote(type), config), seo()})

      assert built.areaServed == "Worldwide",
             "#{unquote(inspect(mod))} dropped areaServed"

      assert built.knowsAbout == "Merkevarebygging, identitetsdesign",
             "#{unquote(inspect(mod))} dropped knowsAbout"
    end

    test "#{type} omits them when unconfigured" do
      built = unquote(mod).build({identity(unquote(type)), seo()})
      json = Brando.JSONLD.to_graph_json([built])

      refute json =~ "areaServed"
      refute json =~ "knowsAbout"
    end
  end
end
