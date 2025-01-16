defmodule Brando.BlueprintTest.P1 do
  defmodule Property do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :key
      field :value
    end

    def changeset(schema, params \\ %{}) do
      schema
      |> cast(params, [:key, :value])
    end
  end

  defmodule Contributor do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "Contributor",
      singular: "contributor",
      plural: "contributors",
      gettext_module: Brando.Gettext

    trait Brando.Trait.Sequenced

    attributes do
      attribute :name, :text
    end
  end

  defmodule Location do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "Location",
      singular: "location",
      plural: "locations",
      gettext_module: Brando.Gettext

    trait Brando.Trait.Sequenced

    attributes do
      attribute :name, :text
    end
  end

  defmodule ProjectContributor do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "ProjectContributor",
      singular: "project_contributor",
      plural: "project_contributors",
      gettext_module: Brando.Gettext

    trait Brando.Trait.Sequenced

    @allow_mark_as_deleted true

    relations do
      relation :p1, :belongs_to, module: Brando.BlueprintTest.P1
      relation :contributor, :belongs_to, module: Brando.BlueprintTest.P1.Contributor
    end
  end

  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator

  attributes do
    attribute :title, :string, unique: true, required: true
  end

  assets do
    asset :image, :image, required: true, cfg: %{}
  end

  relations do
    relation :project_contributors, :has_many,
      module: __MODULE__.ProjectContributor,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :contributors, :has_many,
      module: __MODULE__.Contributor,
      through: [:project_contributors, :contributor],
      preload_order: [asc: :sequence]

    relation :property, :embeds_one, module: __MODULE__.Property
    relation :properties, :embeds_many, module: __MODULE__.Property
    relation :location, :belongs_to, module: __MODULE__.Location, cast: true, required: true
  end
end
