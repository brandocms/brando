defmodule Brando.Sites.Identity.TypeConfig do
  @moduledoc """
  Embedded schema for type-specific Identity configuration.

  Holds the schema.org fields behind the identity's JSON-LD.

  Some apply only to certain types (`opening_hours_specification` for
  LocalBusiness and friends); others — `legal_name`, `vat_id`, `area_served`,
  `knows_about` — are Organization properties every type can carry.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "TypeConfig",
    singular: "type_config",
    plural: "type_configs",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false
  identifier false
  persist_identifier false

  attributes do
    # Organization properties — every identity type descends from Organization
    attribute :legal_name, :string
    attribute :vat_id, :string

    # Organization / Corporation / EducationalOrganization / GovernmentOrganization / NGO
    attribute :founding_date, :date
    attribute :number_of_employees, :integer

    # Corporation only
    attribute :ticker_symbol, :string

    # Organization properties, one entry per market / topic. Lists, so a
    # consumer reads eleven services as eleven topics rather than one string.
    attribute :area_served, Brando.Type.StringList, default: []
    attribute :knows_about, Brando.Type.StringList, default: []

    # LocalBusiness / Restaurant / ArtGallery — structured opening hours
    # Stored as map keyed by day: %{"monday" => %{"opens" => "09:00", "closes" => "17:00", "closed" => false}, ...}
    attribute :opening_hours_specification, :map, default: %{}
    attribute :price_range, :string

    # Restaurant only
    attribute :serves_cuisine, :string
    attribute :has_menu, :string

    # LocalBusiness / Restaurant geo
    attribute :geo_latitude, :decimal
    attribute :geo_longitude, :decimal

    # MedicalOrganization
    attribute :medical_specialty, :string

    # SportsOrganization
    attribute :sport, :string
  end
end
