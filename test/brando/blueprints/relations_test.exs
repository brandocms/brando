defmodule Brando.Blueprint.RelationsTest do
  use ExUnit.Case
  use Brando.ConnCase

  defmodule P1 do
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
        plural: "contributors"

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
        plural: "project_contributors"

      trait Brando.Trait.Sequenced

      @allow_mark_as_deleted true

      relations do
        relation :project, :belongs_to, module: Brando.Blueprint.RelationsTest.P1
        relation :contributor, :belongs_to, module: Brando.Blueprint.RelationsTest.P1.Contributor
      end
    end

    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    attributes do
      attribute :title, :string, unique: true
    end

    relations do
      relation :creator, :belongs_to, module: Brando.Users.User

      relation :project_contributors, :has_many,
        module: __MODULE__.ProjectContributor,
        preload_order: [asc: :sequence],
        on_replace: :delete_if_exists,
        cast: true

      relation :contributors, :has_many,
        module: __MODULE__.Contributor,
        through: [:project_contributors, :contributor]

      relation :property, :embeds_one, module: __MODULE__.Property
      relation :properties, :embeds_many, module: __MODULE__.Property
    end
  end

  test "belongs_to" do
    changeset_meta = __MODULE__.P1.__changeset__()

    assert changeset_meta.creator ==
             {:assoc,
              %Ecto.Association.BelongsTo{
                cardinality: :one,
                defaults: [],
                field: :creator,
                on_cast: nil,
                on_replace: :raise,
                ordered: false,
                owner: Brando.Blueprint.RelationsTest.P1,
                owner_key: :creator_id,
                queryable: Brando.Users.User,
                related: Brando.Users.User,
                related_key: :id,
                relationship: :parent,
                unique: true,
                where: []
              }}
  end

  test "has_many" do
    changeset_meta = __MODULE__.P1.__changeset__()

    assert changeset_meta.project_contributors ==
             {:assoc,
              %Ecto.Association.Has{
                cardinality: :many,
                field: :project_contributors,
                owner: Brando.Blueprint.RelationsTest.P1,
                related: Brando.Blueprint.RelationsTest.P1.ProjectContributor,
                owner_key: :id,
                related_key: :p1_id,
                on_cast: nil,
                queryable: Brando.Blueprint.RelationsTest.P1.ProjectContributor,
                on_delete: :nothing,
                on_replace: :delete_if_exists,
                where: [],
                unique: true,
                defaults: [],
                relationship: :child,
                ordered: false,
                preload_order: [asc: :sequence]
              }}
  end

  test "embeds_one" do
    changeset_meta = __MODULE__.P1.__changeset__()

    assert changeset_meta.property ==
             {:embed,
              %Ecto.Embedded{
                cardinality: :one,
                field: :property,
                on_cast: nil,
                on_replace: :update,
                ordered: true,
                owner: Brando.Blueprint.RelationsTest.P1,
                related: Brando.Blueprint.RelationsTest.P1.Property,
                unique: true
              }}
  end

  test "embeds_many" do
    changeset_meta = __MODULE__.P1.__changeset__()

    assert changeset_meta.properties ==
             {:embed,
              %Ecto.Embedded{
                cardinality: :many,
                field: :properties,
                on_cast: nil,
                on_replace: :raise,
                ordered: true,
                owner: Brando.Blueprint.RelationsTest.P1,
                related: Brando.Blueprint.RelationsTest.P1.Property,
                unique: true
              }}
  end
end
