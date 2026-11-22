defmodule Brando.Translations.ComputePendingTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.Galleries.Gallery
  alias Brando.Galleries.GalleryObject
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias Brando.Translations.Sync
  alias Brando.Villain.Blocks.GalleryBlock
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.Blocks.VideoBlock

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
      module_id: opts[:module_id] || 1,
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

  describe "the source's previous text" do
    test "a review item carries the text the translation was last synced against" do
      {source, target, base} = pair()
      texts = Sync.baseline_texts_for(source, Article)
      [a, b] = source.entry_blocks
      a = put_in(a.block.refs, [text_ref("body", "Første, endret")])

      result =
        compute(%{source | title: "Ny tittel", entry_blocks: [a, b]}, target, base, baseline_texts: texts)

      previous = Map.new(result.work_items, &{&1.path, &1.source_previous})
      assert previous == %{"title" => "Tittel", "entry_blocks/a/refs/body/text" => "Første"}
    end

    test "is left out without the texts of the last sync, and of other kinds of work" do
      {source, target, base} = pair()
      c = %Article.Blocks{sequence: 2, block: block("c", refs: [text_ref("body", "Ny")])}
      source = %{source | title: "Ny tittel", entry_blocks: source.entry_blocks ++ [c]}

      result = compute(source, target, base)

      assert kinds(result) == [{:review, "title"}, {:translate, "entry_blocks/c/refs/body/text"}]
      assert Enum.all?(result.work_items, &is_nil(&1.source_previous))
    end

    test "the texts to keep are the source's text rows, beside their digests" do
      {source, target, base} = pair()
      result = compute(%{source | title: "Ny tittel"}, target, base)

      assert result.baseline_texts == %{
               "title" => "Ny tittel",
               "entry_blocks/a/refs/body/text" => "Første",
               "entry_blocks/b/refs/body/text" => "Andre"
             }

      assert result.baseline_texts == Sync.baseline_texts_for(%{source | title: "Ny tittel"}, Article)
      refute Map.has_key?(result.baseline_texts, "year")
      assert Map.has_key?(result.baseline, "year")
    end
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

  test "a language-controlled asset stays the translation's own" do
    {source, target, base} = pair()
    config = Brando.Trait.Translatable.config(mode: :synchronized, language_controlled_fields: [:cover])

    result = compute(%{source | cover_id: 7}, %{target | cover_id: 9}, base, config: config)

    assert result.payload.cover_id == 9
    refute {:shared_update, "cover"} in kinds(result)
  end

  describe "a parent in the same schema" do
    test "follows the source, mapped to its version in the target's language" do
      {source, target, base} = pair()
      result = compute(%{source | parent_id: 10}, target, base, entries: %{{:parent, 10} => 20})

      assert result.payload.parent_id == 20
      assert {:shared_update, "parent"} in kinds(result)
    end

    test "waits, keeping the target's own, while there is no version yet" do
      {source, target, base} = pair()
      result = compute(%{source | parent_id: 10}, %{target | parent_id: 5}, base, entries: %{{:parent, 10} => nil})

      assert result.payload.parent_id == 5
      assert {:awaiting_translation, "parent/10"} in kinds(result)
    end

    test "has nothing to do when the target is already under the mapped parent" do
      {source, target, base} = pair()
      result = compute(%{source | parent_id: 10}, %{target | parent_id: 20}, base, entries: %{{:parent, 10} => 20})

      assert result.payload.parent_id == 20
      refute Enum.any?(kinds(result), &match?({_, "parent"}, &1))
    end

    test "stays the translation's own when language-controlled" do
      {source, target, base} = pair()
      config = Brando.Trait.Translatable.config(mode: :synchronized, language_controlled_fields: [:parent])

      result =
        compute(%{source | parent_id: 10}, %{target | parent_id: 5}, base,
          config: config,
          entries: %{{:parent, 10} => 20}
        )

      assert result.payload.parent_id == 5
      assert result.work_items == []
    end
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

  describe "source-controlled subform fields and module variables" do
    @uids %{{:local, 1} => "hero-banner", {:local, 2} => "quote"}

    defp controlled_config(overrides) do
      Map.merge(Article.__translatable_config__(), overrides)
    end

    # The module selector as a Blueprint declares it through the DSL:
    # `{:module, "hero-banner", [:layout]}` in `source_controlled_fields`
    defp module_selector_config do
      %{source_controlled_module_vars: vars} = Brando.SyncSelectorTest.Article.__translatable_config__()
      controlled_config(%{source_controlled_module_vars: vars})
    end

    test "a controlled subform field follows the source; the row's text stays translated" do
      config = controlled_config(%{source_controlled_subform_fields: %{items: [:link]}})
      item = fn uid, label, link -> %ArticleItem{uid: uid, label: label, link: link} end
      source = article(:no, items: [item.("i1", "En", "/en")])
      target = article(:en, id: 2, items: [item.("i1", "One", "/one")])
      base = Sync.baseline_for(source, Article, config)

      source = %{source | items: [item.("i1", "En", "/ny")]}
      result = compute(source, target, base, config: config)

      assert [%{label: "One", link: "/ny"}] = result.payload.items
      assert kinds(result) == [{:shared_update, "items/i1/link"}]

      # Without the selector the link is the translation's own.
      plain = compute(source, target, baseline(source))
      assert [%{link: "/one"}] = plain.payload.items
    end

    test "a controlled variable follows the source only on the named module" do
      config = module_selector_config()
      var = fn key, value -> %Var{key: key, type: :string, value: value, label: key} end

      source =
        article(:no,
          blocks: [
            block("h", module_id: 1, vars: [var.("layout", "wide"), var.("heading", "Overskrift")]),
            block("q", module_id: 2, vars: [var.("layout", "left")])
          ]
        )

      target =
        article(:en,
          id: 2,
          blocks: [
            block("h", id: 10, module_id: 1, vars: [var.("layout", "narrow"), var.("heading", "Heading")]),
            block("q", id: 11, module_id: 2, vars: [var.("layout", "right")])
          ]
        )

      base = Sync.baseline_for(source, Article, config, @uids)
      result = compute(source, target, base, config: config, module_uids: @uids)
      [hero, quote] = Enum.map(result.payload.entry_blocks, & &1.block)

      assert Enum.map(hero.vars, &{&1.key, &1.value}) == [{"layout", "wide"}, {"heading", "Heading"}]
      # Same key on another module: the translation's own value.
      assert Enum.map(quote.vars, &{&1.key, &1.value}) == [{"layout", "right"}]
      assert kinds(result) == [{:shared_update, "entry_blocks/h/vars/layout/value"}]

      # A block whose module is unknown controls nothing.
      unknown = compute(source, target, base, config: config, module_uids: %{})
      assert Enum.map(hd(unknown.payload.entry_blocks).block.vars, & &1.value) == ["narrow", "Heading"]
    end

    test "repeated source saves keep controlled values in step without new work" do
      config = module_selector_config()
      var = fn value -> %Var{key: "layout", type: :string, value: value, label: "Layout"} end
      source = article(:no, blocks: [block("h", module_id: 1, vars: [var.("wide")])])
      target = article(:en, id: 2, blocks: [block("h", id: 10, module_id: 1, vars: [var.("wide")])])
      base = Sync.baseline_for(source, Article, config, @uids)

      assert compute(source, target, base, config: config, module_uids: @uids).work_items == []
    end
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

    # 2 has no English version yet: it stays linked, to the Norwegian one
    assert Enum.map(join.block.block_identifiers, & &1.identifier_id) == [11, 2]
    assert hd(join.block.vars).identifier_id == 33

    assert {:awaiting_translation, "entry_blocks/a/identifiers/2"} in kinds(result)
    # The source is as last synchronized: only the mapping moved the link
    assert {:relinked, "entry_blocks/a/identifiers"} in kinds(result)
    refute Enum.any?(result.work_items, &(&1.kind == :shared_update))
    refute Enum.any?(result.work_items, &(&1.path == "entry_blocks/a/vars/cta/media"))
  end

  test "a link the source changed is a shared update, though it is mapped as well" do
    link = fn id -> %Brando.Content.BlockIdentifier{identifier_id: id, sequence: 0} end

    with_links = fn entry, ids ->
      [join] = entry.entry_blocks
      %{entry | entry_blocks: [%{join | block: %{join.block | block_identifiers: Enum.map(ids, link)}}]}
    end

    before = with_links.(article(:no, blocks: [block("a")]), [1])
    source = with_links.(before, [1, 2])
    target = with_links.(article(:en, id: 2, blocks: [block("a", id: 10)]), [11])

    result = compute(source, target, baseline(before), identifiers: %{1 => 11, 2 => 22})

    assert {:shared_update, "entry_blocks/a/identifiers"} in kinds(result)
    refute Enum.any?(result.work_items, &(&1.kind == :relinked))
  end

  test "a link without a version in the target's language keeps the source's, and is not emptied" do
    var = %Var{key: "project", type: :link, link_type: :identifier, identifier_id: 3, label: "project"}
    source = article(:no, blocks: [block("a", vars: [var])])
    target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [var])])

    result = compute(source, target, baseline(source), identifiers: %{3 => nil})
    [join] = result.payload.entry_blocks

    assert hd(join.block.vars).identifier_id == 3
    assert {:awaiting_translation, "entry_blocks/a/vars/project/identifier/3"} in kinds(result)
    refute Enum.any?(result.work_items, &(&1.kind == :shared_update))
  end

  describe "URL links" do
    defp url_link(url), do: %Var{key: "cta", type: :link, link_type: :url, value: url, label: "cta"}

    test "a changed URL is reviewed; the translation keeps its own" do
      source = article(:no, blocks: [block("a", vars: [url_link("/no/om-oss")])])
      target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [url_link("/en/about")])])
      base = baseline(source)

      result =
        compute(
          put_in(source.entry_blocks, [
            %{hd(source.entry_blocks) | block: %{hd(source.entry_blocks).block | vars: [url_link("/no/kontakt")]}}
          ]),
          target,
          base
        )

      [join] = result.payload.entry_blocks

      assert hd(join.block.vars).value == "/en/about"
      assert {:review, "entry_blocks/a/vars/cta/url"} in kinds(result)
    end

    test "a new URL link starts from the source's URL, to translate" do
      source = article(:no, blocks: [block("a", vars: [url_link("/no/om-oss")])])
      target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [])])

      result = compute(source, target, baseline(source))
      [join] = result.payload.entry_blocks

      assert hd(join.block.vars).value == "/no/om-oss"
      assert {:translate, "entry_blocks/a/vars/cta/url"} in kinds(result)
    end

    test "a link that changes kind in the source follows it, from the source's value" do
      source = article(:no, blocks: [block("a", vars: [url_link("/no/om-oss")])])

      entry = %Var{key: "cta", type: :link, link_type: :identifier, identifier_id: 3, label: "cta"}
      target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [entry])])

      result = compute(source, target, baseline(source))
      [var] = hd(result.payload.entry_blocks).block.vars

      assert var.link_type == :url
      assert var.value == "/no/om-oss"
      assert var.identifier_id == nil
      assert {:shared_update, "entry_blocks/a/vars/cta/media"} in kinds(result)
    end

    # A module save moves an empty link onto its default tab (`FollowLinkDefault`):
    # that is where its dialog opens, not a link the translation should follow.
    test "an empty source link opening on another tab leaves the translation's link alone" do
      empty = %Var{key: "cta", type: :link, link_type: :url, label: "cta"}
      source = article(:no, blocks: [block("a", vars: [empty])])
      target = article(:en, id: 2, blocks: [block("a", id: 10, vars: [url_link("/en/about")])])
      base = baseline(source)

      moved =
        put_in(source.entry_blocks, [
          %{hd(source.entry_blocks) | block: %{hd(source.entry_blocks).block | vars: [%{empty | link_type: :identifier}]}}
        ])

      result = compute(moved, target, base)
      [var] = hd(result.payload.entry_blocks).block.vars

      assert var.link_type == :url
      assert var.value == "/en/about"
      assert result.work_items == []
    end
  end

  describe "gallery refs" do
    defp gallery_ref(name, gallery) do
      %Ref{
        name: name,
        uid: uid(),
        gallery_id: gallery && gallery.id,
        gallery: gallery,
        data: %GalleryBlock{type: "gallery", data: %GalleryBlock.Data{}}
      }
    end

    defp gallery(id, image_ids) do
      %Gallery{
        id: id,
        config_target: "default",
        gallery_objects:
          for {image_id, index} <- Enum.with_index(image_ids) do
            %GalleryObject{
              id: id * 100 + index,
              gallery_id: id,
              image_id: image_id,
              sequence: index,
              config: %{"a" => index}
            }
          end
      }
    end

    defp payload_ref(result, name) do
      result.payload.entry_blocks |> Enum.flat_map(& &1.block.refs) |> Enum.find(&(&1.name == name))
    end

    # Unsaved: the translation's save inserts it as the ref's own
    defp assert_unsaved_copy(ref, of) do
      assert ref.gallery_id == nil
      assert ref.gallery.id == nil
      assert ref.gallery.config_target == of.config_target

      assert Enum.map(ref.gallery.gallery_objects, &{&1.id, &1.gallery_id, &1.image_id, &1.sequence, &1.config}) ==
               Enum.map(of.gallery_objects, &{nil, nil, &1.image_id, &1.sequence, &1.config})
    end

    test "a ref the source adds to a block the translation has comes with a copy of its gallery" do
      slides = gallery(1, [10, 11])
      source = article(:no, blocks: [block("b1", id: 1, refs: [text_ref("text", "Hei"), gallery_ref("slides", slides)])])
      target = article(:en, id: 2, blocks: [block("b1", id: 2, refs: [text_ref("text", "Hi")])])

      result = compute(source, target, baseline(source))
      assert_unsaved_copy(payload_ref(result, "slides"), slides)
    end

    test "a ref of a block the source adds comes with a copy of its gallery" do
      slides = gallery(1, [10])
      source = article(:no, blocks: [block("b1", id: 1, refs: [gallery_ref("slides", slides)])])
      target = article(:en, id: 2)

      result = compute(source, target, baseline(source))
      assert_unsaved_copy(payload_ref(result, "slides"), slides)
    end

    test "a ref with a gallery of its own keeps it, with the source's media" do
      slides = gallery(1, [10, 11])
      own = gallery(2, [10])
      source = article(:no, blocks: [block("b1", id: 1, refs: [gallery_ref("slides", slides)])])
      target = article(:en, id: 2, blocks: [block("b1", id: 2, refs: [gallery_ref("slides", own)])])

      ref = payload_ref(compute(source, target, baseline(source)), "slides")
      assert ref.gallery_id == own.id
      assert ref.gallery.id == own.id
      assert Enum.map(ref.gallery.gallery_objects, &{&1.gallery_id, &1.image_id}) == [{2, 10}, {2, 11}]
    end

    test "a stored payload's new ref with the source's gallery takes a copy" do
      slides = gallery(1, [10, 11])
      payload = article(:en, id: 2, blocks: [block("b1", refs: [gallery_ref("slides", slides)])])

      [%{block: %{refs: [ref]}}] = Sync.own_new_ref_galleries(payload).entry_blocks
      assert_unsaved_copy(ref, slides)

      # A saved ref is the translation's own already
      saved = article(:en, id: 2, blocks: [block("b1", refs: [%{gallery_ref("slides", slides) | id: 5}])])
      assert Sync.own_new_ref_galleries(saved) == saved
    end
  end

  describe "a new translation" do
    # The copy `create_target/4` makes: the source's text, the source's ids
    # in its blocks' sync identities.
    defp copy(source), do: %{source | id: 2, language: :en}

    # Every kind of text; `t` rewrites the texts that are not empty.
    defp new_translation(t \\ & &1) do
      t = fn text -> if String.trim(text || "") == "", do: text, else: t.(text) end

      override = %GalleryObjectOverride{
        object_id: "10",
        object_type: :image,
        title: t.("Bildetittel"),
        credits: "",
        alt: t.("Bilde")
      }

      # The image's second placement in the gallery has a caption of its own
      second = %GalleryObjectOverride{object_id: "10", object_type: :image, placement: 1, title: t.("Andre")}

      slides = %{
        gallery_ref("slides", gallery(1, [10, 10]))
        | data: %GalleryBlock{type: "gallery", data: %GalleryBlock.Data{gallery_object_overrides: [override, second]}}
      }

      clip = %Ref{
        name: "clip",
        uid: uid(),
        video_id: 3,
        data: %VideoBlock{type: "video", data: %VideoBlock.Data{title: t.("Film")}}
      }

      # Only the template's `text` parameters are text
      embed = %Ref{
        name: "embed",
        uid: uid(),
        data: %HtmlBlock{
          type: "html",
          data: %HtmlBlock.Data{
            text: "<p>{{ lead }}</p>",
            params: [%HtmlBlock.Param{key: "lead", type: :text}, %HtmlBlock.Param{key: "id", type: :id}],
            values: %{"lead" => t.("Ingress i mal"), "id" => "x1"}
          }
        }
      }

      photo = %Ref{
        name: "photo",
        uid: uid(),
        image_id: 5,
        data: %PictureBlock{
          type: "picture",
          data: %PictureBlock.Data{title: t.("Tittel"), credits: "  ", alt: t.("Alt-tekst")}
        }
      }

      vars = [
        %Var{key: "heading", type: :string, value: t.("Overskrift"), label: "heading"},
        %Var{key: "intro", type: :text, value: t.("Ingress"), label: "intro"},
        %Var{key: "body", type: :rich_text, value: t.("<p>Brødtekst</p>"), label: "body"},
        %Var{key: "empty", type: :string, value: "", label: "empty"},
        %Var{key: "cta", type: :link, link_type: :url, value: t.("/no/om-oss"), link_text: t.("Les mer"), label: "cta"},
        %Var{key: "flag", type: :boolean, value_boolean: true, label: "flag"}
      ]

      cell = %TableRow{sync_uid: "r1", vars: [%Var{key: "cell", type: :string, value: t.("Celle"), label: "cell"}]}

      article(:no,
        title: t.("Tittel"),
        subtitle: nil,
        items: [
          %ArticleItem{uid: "i1", label: t.("Punkt"), link: t.("/a")},
          %ArticleItem{uid: "i2", label: "", link: nil}
        ],
        blocks: [
          %{
            block("a",
              refs: [text_ref("body", t.("Avsnitt")), text_ref("blank", " "), photo, slides, clip, embed],
              vars: vars,
              table_rows: [cell],
              children: [block("child", refs: [text_ref("body", t.("Barn"))])]
            )
            | identifier_metas: %{"5" => %{"title" => t.("Lenketittel")}}
          }
        ]
      )
    end

    defp texts_by_path(entry) do
      for {path, :text, value} <- Sync.flatten_entry(entry, Article), into: %{}, do: {path, value}
    end

    test "text still to translate takes the source's new text, of every kind" do
      source = new_translation()
      copy = copy(source)
      edited = new_translation(&(&1 <> " (endret)"))

      untranslated =
        for {path, value} <- texts_by_path(source), String.trim(value || "") != "", into: MapSet.new(), do: path

      result = compute(edited, copy, baseline(source), untranslated: untranslated)
      payload = texts_by_path(result.payload)
      edited_texts = texts_by_path(edited)

      assert MapSet.size(untranslated) == 19
      for path <- untranslated, do: assert({path, payload[path]} == {path, edited_texts[path]})
      # Still to translate, not to review
      assert Enum.all?(result.work_items, &(&1.kind == :translate))
      assert length(result.work_items) == MapSet.size(untranslated)

      # Text not to translate keeps the translation's own
      result = compute(edited, copy, baseline(source), untranslated: MapSet.delete(untranslated, "title"))
      assert result.payload.title == "Tittel"
      assert texts_by_path(result.payload)["items/i1/label"] == "Punkt (endret)"

      assert texts_by_path(compute(edited, copy, baseline(source)).payload) == texts_by_path(copy)
    end

    test "every copied text that is not empty is to translate, of every kind" do
      source = new_translation()
      result = compute(source, copy(source), baseline(source), translate_all: true)

      assert kinds(result) ==
               Enum.sort([
                 {:translate, "title"},
                 {:translate, "entry_blocks/a/refs/body/text"},
                 {:translate, "entry_blocks/a/refs/photo/title"},
                 {:translate, "entry_blocks/a/refs/photo/alt"},
                 {:translate, "entry_blocks/a/refs/slides/gallery/image:10/title"},
                 {:translate, "entry_blocks/a/refs/slides/gallery/image:10/alt"},
                 {:translate, "entry_blocks/a/refs/slides/gallery/image:10@1/title"},
                 {:translate, "entry_blocks/a/refs/clip/title"},
                 {:translate, "entry_blocks/a/refs/embed/values/lead"},
                 {:translate, "entry_blocks/a/identifier_metas/5/title"},
                 {:translate, "entry_blocks/child/refs/body/text"},
                 {:translate, "entry_blocks/a/vars/heading/value"},
                 {:translate, "entry_blocks/a/vars/intro/value"},
                 {:translate, "entry_blocks/a/vars/body/value"},
                 {:translate, "entry_blocks/a/vars/cta/link_text"},
                 {:translate, "entry_blocks/a/vars/cta/url"},
                 {:translate, "entry_blocks/a/rows/r1/vars/cell/value"},
                 {:translate, "items/i1/label"},
                 {:translate, "items/i1/link"}
               ])

      # Each item is raised against the source's text
      assert Enum.find(result.work_items, &(&1.path == "title")).source_digest == Sync.digest("Tittel")
      # Exactly the text the sync keeps per language
      text_paths =
        for {path, :text, value} <- Sync.flatten_entry(source, Article), String.trim(value || "") != "", do: path

      assert Enum.sort(text_paths) == Enum.sort(Enum.map(result.work_items, & &1.path))
    end

    test "without the option, the copy has nothing to translate" do
      source = new_translation()
      assert compute(source, copy(source), baseline(source)).work_items == []
    end
  end
end
