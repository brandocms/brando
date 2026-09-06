defmodule Brando.Villain.BlockSlotsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Content.Block
  alias Brando.Content.BlockSlots
  alias Brando.Content.Module, as: ContentModule
  alias Brando.Content.Ref
  alias Brando.Villain.Blocks.BlocksBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.Footnotes
  alias Brando.Villain.Parser

  defmodule SiteParser do
    use Brando.Villain.Parser
    def module(block, _opts), do: "<p>Module #{block.module_id}</p>"
  end

  defp slot(uid, name, ids) do
    %Block{
      uid: uid,
      type: :slot,
      slot_kind: :region,
      slot_name: name,
      children: Enum.map(ids, &%Block{uid: "child-#{&1}", type: :module, module_id: &1})
    }
  end

  test "named refs resolve independent subtrees, preserving site parser dispatch and ordering" do
    owner = %Block{children: [slot("left", "sidebar", [2, 1]), slot("right", "related", [3])]}

    refs =
      for name <- ["sidebar", "related"],
          do: %Ref{name: name, uid: "ref-#{name}", data: %BlocksBlock{data: %BlocksBlock.Data{}}}

    processed = Parser.process_refs(refs, owner, %{parser_module: SiteParser})
    assert processed["sidebar"].data.data.rendered_html == "<p>Module 2</p><p>Module 1</p>"
    assert processed["related"].data.data.rendered_html == "<p>Module 3</p>"
  end

  test "ref row replacement does not change region identity, and unmatched content remains owned" do
    owner = %Block{children: [slot("stable", "sidebar", [1])]}
    assert BlockSlots.named(owner, "sidebar").uid == "stable"
    refute BlockSlots.named(owner, "renamed")
    assert length(BlockSlots.children(owner)) == 1
  end

  test "preview placeholders are independently addressed and inactive children do not render" do
    region = slot("unique-slot", "sidebar", [1, 2])
    assert Parser.render_block_slot(region, %{skip_children: true, annotate_blocks: true}) =~ "[$ slot:unique-slot $]"
    [first, second] = region.children
    region = %{region | children: [%{first | active: false}, second]}
    assert Parser.render_block_slot(region, %{parser_module: SiteParser}) == "<p>Module 2</p>"
  end

  test "collection palettes reject multi modules and modules with nested regions" do
    assert BlockSlots.suitable_module?(%ContentModule{refs: []})
    refute BlockSlots.suitable_module?(%ContentModule{multi: true, refs: []})
    refute BlockSlots.suitable_module?(%ContentModule{refs: [%Ref{data: %BlocksBlock{}}]})
  end

  test "Liquid and HEEx refs render named regions and rich note bodies through the same parser" do
    for {type, code} <- [
          {:liquid, "<article>{% ref refs.text %}<aside>{% ref refs.sidebar %}</aside></article>"},
          {:heex,
           ~s(<article><.ref block={@block} ref={:text} /><aside><.ref block={@block} ref={:sidebar} /></aside></article>)}
        ] do
      owner_id = System.unique_integer([:positive])
      child_id = System.unique_integer([:positive])
      owner_module = %ContentModule{id: owner_id, type: type, code: code, datasource: false}
      child_module = %ContentModule{id: child_id, type: :liquid, code: "<p>A supporting source</p>", datasource: false}
      child = %Block{uid: "note-content", type: :module, module_id: child_id, refs: [], vars: [], children: []}
      note = %{slot("note", "text", []) | slot_kind: :footnote, children: [child]}
      region = %{slot("sidebar", "sidebar", []) | children: [%{child | uid: "sidebar-content"}]}

      owner = %Block{
        uid: "owner",
        type: :module,
        module_id: owner_id,
        vars: [],
        children: [note, region],
        refs: [
          %Ref{
            name: "text",
            data: %TextBlock{data: %TextBlock.Data{text: ~s(<p>Read more<sup data-footnote-uid="note">•</sup></p>)}}
          },
          %Ref{name: "sidebar", data: %BlocksBlock{data: %BlocksBlock.Data{}}}
        ]
      }

      opts = %{modules: [owner_module, child_module], context: Liquex.Context.new(%{}), parser_module: Parser}
      result = owner |> Parser.module(opts) |> Footnotes.render()
      assert result.html =~ "<aside><p>A supporting source</p></aside>"
      assert [%{uid: "note", number: 1, html: "<p>A supporting source</p>"}] = result.notes
      assert Footnotes.to_html(result) =~ ~s(role="doc-endnotes")
    end
  end
end
