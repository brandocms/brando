defmodule Brando.Content.ModuleDiffTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Module
  alias Brando.Content.ModuleDiff
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Villain.Blocks

  defp module(attrs \\ %{}) do
    struct(
      %Module{
        id: 1,
        uid: "modmodmodmod",
        name: %{"en" => "Test"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "help"},
        class: "test",
        code: "<div>{% ref refs.h2 %}</div>",
        version: 1,
        refs: [],
        vars: []
      },
      attrs
    )
  end

  defp ref(name, data) do
    %Ref{name: name, uid: "uid-#{name}", data: data}
  end

  defp header_ref(name \\ "h2") do
    ref(name, %Blocks.HeaderBlock{
      type: "header",
      data: %Blocks.HeaderBlock.Data{level: 2, text: "Heading"}
    })
  end

  defp picture_ref(name \\ "h2") do
    ref(name, %Blocks.PictureBlock{type: "picture", data: %Blocks.PictureBlock.Data{}})
  end

  defp var(key, type \\ :string), do: %Var{key: key, type: type, label: key}

  describe "classify/1 — every diff class" do
    test "no change at all" do
      old = module()
      diff = ModuleDiff.diff(old, module())

      assert ModuleDiff.classify(diff) == :none
      refute ModuleDiff.effective?(diff)
      refute ModuleDiff.destructive?(diff)
    end

    test "metadata only" do
      diff = ModuleDiff.diff(module(), module(%{name: %{"en" => "Renamed"}}))

      assert ModuleDiff.classify(diff) == :metadata
      assert ModuleDiff.effective?(diff)
      refute ModuleDiff.destructive?(diff)
      assert diff.metadata_changed?
    end

    test "code change is render-only" do
      diff = ModuleDiff.diff(module(), module(%{code: "<p>new</p>"}))

      assert ModuleDiff.classify(diff) == :render
      assert diff.code_changed?
    end

    test "class change is render-only, not metadata" do
      diff = ModuleDiff.diff(module(), module(%{class: "other"}))

      assert ModuleDiff.classify(diff) == :render
      refute diff.metadata_changed?
    end

    test "adding a ref is compatible" do
      old = module()
      new = module(%{refs: [header_ref()]})
      diff = ModuleDiff.diff(old, new)

      assert ModuleDiff.classify(diff) == :compatible
      assert diff.added_refs == ["h2"]
      refute ModuleDiff.destructive?(diff)
    end

    test "adding a var is compatible" do
      diff = ModuleDiff.diff(module(), module(%{vars: [var("title")]}))

      assert ModuleDiff.classify(diff) == :compatible
      assert diff.added_vars == ["title"]
    end

    test "removing a ref is destructive" do
      old = module(%{refs: [header_ref()]})
      diff = ModuleDiff.diff(old, module())

      assert ModuleDiff.classify(diff) == :destructive
      assert diff.removed_refs == ["h2"]
      assert ModuleDiff.destructive?(diff)
    end

    test "removing a var is destructive" do
      old = module(%{vars: [var("title")]})
      diff = ModuleDiff.diff(old, module())

      assert ModuleDiff.classify(diff) == :destructive
      assert diff.removed_vars == ["title"]
    end

    test "retyping a ref is destructive" do
      old = module(%{refs: [header_ref()]})
      new = module(%{refs: [picture_ref()]})
      diff = ModuleDiff.diff(old, new)

      assert ModuleDiff.classify(diff) == :destructive

      assert diff.retyped_refs == [
               {"h2", Blocks.HeaderBlock, Blocks.PictureBlock}
             ]

      assert diff.removed_refs == []
      assert diff.added_refs == []
    end

    test "a media ref backing a picture is not a retype" do
      # `media` is a slot: one module ref legitimately drives a picture, video,
      # gallery or svg block ref, and each of those reads its own template out of
      # the media source. Flagging that as destructive would put a confirmation
      # dialog in front of every media module edit.
      media = ref("hero", %Blocks.MediaBlock{type: "media", data: %Blocks.MediaBlock.Data{}})

      old = module(%{refs: [media]})
      new = module(%{refs: [picture_ref("hero")]})

      diff = ModuleDiff.diff(old, new)

      assert diff.retyped_refs == []
      refute ModuleDiff.destructive?(diff)
    end

    test "retyping a var is destructive" do
      old = module(%{vars: [var("title", :string)]})
      new = module(%{vars: [var("title", :boolean)]})
      diff = ModuleDiff.diff(old, new)

      assert ModuleDiff.classify(diff) == :destructive
      assert diff.retyped_vars == [{"title", :string, :boolean}]
    end

    test "a rename reads as remove plus add, and is destructive" do
      old = module(%{refs: [header_ref("h2")]})
      new = module(%{refs: [header_ref("heading")]})
      diff = ModuleDiff.diff(old, new)

      assert diff.removed_refs == ["h2"]
      assert diff.added_refs == ["heading"]
      assert ModuleDiff.classify(diff) == :destructive
    end

    test "contract fields are destructive even when flipping from a falsey value" do
      for {field, from, to} <- [
            {:multi, false, true},
            {:multi, nil, true},
            {:datasource, false, true},
            {:table_template_id, nil, 3},
            {:type, :liquid, :heex},
            {:datasource_type, nil, :list}
          ] do
        diff = ModuleDiff.diff(module(%{field => from}), module(%{field => to}))

        assert ModuleDiff.destructive?(diff),
               "expected #{field} #{inspect(from)} -> #{inspect(to)} to be destructive"

        assert {field, from, to} in diff.contract_changes
      end
    end

    test "an unset contract field settling to its off value is not a change" do
      # A module created through the admin stores `multi: nil` until the checkbox
      # is touched, and the form posts `false` on the first save. Reading that as
      # a contract change put the confirmation dialog in front of the first save
      # of every new module.
      for {from, to} <- [{nil, false}, {false, nil}, {nil, nil}] do
        diff = ModuleDiff.diff(module(%{multi: from}), module(%{multi: to}))

        assert diff.contract_changes == [],
               "expected multi #{inspect(from)} -> #{inspect(to)} to be no change"

        assert ModuleDiff.classify(diff) == :none
      end
    end

    test "an unset string field settling to an empty string is not a change" do
      diff = ModuleDiff.diff(module(%{datasource_module: nil}), module(%{datasource_module: ""}))

      assert ModuleDiff.classify(diff) == :none
    end

    test "destructive wins over compatible when both are present" do
      old = module(%{refs: [header_ref("h2")], vars: [var("title")]})
      new = module(%{refs: [header_ref("h3")], vars: [var("title"), var("subtitle")]})
      diff = ModuleDiff.diff(old, new)

      assert ModuleDiff.classify(diff) == :destructive
      assert diff.added_vars == ["subtitle"]
      assert diff.removed_refs == ["h2"]
    end
  end

  describe "diff/2 with a changeset" do
    test "applies pending changes before comparing" do
      old = module(%{refs: [header_ref()]})

      changeset =
        old
        |> Ecto.Changeset.change(%{code: "<p>gone</p>"})
        |> Ecto.Changeset.put_assoc(:refs, [])

      diff = ModuleDiff.diff(old, changeset)

      assert diff.removed_refs == ["h2"]
      assert diff.code_changed?
      assert ModuleDiff.destructive?(diff)
    end
  end

  describe "unloaded associations" do
    test "are treated as empty rather than crashing" do
      old = %{module() | refs: %Ecto.Association.NotLoaded{}, vars: %Ecto.Association.NotLoaded{}}
      diff = ModuleDiff.diff(old, old)

      assert ModuleDiff.classify(diff) == :none
    end
  end

  describe "summary/1" do
    test "is empty for a non-destructive diff" do
      assert ModuleDiff.summary(ModuleDiff.diff(module(), module(%{code: "x"}))) == []
    end

    test "names each orphaned reference and variable" do
      old = module(%{refs: [header_ref("h2"), picture_ref("img")], vars: [var("title")]})
      new = module(%{refs: [picture_ref("img")], vars: [var("title", :boolean)], multi: true})

      summary = ModuleDiff.summary(ModuleDiff.diff(old, new))

      assert ~s(Reference "h2" was removed) in summary
      assert ~s(Variable "title" changed from string to boolean) in summary
      assert ~s("multi" changed from none to true) in summary
    end

    test "uses the editor-facing block type name when a reference is retyped" do
      old = module(%{refs: [header_ref("hero")]})
      new = module(%{refs: [picture_ref("hero")]})

      assert ModuleDiff.summary(ModuleDiff.diff(old, new)) == [
               ~s(Reference "hero" changed from header to picture)
             ]
    end
  end
end
