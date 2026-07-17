defmodule Brando.Blueprint.RelationsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Blueprint.Relations
  alias Brando.Blueprint.Relations.Relation
  alias Ecto.Changeset

  defmodule Tag do
    @moduledoc false
    use Ecto.Schema

    schema "relation_contract_tags" do
      field :name, :string
    end
  end

  defmodule Owner do
    @moduledoc false
    use Ecto.Schema

    schema "relation_contract_owners" do
      many_to_many :tags, Tag, join_through: "relation_contract_owners_tags"
    end
  end

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

  describe "required collection casting" do
    test "an empty has-many value cannot bypass required validation" do
      relation = %Relation{
        name: :project_contributors,
        type: :has_many,
        opts: %{
          cast: true,
          module: Brando.BlueprintTest.P1.ProjectContributor,
          required: true
        }
      }

      changeset =
        Changeset.cast(
          %Brando.BlueprintTest.P1{},
          %{"project_contributors" => ""},
          []
        )

      result = Relations.run_cast_relation(relation, changeset, nil)

      refute result.valid?
      assert {"can't be blank", [validation: :required]} = result.errors[:project_contributors]
    end

    test "an empty entries value cannot bypass required validation" do
      relation =
        Brando.Persons.Person
        |> Relations.__relation__(:related_entries)
        |> update_in([Access.key(:opts)], fn opts ->
          opts
          |> Map.put(:required, true)
          |> Map.put(:required_message, "select at least one entry")
        end)

      changeset =
        Changeset.cast(
          %Brando.Persons.Person{},
          %{"related_entries" => ""},
          []
        )

      result = Relations.run_cast_relation(relation, changeset, nil)

      refute result.valid?
      assert {"select at least one entry", [validation: :required]} = result.errors[:related_entries]
    end

    test "empty optional collections still clear existing associations" do
      has_many_relation = %Relation{
        name: :project_contributors,
        type: :has_many,
        opts: %{
          cast: true,
          module: Brando.BlueprintTest.P1.ProjectContributor
        }
      }

      entries_relation = Relations.__relation__(Brando.Persons.Person, :related_entries)

      has_many_changeset =
        Changeset.cast(
          %Brando.BlueprintTest.P1{},
          %{"project_contributors" => ""},
          []
        )

      entries_changeset =
        Changeset.cast(
          %Brando.Persons.Person{},
          %{"related_entries" => ""},
          []
        )

      assert [] ==
               has_many_changeset
               |> then(&Relations.run_cast_relation(has_many_relation, &1, nil))
               |> Changeset.get_change(:project_contributors)

      assert [] ==
               entries_changeset
               |> then(&Relations.run_cast_relation(entries_relation, &1, nil))
               |> Changeset.get_change(:related_entries)
    end

    test "an empty many-to-many value uses the same required contract" do
      relation = %Relation{
        name: :tags,
        type: :many_to_many,
        opts: %{
          cast: true,
          module: Tag,
          required: true,
          required_message: "select at least one tag"
        }
      }

      changeset = Changeset.cast(%Owner{}, %{"tags" => ""}, [])
      result = Relations.run_cast_relation(relation, changeset, nil)

      refute result.valid?
      assert {"select at least one tag", [validation: :required]} = result.errors[:tags]
    end
  end
end
