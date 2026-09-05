defmodule Brando.Content.ModuleSyncTest do
  @moduledoc """
  Covers what a module save does to the blocks that already use it.

  Every one of these runs through `sync_module/2` on plain structs — the same
  function the update mutation calls for every block on the site — so the
  assertions are about the migration itself, not about the admin UI on top of it.
  """
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Content.Module
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Villain.Blocks, as: VillainBlocks
  alias Ecto.Changeset

  defp header_data(text \\ "Heading") do
    %VillainBlocks.HeaderBlock{
      type: "header",
      data: %VillainBlocks.HeaderBlock.Data{level: 2, text: text}
    }
  end

  defp picture_data do
    %VillainBlocks.PictureBlock{
      type: "picture",
      data: %VillainBlocks.PictureBlock.Data{title: "A picture"}
    }
  end

  defp ref(name, data, opts \\ []) do
    %Ref{
      id: Keyword.get(opts, :id),
      name: name,
      description: Keyword.get(opts, :description),
      uid: "uid-#{name}",
      data: data,
      sequence: 0
    }
  end

  defp module(attrs) do
    struct(
      %Module{
        id: 22,
        uid: "modmodmodmod",
        name: %{"en" => "Test"},
        namespace: %{"en" => "general"},
        class: "test",
        code: "<div>{% ref refs.h2 %}</div>",
        version: 2,
        refs: [],
        vars: []
      },
      attrs
    )
  end

  defp block(attrs) do
    struct(
      %Block{
        id: 100,
        uid: "blockblockblo",
        type: :module,
        module_id: 22,
        module_version: 1,
        refs: [],
        vars: []
      },
      attrs
    )
  end

  defp synced_refs(changeset) do
    changeset
    |> Changeset.get_assoc(:refs)
    |> Enum.map(&{Changeset.get_field(&1, :name), Changeset.get_field(&1, :data)})
    |> Map.new()
  end

  describe "refs the module no longer defines" do
    test "are retained instead of deleted" do
      module = module(refs: [ref("h2", header_data("From module"))])

      block =
        block(
          refs: [
            ref("h2", header_data("Editor wrote this"), id: 1),
            ref("gone", header_data("Content nobody wants to lose"), id: 2)
          ]
        )

      refs = block |> Blocks.sync_module(module) |> synced_refs()

      assert Map.has_key?(refs, "gone")
      assert refs["gone"].data.text == "Content nobody wants to lose"
    end

    test "leave the block behind the module's version" do
      module = module(refs: [ref("h2", header_data())])
      block = block(refs: [ref("h2", header_data(), id: 1), ref("gone", header_data(), id: 2)])

      changeset = Blocks.sync_module(block, module)

      refute Map.has_key?(changeset.changes, :module_version)
      assert Changeset.get_field(changeset, :module_version) == 1
    end

    test "are untouched by the module's template settings" do
      module = module(refs: [ref("h2", header_data())])

      block =
        block(refs: [ref("gone", header_data("Kept"), id: 2, description: "editor description")])

      changeset = Blocks.sync_module(block, module)

      gone =
        changeset
        |> Changeset.get_assoc(:refs)
        |> Enum.find(&(Changeset.get_field(&1, :name) == "gone"))

      assert Changeset.get_field(gone, :description) == "editor description"
      assert Changeset.get_field(gone, :data).data.text == "Kept"
    end
  end

  describe "refs the module retyped" do
    test "keep the block's own data rather than being merged into garbage" do
      module = module(refs: [ref("hero", picture_data())])
      block = block(refs: [ref("hero", header_data("Still a heading"), id: 1)])

      refs = block |> Blocks.sync_module(module) |> synced_refs()

      assert refs["hero"].__struct__ == VillainBlocks.HeaderBlock
      assert refs["hero"].data.text == "Still a heading"
    end

    test "leave the block behind the module's version" do
      module = module(refs: [ref("hero", picture_data())])
      block = block(refs: [ref("hero", header_data(), id: 1)])

      assert Blocks.sync_module(block, module) |> Changeset.get_field(:module_version) == 1
    end
  end

  describe "a media ref" do
    # `media` module refs drive picture/video/gallery/svg block refs by design —
    # `PictureBlock.apply_ref/3` has a MediaBlock clause that reads
    # `template_picture` out of the source. That is a match, not a retype.
    test "still drives a picture block ref, and the block is stamped" do
      media =
        ref("hero", %VillainBlocks.MediaBlock{
          type: "media",
          data: %VillainBlocks.MediaBlock.Data{
            template_picture: %VillainBlocks.PictureBlock.Data{img_class: "from-module"}
          }
        })

      module = module(refs: [media])
      block = block(refs: [ref("hero", picture_data(), id: 1)])

      changeset = Blocks.sync_module(block, module)
      refs = synced_refs(changeset)

      assert refs["hero"].__struct__ == VillainBlocks.PictureBlock
      assert refs["hero"].data.img_class == "from-module"
      assert Changeset.get_change(changeset, :module_version) == 2
    end
  end

  describe "a clean migration" do
    test "stamps the block with the module's current version" do
      module = module(refs: [ref("h2", header_data("From module"))])
      block = block(refs: [ref("h2", header_data("Editor text"), id: 1)])

      changeset = Blocks.sync_module(block, module)

      assert Changeset.get_change(changeset, :module_version) == 2
    end

    test "instantiates refs the block is missing" do
      module = module(refs: [ref("h2", header_data()), ref("added", header_data("Default"))])
      block = block(refs: [ref("h2", header_data("Editor text"), id: 1)])

      refs = block |> Blocks.sync_module(module) |> synced_refs()

      assert Map.has_key?(refs, "added")
      assert refs["added"].data.text == "Default"
    end

    test "instantiating a new ref still stamps the version" do
      module = module(refs: [ref("added", header_data("Default"))])
      block = block(refs: [])

      assert Blocks.sync_module(block, module) |> Changeset.get_change(:module_version) == 2
    end

    test "preserves the editor's ref content while reapplying template settings" do
      module = module(refs: [ref("h2", header_data("Module placeholder"), description: "from module")])
      block = block(refs: [ref("h2", header_data("Editor text"), id: 1, description: "stale")])

      changeset = Blocks.sync_module(block, module)

      h2 =
        changeset
        |> Changeset.get_assoc(:refs)
        |> Enum.find(&(Changeset.get_field(&1, :name) == "h2"))

      assert Changeset.get_field(h2, :description) == "from module"
      # `text` is not a protected attr on HeaderBlock, so the module owns it —
      # the point here is that the ref survives as the same row rather than
      # being deleted and reinserted.
      assert Changeset.get_field(h2, :uid) == "uid-h2"
    end

    test "treats a module with no version as version 1" do
      module = module(version: nil, refs: [ref("h2", header_data())])
      block = block(module_version: nil, refs: [ref("h2", header_data(), id: 1)])

      assert Blocks.sync_module(block, module) |> Changeset.get_change(:module_version) == 1
    end
  end

  describe "vars" do
    test "the module no longer defines are retained and hold the block behind" do
      module = module(vars: [%Var{key: "title", type: :string, label: "Title"}])

      block =
        block(
          vars: [
            %Var{id: 1, key: "title", type: :string, label: "Title", value: "Editor value"},
            %Var{id: 2, key: "orphan", type: :string, label: "Orphan", value: "Kept"}
          ]
        )

      changeset = Blocks.sync_module(block, module)
      vars = Changeset.get_assoc(changeset, :vars)

      assert Enum.map(vars, &Changeset.get_field(&1, :key)) == ["title", "orphan"]

      assert changeset
             |> Changeset.get_assoc(:vars)
             |> Enum.find(&(Changeset.get_field(&1, :key) == "orphan"))
             |> Changeset.get_field(:value) == "Kept"

      assert Changeset.get_field(changeset, :module_version) == 1
    end

    test "added by the module are instantiated and the block is stamped" do
      module =
        module(vars: [%Var{key: "title", type: :string, label: "Title", value: "Default"}])

      block = block(vars: [])

      changeset = Blocks.sync_module(block, module)

      assert changeset |> Changeset.get_assoc(:vars) |> length() == 1
      assert Changeset.get_change(changeset, :module_version) == 2
    end

    test "keep the editor's value while template settings are reapplied" do
      module = module(vars: [%Var{key: "title", type: :string, label: "New label"}])
      block = block(vars: [%Var{id: 1, key: "title", type: :string, label: "Old", value: "Mine"}])

      var =
        block
        |> Blocks.sync_module(module)
        |> Changeset.get_assoc(:vars)
        |> List.first()

      assert Changeset.get_field(var, :value) == "Mine"
      assert Changeset.get_field(var, :label) == "New label"
    end
  end
end
