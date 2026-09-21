defmodule Brando.Sites.Service do
  @moduledoc """
  A service the organization provides, configured on the identity.

  Rendered into the JSON-LD graph as a `Service` node joined to the identity,
  so a site can say what its business does without a developer writing a
  controller. Optionally points at an entry through its identifier; the
  service then takes that page's URL and, when it has no description of its
  own, the page's meta description or block text — keeping the markup
  grounded in content that is actually published.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Service",
    singular: "service",
    plural: "services",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  table "sites_services"

  trait :sequenced
  trait :timestamped

  identifier false
  persist_identifier false

  attributes do
    attribute :name, :string, required: true
    attribute :description, :text
    attribute :alternate_names, Brando.Type.StringList, default: []
    attribute :service_type, :string
    attribute :url, :string
    attribute :area_served, Brando.Type.StringList, default: []

    # Filled by `Brando.Sites.Services.resolve/1` when the identity cache is
    # built, so page renders read them without a query.
    attribute :resolved_url, :string, virtual: true
    attribute :resolved_description, :text, virtual: true
  end

  relations do
    relation :identity, :belongs_to, module: Brando.Sites.Identity
    relation :identifier, :belongs_to, module: Brando.Content.Identifier, on_replace: :nilify
  end

  translations do
    context :naming do
      translate :singular, t("service")
      translate :plural, t("services")
    end
  end
end
