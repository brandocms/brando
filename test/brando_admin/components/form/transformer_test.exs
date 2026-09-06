defmodule BrandoAdmin.Components.Form.TransformerTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest

  alias Brando.Blueprint.Forms.Subform
  alias BrandoAdmin.Components.Form.Transformer

  defmodule Item do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
    end
  end

  defmodule MediaItem do
    use Brando.Blueprint,
      application: "Brando",
      domain: "TransformerTest",
      schema: "MediaItem",
      singular: "media_item",
      plural: "media_items",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string
    end

    assets do
      asset :cover, :image, cfg: :default
    end
  end

  defmodule Collection do
    use Brando.Blueprint,
      application: "Brando",
      domain: "TransformerTest",
      schema: "Collection",
      singular: "collection",
      plural: "collections",
      gettext_module: Brando.Gettext

    relations do
      relation :items, :has_many, module: MediaItem
    end
  end

  test "a transformer without a summary renders its fields directly, including a requested grid" do
    field =
      %Collection{items: [%MediaItem{id: 1, title: "Editable caption", cover: nil}]}
      |> Ecto.Changeset.change()
      |> Phoenix.Component.to_form()
      |> Access.get(:items)

    subform = %Subform{
      name: :items,
      cardinality: :many,
      style: {:transformer, :cover},
      layout: :grid,
      sub_fields: [%Brando.Blueprint.Forms.Input{name: :title, type: :text, opts: [label: "Title"]}]
    }

    html =
      Phoenix.LiveViewTest.render_component(Transformer,
        id: "collection-items",
        field: field,
        subform: subform,
        form_id: "collection_form",
        current_user: %Brando.Users.User{language: "en"},
        label: "Items",
        instructions: nil
      )

    document = Floki.parse_fragment!(html)
    assert [_] = Floki.find(document, ".layout-list .subform-fields input[value='Editable caption']")
    assert [] = Floki.find(document, ".subform-edit")
    assert [] = Floki.find(document, ".modal")
  end

  test "builds a clean related record when no default is configured" do
    assert Transformer.build_default(%Subform{}, Item, %{title: "Parent"}, nil) == %{title: nil}
  end

  test "passes the parent and asset to an arity-2 default callback" do
    parent = %{title: "Parent"}
    asset = %{id: 42}

    subform = %Subform{
      default: fn received_parent, received_asset ->
        assert received_parent == parent
        assert received_asset == asset
        %Item{title: "Generated"}
      end
    }

    assert Transformer.build_default(subform, Item, parent, asset) == %{title: "Generated"}
  end

  test "retains explicit map defaults" do
    assert Transformer.build_default(%Subform{default: %{title: "Draft"}}, Item, %{}, nil) == %{
             title: "Draft"
           }
  end

  test "reports invalid callback return values" do
    subform = %Subform{default: fn _parent, _asset -> nil end}

    assert_raise ArgumentError, ~r/must return a map or struct, got: nil/, fn ->
      Transformer.build_default(subform, Item, %{}, nil)
    end
  end

  # Every item goes through the same render and the same save collection, so a
  # constructor that omits a key does not fail where it is written — it fails
  # later, inside render, as a KeyError with no obvious link to the upload that
  # produced it.
  describe "item shape" do
    @item_keys [:assets, :changes, :dom_id, :is_new, :pending, :source]

    test "a new item carries every key" do
      item = Transformer.new_item("transformer-item-new-1", %{})

      assert item |> Map.keys() |> Enum.sort() == @item_keys
      assert item.is_new
      assert item.assets == %{}
      refute item.pending
    end

    test "an existing row carries every key" do
      item = Transformer.new_item("transformer-item-1", %Item{}, is_new: false)

      assert item |> Map.keys() |> Enum.sort() == @item_keys
      refute item.is_new
    end

    test "an upload placeholder carries every key" do
      file = %{"ref" => "tf-abc123", "filename" => "photo.jpg", "size" => 1024, "kind" => "image"}
      item = Transformer.build_placeholder(file, %Subform{}, Item, %{})

      assert item |> Map.keys() |> Enum.sort() == @item_keys
      assert item.assets == %{}
      assert item.pending.ref == "tf-abc123"
      assert item.pending.kind == :image
      assert item.pending.status == :waiting
      assert item.pending.size == 1024
    end

    test "a video placeholder is tagged as video" do
      file = %{"ref" => "tf-abc124", "filename" => "clip.mp4", "size" => 2048, "kind" => "video"}

      assert Transformer.build_placeholder(file, %Subform{}, Item, %{}).pending.kind == :video
    end
  end

  describe "placeholder rejection" do
    test "refuses a ref that could not safely become a DOM id" do
      file = %{"ref" => "../../etc", "filename" => "x.jpg", "size" => 1, "kind" => "image"}

      refute Transformer.build_placeholder(file, %Subform{}, Item, %{})
    end

    test "refuses malformed entries rather than raising" do
      refute Transformer.build_placeholder(%{}, %Subform{}, Item, %{})
      refute Transformer.build_placeholder(%{"ref" => 1}, %Subform{}, Item, %{})
    end
  end
end
