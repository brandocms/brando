defmodule Brando.Sites.Identity.TypeConfig do
  @moduledoc """
  Embedded schema for type-specific Identity configuration.

  Stores fields that only apply to certain identity types
  (e.g. `opening_hours_specification` for LocalBusiness/Restaurant).
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
    # Organization / Corporation / EducationalOrganization / GovernmentOrganization / NGO
    attribute :founding_date, :date
    attribute :number_of_employees, :integer

    # Corporation only
    attribute :ticker_symbol, :string

    # ProfessionalService / LocalBusiness / Restaurant
    attribute :area_served, :string

    # ProfessionalService
    attribute :knows_about, :string

    # LocalBusiness / Restaurant — structured opening hours
    # Stored as list of maps: [%{"days" => ["Monday", ...], "opens" => "09:00", "closes" => "17:00"}, ...]
    attribute :opening_hours_specification, {:array, :map}, default: []
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
