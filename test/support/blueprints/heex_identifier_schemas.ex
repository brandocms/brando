defmodule Brando.Blueprint.Identifier.HEExTest.HEExIdentifierSchema do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "HEExProject",
    singular: "heex_project",
    plural: "heex_projects",
    gettext_module: Brando.Gettext

  identifier ~H"{@entry.title} [{@entry.language}]"

  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :language, :string
  end

  absolute_url false
end

defmodule Brando.Blueprint.Identifier.HEExTest.HEExAbsoluteURLSchema do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "HEExURLProject",
    singular: "heex_url_project",
    plural: "heex_url_projects",
    gettext_module: Brando.Gettext

  identifier ~H"{@entry.title} [{@entry.category.title}]"

  absolute_url ~H"/projects/{@entry.category.slug}/{@entry.slug}"

  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  relations do
    relation :category, :belongs_to, module: Brando.BlueprintTest.Project
  end
end
