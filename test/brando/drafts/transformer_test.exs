defmodule Brando.Drafts.TransformerTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.Var
  alias Brando.Drafts.Params
  alias BrandoAdmin.Components.Form.Transformer

  test "restored new rows display existing assets and save without duplicating them" do
    user = Brando.Factory.insert(:random_user)
    image = Brando.Factory.insert(:image)
    image_count = Brando.Repo.aggregate(Brando.Images.Image, :count)
    params = %{"type" => "image", "key" => "photo", "label" => "Photo", "image_id" => image.id}
    cs = Var.changeset(%Var{}, params, user)
    first = Transformer.recovery_item(cs, [:image])
    second = Transformer.recovery_item(cs, [:image])
    assert first.is_new
    refute is_struct(first.source)
    assert first.dom_id != second.dom_id
    assert first.assets.image.id == image.id
    assert Params.snapshot(first.source)["image_id"] == image.id

    saved = %Var{} |> Var.changeset(Map.merge(first.source, first.changes), user) |> Brando.Repo.insert!()
    assert saved.image_id == image.id
    assert Brando.Repo.aggregate(Brando.Images.Image, :count) == image_count
  end

  test "restored rows retain raw invalid values and resolve a changed asset FK" do
    user = Brando.Factory.insert(:random_user)
    old = Brando.Factory.insert(:image)
    selected = Brando.Factory.insert(:image)
    entry = %Var{id: 123, image_id: old.id, image: old, sequence: 0}
    cs = Var.changeset(entry, %{"image_id" => selected.id, "sequence" => "unfinished"}, user)
    item = Transformer.recovery_item(cs, [:image])
    refute item.is_new
    assert item.changes.sequence == "unfinished"
    assert item.assets.image.id == selected.id
  end
end
