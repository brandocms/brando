defmodule Brando.Translations.ComputePendingTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias Brando.Translations.Sync
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock

  # --- Builders -------------------------------------------------------------

  defp text_ref(name, text),
    do: %Ref{name: name, uid: uid(), data: %TextBlock{type: "text", data: %TextBlock.Data{text: text}}}

  defp picture_ref(name, image_id, alt) do
    %Ref{
      name: name,
      uid: uid(),
      image_id: image_id,
      data: %PictureBlock{type: "picture", data: %PictureBlock.Data{alt: alt}}
    }
  end

  defp block(sync_uid, opts \\ []) do
    %Block{
      id: opts[:id],
      uid: opts[:uid] || uid(),
      sync_uid: sync_uid,
      type: :module,
      module_id: 1,
      sequence: opts[:sequence] || 0,
      refs: opts[:refs] || [],
      vars: opts[:vars] || [],
      table_rows: opts[:table_rows] || [],
      children: opts[:children] || [],
      block_identifiers: []
    }
  end

  defp article(language, opts) do
    blocks =
      opts
      |> Keyword.get(:blocks, [])
      |> Enum.with_index()
      |> Enum.map(fn {block, index} ->
        %Article.Blocks{id: block.id, sequence: index, block: %{block | sequence: index}}
      end)

    %Article{
      id: opts[:id] || 1,
      language: language,
      title: opts[:title] || "Tittel",
      subtitle: opts[:subtitle],
      slug: "slug",
      year: opts[:year] || 2020,
      featured: opts[:featured] || false,
      cover_id: opts[:cover_id],
      entry_blocks: blocks,
      items: opts[:items] || []
    }
  end

  defp uid, do: Brando.Utils.generate_uid()

  defp compute(source, target, baseline, opts \\ []) do
    Sync.compute_pending(source, target, baseline, [schema: Article] ++ opts)
  end

  defp baseline(entry), do: Sync.baseline_for(entry, Article)

  defp kinds(result), do: result.work_items |> Enum.map(&{&1.kind, &1.path}) |> Enum.sort()

  defp payload_texts(result) do
    Enum.map(result.payload.entry_blocks, fn join -> {join.block.sync_uid, hd(join.block.refs).data.data.text} end)
  end

  # A source and its translation, as `create_target/4` leaves them after the
  # translator has worked: same sync identities, translated text.
  defp pair do
    source =
      article(:no,
        title: "Tittel",
        blocks: [
          block("a", refs: [text_ref("body", "Første")]),
          block("b", refs: [text_ref("body", "Andre")])
        ]
      )

    target =
      article(:en,
        id: 2,
        title: "Title",
        blocks: [
          block("a", id: 10, refs: [text_ref("body", "First")]),
          block("b", id: 11, refs: [text_ref("body", "Second")])
        ]
      )

    {source, target, baseline(source)}
  end

  # --- Tests ----------------------------------------------------------------

  test "nothing changed in the source gives no pending version" do
    {source, target, base} = pair()
    result = compute(source, target, base)

    assert result.work_items == []
    refute result.changed?
  end

  test "an added block is copied with source text and needs translation" do
    {source, target, base} = pair()
    new_block = block("c", refs: [text_ref("body", "Tredje")])
    source = %{source | entry_blocks: source.entry_blocks ++ [%Article.Blocks{sequence: 2, block: new_block}]}

    result = compute(source, target, base)

    assert result.changed?
    assert {:translate, "entry_blocks/c/refs/body/text"} in kinds(result)
    assert payload_texts(result) == [{"a", "First"}, {"b", "Second"}, {"c", "Tredje"}]

    [_, _, added] = result.payload.entry_blocks
    assert is_nil(added.id)
    assert is_nil(added.block.id)
    assert added.block.sync_uid == "c"
    refute added.block.uid == new_block.uid
  end

  test "an added block without text raises no translation work" do
    {source, target, base} = pair()
    source = %{source | entry_blocks: source.entry_blocks ++ [%Article.Blocks{sequence: 2, block: block("c")}]}

    result = compute(source, target, base)

    assert result.changed?
    assert result.work_items == [] or Enum.all?(result.work_items, &(&1.kind != :translate))
  end

  test "a removed block is dropped without work" do
    {source, target, base} = pair()
    source = %{source | entry_blocks: [hd(source.entry_blocks)]}

    result = compute(source, target, base)

    assert result.changed?
    assert result.work_items == []
    assert payload_texts(result) == [{"a", "First"}]
  end

  test "reordering keeps translations and raises no work" do
    {source, target, base} = pair()
    [a, b] = source.entry_blocks
    source = %{source | entry_blocks: [%{b | sequence: 0}, %{a | sequence: 1}]}

    result = compute(source, target, base)

    assert result.changed?
    assert result.work_items == []
    assert payload_texts(result) == [{"b", "Second"}, {"a", "First"}]
    assert Enum.map(result.payload.entry_blocks, & &1.id) == [11, 10]
    assert Enum.map(result.payload.entry_blocks, & &1.sequence) == [0, 1]
  end

  test "changed source text keeps the translation and asks for review" do
    {source, target, base} = pair()
    [a, b] = source.entry_blocks
    a = put_in(a.block.refs, [text_ref("body", "Første, endret")])
    source = %{source | entry_blocks: [a, b]}

    result = compute(source, target, base)

    assert kinds(result) == [{:review, "entry_blocks/a/refs/body/text"}]
    assert payload_texts(result) == [{"a", "First"}, {"b", "Second"}]
  end

  test "a minor correction raises no review, but still translates new content" do
    {source, target, base} = pair()
    [a, b] = source.entry_blocks
    a = put_in(a.block.refs, [text_ref("body", "Første!")])
    c = %Article.Blocks{sequence: 2, block: block("c", refs: [text_ref("body", "Ny")])}
    source = %{source | entry_blocks: [a, b, c]}

    result = compute(source, target, base, minor: true)

    assert kinds(result) == [{:translate, "entry_blocks/c/refs/body/text"}]
    # The corrected text is now the baseline, so the next save does not flag it.
    assert compute(source, target, result.baseline) |> kinds() == [{:translate, "entry_blocks/c/refs/body/text"}]
  end

  test "changed entry text asks for review; the translated title is kept" do
    {source, target, base} = pair()
    result = compute(%{source | title: "Ny tittel"}, target, base)

    assert kinds(result) == [{:review, "title"}]
    assert result.payload.title == "Title"
  end

  test "source-controlled fields and media follow the source" do
    {source, target, base} = pair()
    source = %{source | year: 2024, cover_id: 7}

    result = compute(source, target, base)

    assert result.payload.year == 2024
    assert result.payload.cover_id == 7
    assert {:shared_update, "year"} in kinds(result)
    assert {:shared_update, "cover"} in kinds(result)
  end

  test "other values are language-specific" do
    {source, target, base} = pair()
    result = compute(%{source | featured: true}, %{target | year: 2020}, base)

    refute result.payload.featured
    assert result.work_items == []
  end

  test "a picture keeps its translated alt text while its image follows the source" do
    source = article(:no, blocks: [block("a", refs: [picture_ref("photo", 1, "Hund")])])
    target = article(:en, id: 2, year: 2020, blocks: [block("a", id: 10, refs: [picture_ref("photo", 1, "Dog")])])
    base = baseline(source)
    source = article(:no, blocks: [block("a", refs: [picture_ref("photo", 2, "Hund")])])

    result = compute(source, target, base)
    [join] = result.payload.entry_blocks
    [ref] = join.block.refs

    assert ref.image_id == 2
    assert ref.data.data.alt == "Dog"
    assert kinds(result) == [{:shared_update, "entry_blocks/a/refs/photo/media"}]
  end

  test "nested blocks follow the source's nesting and keep their translations" do
    child_no = block("child", refs: [text_ref("body", "Barn")])
    child_en = block("child", id: 20, refs: [text_ref("body", "Child")])

    source = article(:no, blocks: [block("container", children: [child_no]), block("other")])

    target =
      article(:en, id: 2, year: 2020, blocks: [block("container", id: 10, children: [child_en]), block("other", id: 11)])

    base = baseline(source)

    # Move the child from the container into the other block.
    moved = article(:no, blocks: [block("container"), block("other", children: [child_no])])
    result = compute(moved, target, base)

    [container, other] = result.payload.entry_blocks
    assert container.block.children == []
    assert [%{id: 20} = child] = other.block.children
    assert hd(child.refs).data.data.text == "Child"
    assert result.work_items == []
  end

  test "vars match by key and table rows by sync_uid" do
    var = fn key, value -> %Var{key: key, type: :string, value: value, label: key} end
    row = fn sync_uid, value -> %TableRow{sync_uid: sync_uid, vars: [var.("cell", value)]} end

    source = article(:no, blocks: [block("t", vars: [var.("heading", "Overskrift")], table_rows: [row.("r1", "En")])])

    target =
      article(:en,
        id: 2,
        year: 2020,
        blocks: [block("t", id: 10, vars: [var.("heading", "Heading")], table_rows: [row.("r1", "One")])]
      )

    base = baseline(source)

    source =
      article(:no,
        blocks: [block("t", vars: [var.("heading", "Overskrift")], table_rows: [row.("r1", "En"), row.("r2", "To")])]
      )

    result = compute(source, target, base)
    [join] = result.payload.entry_blocks

    assert hd(join.block.vars).value == "Heading"
    assert Enum.map(join.block.table_rows, &hd(&1.vars).value) == ["One", "To"]
    assert kinds(result) == [{:translate, "entry_blocks/t/rows/r2/vars/cell/value"}]
  end

  test "subform rows match by uid" do
    item = fn uid, label -> %ArticleItem{uid: uid, label: label, link: "/x"} end
    source = article(:no, items: [item.("i1", "En"), item.("i2", "To")])
    target = article(:en, id: 2, year: 2020, items: [item.("i1", "One"), item.("i2", "Two")])
    base = baseline(source)

    source = %{source | items: [item.("i2", "To"), item.("i3", "Tre")]}
    result = compute(source, target, base)

    assert Enum.map(result.payload.items, & &1.label) == ["Two", "Tre"]
    # Both are `:text` inputs in the subform.
    assert kinds(result) == [{:translate, "items/i3/label"}, {:translate, "items/i3/link"}]
  end

  test "repeated source saves keep completed translations" do
    {source, target, base} = pair()
    [a, b] = source.entry_blocks
    c = %Article.Blocks{sequence: 2, block: block("c", refs: [text_ref("body", "Tredje")])}
    source = %{source | entry_blocks: [a, b, c]}

    first = compute(source, target, base)

    # The translator saves the pending version with "c" translated.
    translated =
      update_in(first.payload.entry_blocks, fn joins ->
        Enum.map(joins, fn
          %{block: %{sync_uid: "c"} = block} = join -> %{join | block: %{block | refs: [text_ref("body", "Third")]}}
          join -> join
        end)
      end)

    second = compute(source, translated.payload, first.baseline)

    assert payload_texts(second) == [{"a", "First"}, {"b", "Second"}, {"c", "Third"}]
    assert second.work_items == []
  end

  test "a sync_uid copied onto two blocks in one entry does not merge them" do
    source =
      article(:no, blocks: [block("a", refs: [text_ref("body", "En")]), block("a", refs: [text_ref("body", "To")])])

    target = article(:en, id: 2, year: 2020, blocks: [block("a", id: 10, refs: [text_ref("body", "One")])])

    result = compute(source, target, baseline(source))

    assert [{"a", "One"}, {_other, "To"}] = payload_texts(result)
  end

  test "links map to the target language, and wait when there is no version yet" do
    link = fn id -> %Brando.Content.BlockIdentifier{identifier_id: id, sequence: 0} end
    var = %Var{key: "cta", type: :link, link_type: :identifier, identifier_id: 3, label: "cta"}

    source = article(:no, blocks: [block("a", vars: [var])])

    source =
      put_in(source.entry_blocks, [
        %{hd(source.entry_blocks) | block: %{hd(source.entry_blocks).block | block_identifiers: [link.(1), link.(2)]}}
      ])

    target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [%{var | identifier_id: 33}])])

    result = compute(source, target, baseline(source), identifiers: %{1 => 11, 2 => nil, 3 => 33})
    [join] = result.payload.entry_blocks

    assert Enum.map(join.block.block_identifiers, & &1.identifier_id) == [11]
    assert hd(join.block.vars).identifier_id == 33

    assert {:awaiting_translation, "entry_blocks/a/identifiers/2"} in kinds(result)
    assert {:shared_update, "entry_blocks/a/identifiers"} in kinds(result)
    refute Enum.any?(result.work_items, &(&1.path == "entry_blocks/a/vars/cta/media"))
  end
end
