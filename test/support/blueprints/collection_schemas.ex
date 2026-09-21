defmodule Brando.JSONLD.CollectionTest.Thing do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Things",
    schema: "Thing",
    singular: "thing",
    plural: "things",
    gettext_module: Brando.Gettext

  identifier ~H"{@entry.title}"
  absolute_url ~H"/things/{@entry.slug}"

  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end
end

defmodule Brando.JSONLD.CollectionTest.NoUrlThing do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Things",
    schema: "NoUrlThing",
    singular: "no_url_thing",
    plural: "no_url_things",
    gettext_module: Brando.Gettext

  identifier ~H"{@entry.title}"
  absolute_url false

  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
  end
end
