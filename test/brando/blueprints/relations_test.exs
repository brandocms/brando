defmodule Brando.Blueprint.RelationsTest do
  use ExUnit.Case
  use Brando.ConnCase

  test "belongs_to" do
    changeset_meta = Brando.BlueprintTest.P1.__changeset__()

    assert changeset_meta.creator ==
             {:assoc,
              %Ecto.Association.BelongsTo{
                cardinality: :one,
                defaults: [],
                field: :creator,
                on_cast: nil,
                on_replace: :raise,
                ordered: false,
                owner: Brando.BlueprintTest.P1,
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
    changeset_meta = Brando.BlueprintTest.P1.__changeset__()

    assert changeset_meta.project_contributors ==
             {:assoc,
              %Ecto.Association.Has{
                cardinality: :many,
                field: :project_contributors,
                owner: Brando.BlueprintTest.P1,
                related: Brando.BlueprintTest.P1.ProjectContributor,
                owner_key: :id,
                related_key: :p1_id,
                on_cast: nil,
                queryable: Brando.BlueprintTest.P1.ProjectContributor,
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
    changeset_meta = Brando.BlueprintTest.P1.__changeset__()

    assert changeset_meta.property ==
             {:embed,
              %Ecto.Embedded{
                cardinality: :one,
                field: :property,
                on_cast: nil,
                on_replace: :update,
                ordered: true,
                owner: Brando.BlueprintTest.P1,
                related: Brando.BlueprintTest.P1.Property,
                unique: true
              }}
  end

  test "embeds_many" do
    changeset_meta = Brando.BlueprintTest.P1.__changeset__()

    assert changeset_meta.properties ==
             {:embed,
              %Ecto.Embedded{
                cardinality: :many,
                field: :properties,
                on_cast: nil,
                on_replace: :delete,
                ordered: true,
                owner: Brando.BlueprintTest.P1,
                related: Brando.BlueprintTest.P1.Property,
                unique: true
              }}
  end

  test "required_attrs" do
    required_attrs = Brando.BlueprintTest.P1.__required_attrs__()
    assert required_attrs == [:title]
  end

  test "required_relations" do
    required_relations = Brando.BlueprintTest.P1.__required_relations__()
    assert required_relations == [:location_id, :creator_id]
  end
end
