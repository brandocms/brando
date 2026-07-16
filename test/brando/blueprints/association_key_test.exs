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
end
