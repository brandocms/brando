defmodule Brando.Blueprint.PreloadsTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.AssetPreloads
  alias Brando.Blueprint.Preloads
  alias Brando.Blueprint.RelationPreloads

  defmodule DescendingOwner do
    @moduledoc false

    use Brando.Blueprint,
      application: "Brando",
      domain: "PreloadsTest",
      schema: "DescendingOwner",
      singular: "descending_owner",
      plural: "descending_owners",
      gettext_module: Brando.Gettext

    relations do
      relation :contributors, :has_many,
        module: Brando.BlueprintTest.P1.Contributor,
        cast: true,
        preload_order: [desc: :sequence]
    end
  end

  test "complete relation preloads include direct has-one associations and their relations" do
    preloads = RelationPreloads.for_schema(Brando.Navigation.Item)

    assert {:link, link_preloads} = List.keyfind(preloads, :link, 0)
    assert :image in link_preloads
  end

  test "cast has-many preloads preserve the declared order" do
    assert [{:contributors, %Ecto.Query{} = query}] =
             RelationPreloads.for_schema(DescendingOwner)

    assert [%Ecto.Query.ByExpr{expr: [desc: _sequence_expression]}] = query.order_bys
  end

  test "sequenced cast children default to ascending sequence" do
    assert {:project_contributors, %Ecto.Query{} = query} =
             Brando.BlueprintTest.P1
             |> RelationPreloads.for_schema()
             |> List.keyfind(:project_contributors, 0)

    assert [%Ecto.Query.ByExpr{expr: [asc: _sequence_expression]}] = query.order_bys
    assert query.preloads == [:contributor]
  end

  test "cast one-to-one preloads include the related entry's own assets" do
    assert {:author, [:portrait]} in RelationPreloads.for_schema(Brando.SyncTest.Article)
    # A cast belongs_to whose schema has no assets or relations of its own
    assert :location in RelationPreloads.for_schema(Brando.BlueprintTest.P1)
  end

  test "complete preloads retain entry identifiers and direct assets" do
    assert {:related_entries, [:identifier]} in Preloads.for_schema(Brando.Persons.Person, skip_blocks: true)

    assert AssetPreloads.for_schema(Brando.BlueprintTest.P1) == [:image]
  end
end
