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

      relation :related_projects, :many_to_many,
        module: __MODULE__,
        cast: true,
        join_through: "projects_related",
        join_keys: [project_id: :id, related_project_id: :id],
        on_delete: :delete_all,
        on_replace: :delete

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

  test "many_to_many" do
    changeset_meta = __MODULE__.P1.__changeset__()

    assert changeset_meta.related_projects ==
             {:assoc,
              %Ecto.Association.ManyToMany{
                cardinality: :many,
                defaults: [],
                field: :related_projects,
                on_cast: nil,
                on_replace: :delete,
                ordered: false,
                owner: Brando.Blueprint.RelationsTest.P1,
                owner_key: :id,
                queryable: Brando.Blueprint.RelationsTest.P1,
                related: Brando.Blueprint.RelationsTest.P1,
                relationship: :child,
                unique: false,
                where: [],
                join_defaults: [],
                join_keys: [project_id: :id, related_project_id: :id],
                join_through: "projects_related",
                join_where: [],
                on_delete: :delete_all
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
