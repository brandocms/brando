defmodule BrandoAdmin.Components.Form.BlockField.OutlineTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.BlockField.Outline

  describe "build_outline_items/1" do
    test "returns empty list for nil" do
      assert Outline.build_outline_items(nil) == []
    end

    test "returns empty list for empty list" do
      assert Outline.build_outline_items([]) == []
    end
  end

  describe "build_outline_item_from_struct/1" do
    test "builds item from a Block struct" do
      block = %Brando.Content.Block{
        uid: "test-uid-1",
        type: :module,
        module_id: nil,
        description: "Test block",
        active: true,
        multi: false,
        children: []
      }

      item = Outline.build_outline_item_from_struct(block)

      assert item.uid == "test-uid-1"
      assert item.type == :module
      assert item.description == "Test block"
      assert item.active == true
      assert item.multi == false
      assert item.module_color == :blue
      assert item.children == []
    end

    test "builds nested children recursively" do
      child = %Brando.Content.Block{
        uid: "child-uid-1",
        type: :module_entry,
        module_id: nil,
        description: nil,
        active: true,
        multi: false,
        children: []
      }

      block = %Brando.Content.Block{
        uid: "parent-uid-1",
        type: :module,
        module_id: nil,
        description: "Multi block",
        active: true,
        multi: true,
        children: [child]
      }

      item = Outline.build_outline_item_from_struct(block)

      assert item.uid == "parent-uid-1"
      # multi comes from module lookup, not block struct — nil module_id resolves to false
      assert item.multi == false
      assert length(item.children) == 1

      [child_item] = item.children
      assert child_item.uid == "child-uid-1"
      assert child_item.type == :module_entry
      assert child_item.children == []
    end

    test "handles NotLoaded children gracefully" do
      block = %Brando.Content.Block{
        uid: "uid-1",
        type: :container,
        module_id: nil,
        description: nil,
        active: true,
        multi: false,
        children: %Ecto.Association.NotLoaded{
          __field__: :children,
          __owner__: Brando.Content.Block,
          __cardinality__: :many
        }
      }

      item = Outline.build_outline_item_from_struct(block)

      assert item.uid == "uid-1"
      assert item.type == :container
      assert item.children == []
    end

    test "handles nil children" do
      block = %Brando.Content.Block{
        uid: "uid-2",
        type: :module,
        module_id: nil,
        description: nil,
        active: true,
        multi: false,
        children: nil
      }

      item = Outline.build_outline_item_from_struct(block)
      assert item.children == []
    end

    test "inactive block is marked inactive" do
      block = %Brando.Content.Block{
        uid: "uid-3",
        type: :module,
        module_id: nil,
        description: nil,
        active: false,
        multi: false,
        children: []
      }

      item = Outline.build_outline_item_from_struct(block)
      assert item.active == false
    end
  end
end
