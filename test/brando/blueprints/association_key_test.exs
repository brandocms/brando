defmodule Brando.Blueprint.AssociationKeyTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.AssociationKey

  doctest AssociationKey

  test "singular relation and asset types use foreign keys" do
    for type <- [:belongs_to, :file, :image, :video] do
      assert AssociationKey.for(%{type: type, name: :cover}) == :cover_id
    end
  end

  test "collection and embedded types retain their association names" do
    for type <- [:has_many, :many_to_many, :embeds_one, :embeds_many, :gallery] do
      assert AssociationKey.for(%{type: type, name: :items}) == :items
    end
  end

  test "belongs_to relations honor custom foreign keys" do
    relation = %{type: :belongs_to, name: :creator, opts: %{foreign_key: :owner_id}}

    assert AssociationKey.for(relation) == :owner_id
  end

  test "the Blueprint compatibility helpers use the canonical cast fields" do
    relations = [%{type: :belongs_to, name: :creator, opts: %{foreign_key: :owner_id}}]
    assets = [%{type: :image, name: :cover}, %{type: :gallery, name: :gallery}]

    assert Brando.Blueprint.get_castable_relation_fields(relations) == [:owner_id]
    assert Brando.Blueprint.get_castable_asset_fields(assets) == [:cover_id]
  end
end
