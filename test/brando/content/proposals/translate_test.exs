defmodule Brando.Content.Proposals.TranslateTest do
  # The translate operation: a batch of a synchronized translation's work,
  # answered as a reviewed proposal and saved as the translation form saves
  # it. Grouped: the authorization tests take the authorization lock
  # (Brando.Authorization.Groups.lock!/0) until they end.
  use Brando.ConnCase, async: true, group: :shared_locks

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.CreateTranslation
  alias Brando.Content.Proposals.Proposal
  alias Brando.Content.Proposals.Review
  alias Brando.Content.Proposals.SetFields
  alias Brando.Content.Proposals.Translate
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Work

  @body ~s(<p>Første <a href="https://example.com/">avsnitt</a> om {{ entry.title }}</p>)

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [
            %{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}},
            %{name: "heading", uid: Brando.Utils.generate_uid(), data: %{type: "header", data: %{text: ""}}},
            %{name: "notes", uid: Brando.Utils.generate_uid(), data: %{type: "markdown", data: %{text: ""}}},
            %{name: "photo", uid: Brando.Utils.generate_uid(), data: %{type: "picture", data: %{}}}
          ],
          vars: [
            %{key: "kicker", type: "string", label: "Kicker"},
            %{key: "intro", type: "rich_text", label: "Intro"}
          ]
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    block = add_block(source, module, user)
    %{user: user, module: module, source: source, block: block, prefix: "entry_blocks/#{block.uid}"}
  end

  # A rich text with a link and a placeholder, a header, Markdown, a
  # picture's title and alt text, and a string and a rich text variable
  defp add_block(article, module, user, sequence \\ 0) do
    ref = fn name, type, data ->
      %{"uid" => Brando.Utils.generate_uid(), "name" => name, "data" => %{"type" => type, "data" => data}}
    end

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        ref.("body", "text", %{"text" => @body}),
        ref.("heading", "header", %{"text" => "Overskrift"}),
        ref.("notes", "markdown", %{"text" => "**Merk** dette"}),
        ref.("photo", "picture", %{"title" => "Bildetittel", "alt" => "Bilde", "credits" => ""})
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()

    for {var, index} <-
          Enum.with_index([
            %Var{key: "kicker", type: :string, value: "Stikktittel"},
            %Var{key: "intro", type: :rich_text, value: "<p>Innledning</p>"}
          ]),
        do: Repo.insert!(%{var | label: %{"en" => var.key}, block_id: block.id, sequence: index})

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  # The English translations of every text
  defp english(c), do: Map.put(english_block(c.prefix), "title", "Title")

  defp english_block(prefix) do
    c = %{prefix: prefix}

    %{
      "#{c.prefix}/refs/body/text" => ~s(<p>First <a href="https://example.com/">paragraph</a> on {{ entry.title }}</p>),
      "#{c.prefix}/refs/heading/text" => "Heading",
      "#{c.prefix}/refs/notes/text" => "**Note** this",
      "#{c.prefix}/refs/photo/title" => "Picture title",
      "#{c.prefix}/refs/photo/alt" => "Picture",
      "#{c.prefix}/vars/kicker/value" => "Kicker",
      "#{c.prefix}/vars/intro/value" => "<p>Introduction</p>"
    }
  end

  defp create_translation(c) do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    target
  end

  defp units(target) do
    {:ok, %{units: units}} = Work.translation_units(Article, target.id)
    Enum.filter(units, & &1.answerable)
  end

  # The token for the units with `keys` (all of them by default), as
  # translation_work gives it for a batch
  defp digest(target, keys \\ nil) do
    units = units(target)
    units = if keys, do: Enum.filter(units, &(&1.key in keys)), else: units
    Work.token(%{type: to_string(Article), id: target.id, language: "en"}, units)
  end

  defp translate(target, texts, opts \\ []) do
    %Translate{
      target: {Article, target.id},
      source_digest: Keyword.get_lazy(opts, :digest, fn -> digest(target, Keyword.get(opts, :keys)) end),
      texts: texts,
      reviewed: Keyword.get(opts, :reviewed, [])
    }
  end

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  defp problems(ops, user) do
    {:ok, proposal} = Proposals.prepare(ops, user)
    Enum.map(proposal.problems, &{Map.get(&1, :operation), &1.code, Map.get(&1, :key)})
  end

  defp open_items(id) do
    case Translations.get_pending_version(Article, id) do
      nil -> []
      version -> for(%{resolved_at: nil} = item <- version.work_items, do: {item.kind, item.path}) |> Enum.sort()
    end
  end

  defp load(id) do
    {:ok, entry} = Translations.load_entry(Article, id)
    entry
  end

  defp saved_texts(id) do
    entry = load(id)
    [join] = entry.entry_blocks
    refs = Map.new(join.block.refs, &{&1.name, &1.data.data})
    vars = Map.new(join.block.vars, &{&1.key, &1.value})

    %{
      title: entry.title,
      body: refs["body"].text,
      heading: refs["heading"].text,
      notes: refs["notes"].text,
      photo: {refs["photo"].title, refs["photo"].alt},
      kicker: vars["kicker"],
      intro: vars["intro"]
    }
  end

  describe "an existing translation" do
    test "is saved with every text, its answered items resolved and its structure untouched", c do
      target = create_translation(c)
      block_uid = hd(load(target.id).entry_blocks).block.uid

      assert {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      assert proposal.problems == []
      assert {:ok, receipt} = approve_and_apply(proposal, c.user)

      assert saved_texts(target.id) == %{
               title: "Title",
               body: ~s(<p>First <a href="https://example.com/">paragraph</a> on {{ entry.title }}</p>),
               heading: "Heading",
               notes: "**Note** this",
               photo: {"Picture title", "Picture"},
               kicker: "Kicker",
               intro: "<p>Introduction</p>"
             }

      assert open_items(target.id) == []
      # The translation's own block, still in its group, still a draft
      assert [%{block: %{uid: ^block_uid}}] = load(target.id).entry_blocks
      assert Repo.get!(Article, target.id).status == :draft
      assert %{role: :target, synchronized: true} = Translations.get_member(Article, target.id)
      assert length(receipt.mappings["translated"][Proposal.key({Article, target.id})]) == 8
    end

    test "a batch resolves its own units and leaves the rest open", c do
      target = create_translation(c)
      keys = ["title", "#{c.prefix}/refs/heading/text"]
      texts = Map.take(english(c), keys)

      {:ok, proposal} = Proposals.propose([translate(target, texts, keys: keys)], c.user)
      assert proposal.problems == []
      {:ok, _} = approve_and_apply(proposal, c.user)

      assert %{title: "Title", heading: "Heading", kicker: "Stikktittel"} = saved_texts(target.id)
      open = Enum.map(open_items(target.id), &elem(&1, 1))
      assert length(open) == 6
      refute Enum.any?(keys, &(&1 in open))
    end

    test "a unit marked reviewed is resolved without a change, as is a text the translation already has", c do
      target = create_translation(c)
      keys = ["title", "#{c.prefix}/refs/heading/text"]

      op = translate(target, %{"title" => "Tittel"}, keys: keys, reviewed: ["#{c.prefix}/refs/heading/text"])
      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []
      {:ok, _} = approve_and_apply(proposal, c.user)

      assert %{title: "Tittel", heading: "Overskrift"} = saved_texts(target.id)
      refute Enum.any?(open_items(target.id), &(elem(&1, 1) in keys))
    end

    test "a published translation is updated, and stays published", c do
      target = create_translation(c)
      {:ok, _} = SyncTest.update_article(target.id, %{status: "published"}, c.user)

      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      assert proposal.effects.live == [{Article, target.id}]
      {:ok, _} = approve_and_apply(proposal, c.user)

      assert %{status: :published, title: "Title"} = Repo.get!(Article, target.id)
    end

    test "the translation's blocks are rendered in its language", c do
      target = create_translation(c)
      {:ok, _} = SyncTest.update_article(target.id, %{status: "published"}, c.user)

      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      {:ok, _} = approve_and_apply(proposal, c.user)

      rendered = Repo.get!(Article, target.id).rendered_blocks
      assert rendered =~ "First"
      refute rendered =~ "Første"
    end

    test "it cannot be published at apply", c do
      target = create_translation(c)
      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      assert {:error, _} =
               Proposals.apply(proposal.id, proposal.version, c.user, publish: [Proposal.key({Article, target.id})])
    end

    test "two batches in one proposal are saved together, and a key is answered once", c do
      target = create_translation(c)
      first = ["title", "#{c.prefix}/refs/heading/text"]
      second = Map.keys(english(c)) -- first

      ops = [
        translate(target, Map.take(english(c), first), keys: first),
        translate(target, Map.take(english(c), second), keys: second)
      ]

      {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      {:ok, _} = approve_and_apply(proposal, c.user)
      assert %{title: "Title", kicker: "Kicker"} = saved_texts(target.id)
      assert open_items(target.id) == []

      again = translate(target, %{"title" => "Title"}, keys: ["title"])
      assert {2, :duplicate_key, "title"} in problems(ops ++ [again], c.user)
    end

    test "undo puts the texts back and opens the items again", c do
      target = create_translation(c)
      before = open_items(target.id)

      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      {:ok, _} = approve_and_apply(proposal, c.user)
      assert open_items(target.id) == []

      assert {:ok, _} = Proposals.undo(proposal.id, c.user)
      assert %{title: "Tittel", heading: "Overskrift"} = saved_texts(target.id)
      assert open_items(target.id) == before
    end

    test "undo opens a review again with the source's text before the change, from the receipt", c do
      target = create_translation(c)
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: english(c)}, c.user)
      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)

      {:ok, proposal} = Proposals.propose([translate(target, %{"title" => "New title"}, keys: ["title"])], c.user)
      {:ok, _} = approve_and_apply(proposal, c.user)
      assert open_items(target.id) == []

      assert {:ok, _} = Proposals.undo(proposal.id, c.user)

      assert [%{source_previous: "Tittel"}] =
               for(
                 %{resolved_at: nil, kind: :review, path: "title"} = item <-
                   Translations.get_pending_version(Article, target.id).work_items,
                 do: item
               )
    end

    test "a source changed between prepare and apply makes the proposal stale, naming the units", c do
      target = create_translation(c)
      heading = "#{c.prefix}/refs/heading/text"

      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      [join] = load(c.source.id).entry_blocks
      ref = Enum.find(join.block.refs, &(&1.name == "heading"))
      ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: "Ny overskrift"}}) |> Repo.update!()
      Translations.source_saved(load(c.source.id))

      assert {:error, message} = Proposals.apply(proposal.id, proposal.version, c.user)
      assert message =~ "Text › Heading"
      refute message =~ heading
      assert {:ok, %{status: "pending", problems: problems}} = Proposals.get(proposal.id, c.user)
      assert [%{code: :source_changed, key: ^heading}] = problems
      assert %{title: "Tittel"} = saved_texts(target.id)
    end
  end

  describe "a translation whose source changed its structure" do
    # A translated translation whose source then gets a new block, loses its
    # second, replaces its first's image and changes a field it controls: the
    # pending version carries that structure, with the new block's texts to
    # translate.
    setup c do
      second = add_block(c.source, c.module, c.user, 1)
      second = "entry_blocks/#{second.uid}"
      target = create_translation(c)
      texts = english(c) |> Map.merge(english_block(second)) |> Map.put("#{second}/refs/heading/text", "Second heading")
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: texts}, c.user)

      added = add_block(c.source, c.module, c.user, 2)

      Repo.delete_all(
        from(j in Article.Blocks,
          where: j.entry_id == ^c.source.id and j.block_id != ^c.block.id and j.block_id != ^added.id
        )
      )

      image = Factory.insert(:image)

      Repo.update_all(from(r in Brando.Content.Ref, where: r.block_id == ^c.block.id and r.name == "photo"),
        set: [image_id: image.id]
      )

      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2001}, c.user)
      Translations.source_saved(load(c.source.id))

      %{target: target, added: "entry_blocks/#{added.uid}", image: image}
    end

    defp blocks(id) do
      for join <- load(id).entry_blocks do
        refs = Map.new(join.block.refs, &{&1.name, &1})
        {refs["heading"].data.data.text, refs["photo"].image_id}
      end
    end

    test "is saved with that structure, and undo puts back the translation and its open work", c do
      before = open_items(c.target.id)
      assert {:shared_update, "year"} in before
      assert {:shared_update, "#{c.prefix}/refs/photo/media"} in before
      assert {:translate, "#{c.added}/refs/heading/text"} in before

      texts = Map.put(english_block(c.added), "#{c.added}/refs/heading/text", "New heading")
      {:ok, proposal} = Proposals.propose([translate(c.target, texts)], c.user)
      assert proposal.problems == []
      {:ok, receipt} = approve_and_apply(proposal, c.user)

      # The source's new block, translated, in place of the one it lost
      assert blocks(c.target.id) == [{"Heading", c.image.id}, {"New heading", nil}]
      assert %{year: 2001} = Repo.get!(Article, c.target.id)
      assert open_items(c.target.id) == []
      assert Repo.get!(Article, c.target.id).rendered_blocks =~ "First"

      resolved = receipt.mappings["translated"][Proposal.key({Article, c.target.id})]
      assert Enum.sort(Enum.map(resolved, &{String.to_existing_atom(&1["kind"]), &1["path"]})) == before

      assert {:ok, _} = Proposals.undo(proposal.id, c.user)
      assert blocks(c.target.id) == [{"Heading", nil}, {"Second heading", nil}]
      assert %{year: nil} = Repo.get!(Article, c.target.id)
      assert open_items(c.target.id) == before
    end
  end

  describe "the source checked again under its lock, in the apply's transaction" do
    # A source saved after the recheck, while the apply waits for the
    # proposal lock: the race cannot be staged, so the step is called as the
    # apply calls it, after the source changed.
    defp check_sources(proposal) do
      Repo.transaction(fn -> Proposals.check_translated_sources!(proposal) end)
    end

    test "the sources are locked with the apply's other rows, in its sorted order", c do
      target = create_translation(c)
      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      assert Proposals.apply_lock_order(proposal) == [{Article, c.source.id}, {Article, target.id}]

      units = Work.new_translation_units(Article, c.source.id) |> elem(1) |> Map.fetch!(:units)
      digest = Work.token(%{type: to_string(Article), id: {:new, c.source.id}, language: "en"}, units)

      ops = [
        %CreateTranslation{source: {Article, c.source.id}, language: "en", ref: "english"},
        %Translate{target: {:new, "english"}, source_digest: digest, texts: english(c)}
      ]

      {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {Article, c.source.id} in Proposals.apply_lock_order(proposal)
    end

    test "refuses a batch whose source text changed, naming the unit", c do
      target = create_translation(c)
      {:ok, proposal} = Proposals.propose([translate(target, english(c))], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:ok, :ok} = check_sources(proposal)

      [join] = load(c.source.id).entry_blocks
      ref = Enum.find(join.block.refs, &(&1.name == "heading"))
      ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: "Ny overskrift"}}) |> Repo.update!()

      error = assert_raise Brando.Content.Transfer.Error, fn -> check_sources(proposal) end
      assert Exception.message(error) =~ "Text › Heading"
      refute Exception.message(error) =~ "#{c.prefix}/refs/heading/text"
    end

    test "refuses a batch for a translation the proposal creates whose source text changed", c do
      units = Work.new_translation_units(Article, c.source.id) |> elem(1) |> Map.fetch!(:units)
      digest = Work.token(%{type: to_string(Article), id: {:new, c.source.id}, language: "en"}, units)

      ops = [
        %CreateTranslation{source: {Article, c.source.id}, language: "en", ref: "english"},
        %Translate{target: {:new, "english"}, source_digest: digest, texts: english(c)}
      ]

      {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, :ok} = check_sources(proposal)

      {1, _} = Repo.update_all(from(a in Article, where: a.id == ^c.source.id), set: [title: "I morgen"])

      assert_raise Brando.Content.Transfer.Error, ~r/Title/, fn -> check_sources(proposal) end
    end
  end

  describe "a tag added around a placeholder" do
    # The source's heading (plain), intro (rich text without a tag) and notes
    # (Markdown) hold a placeholder: a translation may keep it, not put it in
    # a tag of its own.
    setup c do
      [join] = load(c.source.id).entry_blocks
      ref = Enum.find(join.block.refs, &(&1.name == "heading"))

      ref
      |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: "Om {{ entry.title }}"}})
      |> Repo.update!()

      notes = Enum.find(join.block.refs, &(&1.name == "notes"))

      notes
      |> Ecto.Changeset.change(data: %{notes.data | data: %{notes.data.data | text: "**Merk** {{ entry.title }}"}})
      |> Repo.update!()

      var = Enum.find(join.block.vars, &(&1.key == "intro"))
      var |> Ecto.Changeset.change(value: "Innledning om {{ entry.title }}") |> Repo.update!()

      %{target: create_translation(c)}
    end

    test "is refused in a plain unit, a rich text without tags and one with them, and Markdown", c do
      heading = "#{c.prefix}/refs/heading/text"
      intro = "#{c.prefix}/vars/intro/value"
      body = "#{c.prefix}/refs/body/text"
      notes = "#{c.prefix}/refs/notes/text"

      kept = %{
        heading => "About {{ entry.title }}",
        intro => "Introduction to {{ entry.title }}",
        notes => "**Note** {{ entry.title }}"
      }

      texts =
        english(c)
        |> Map.put(heading, ~s(About <a href="{{ entry.title }}">it</a>))
        |> Map.put(intro, ~s(Introduction to <a href="{{ entry.title }}">it</a>))
        |> Map.put(
          body,
          ~s(<p>First <a href="https://example.com/">paragraph</a> on <a href="{{ entry.title }}">it</a></p>)
        )

      found = problems([translate(c.target, texts)], c.user)
      assert Enum.any?(found, &match?({0, _, ^heading}, &1))
      assert Enum.any?(found, &match?({0, _, ^intro}, &1))
      assert Enum.any?(found, &match?({0, _, ^body}, &1))

      # In an attribute after an address, or inside a tag of its own
      for text <- [
            ~s(Introduction to <a href="https://example.com/{{ entry.title }}">it</a>),
            ~s(Introduction to <strong>{{ entry.title }}</strong>),
            ~s(Introduction to <a href="https://example.com/">{{ entry.title }}</a>)
          ] do
        texts = english(c) |> Map.merge(kept) |> Map.put(intro, text)
        assert problems([translate(c.target, texts)], c.user) == [{0, :unsafe_text, intro}]
      end

      texts = english(c) |> Map.merge(kept) |> Map.put(notes, "**Note** **{{ entry.title }}**")
      assert problems([translate(c.target, texts)], c.user) == [{0, :unsafe_text, notes}]

      # Kept as text, the placeholder is right
      assert problems([translate(c.target, Map.merge(english(c), kept))], c.user) == []
    end
  end

  describe "where a placeholder sits, read from the parsed markup" do
    # Sets the source's intro (rich text) and notes (Markdown), then creates
    # the translation
    defp with_source(c, texts) do
      [join] = load(c.source.id).entry_blocks

      if notes = texts[:notes] do
        ref = Enum.find(join.block.refs, &(&1.name == "notes"))

        ref
        |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: notes}})
        |> Repo.update!()
      end

      if intro = texts[:intro] do
        var = Enum.find(join.block.vars, &(&1.key == "intro"))
        var |> Ecto.Changeset.change(value: intro) |> Repo.update!()
      end

      create_translation(c)
    end

    # A placeholder without spaces passes as an address, so only where it
    # sits keeps it out of an href
    test "a placeholder moved into an attribute behind a quoted > is refused", c do
      target = with_source(c, %{intro: "Innledning om {{entry.title}}"})
      intro = "#{c.prefix}/vars/intro/value"

      for text <- [
            ~s(Introduction to <a title="></a>" href="https://example.com/{{entry.title}}">it</a>),
            ~s(Introduction to <a title="></a>" href="{{entry.title}}#">it</a>)
          ] do
        texts = Map.put(english(c), intro, text)
        assert problems([translate(target, texts)], c.user) == [{0, :unsafe_text, intro}], text
      end

      texts = Map.put(english(c), intro, "Introduction to {{entry.title}}")
      assert problems([translate(target, texts)], c.user) == []
    end

    # The marker a placeholder is swapped for is made for one comparison, so
    # no text can carry one to stand in for a placeholder it moved
    test "a placeholder made a tag's name is refused, also with marker-like text beside it", c do
      target = with_source(c, %{intro: "Innledning om {{entry.title}}"})
      intro = "#{c.prefix}/vars/intro/value"

      for text <- [
            ~s|Introduction <{{entry.title}} autofocus tabindex="0" onfocus="alert(1)">|,
            ~s|zqbrandoplaceholder0zq <{{entry.title}} autofocus tabindex="0" onfocus="alert(1)">|
          ] do
        texts = Map.put(english(c), intro, text)
        assert [{0, :unsafe_text, ^intro}] = problems([translate(target, texts)], c.user), text
      end

      # Marker-like text is only text
      texts = Map.put(english(c), intro, "Introduction to {{entry.title}} zqbrandoplaceholder9zq")
      assert problems([translate(target, texts)], c.user) == []
    end

    test "Markdown does not let a placeholder trade places with text in an address", c do
      notes = "#{c.prefix}/refs/notes/text"

      target = with_source(c, %{notes: "{{entry.title}} [x](https://example.com/side)"})
      texts = Map.put(english(c), notes, "Page [x](https://example.com/{{entry.title}})")
      assert [{0, :unsafe_text, ^notes}] = problems([translate(target, texts)], c.user)
    end

    test "Markdown keeps a placeholder in an image's alt text", c do
      notes = "#{c.prefix}/refs/notes/text"

      target = with_source(c, %{notes: "![Bilde av {{ entry.title }}](/x.jpg)"})
      texts = Map.put(english(c), notes, "![Picture of {{ entry.title }}](/x.jpg)")
      assert problems([translate(target, texts)], c.user) == []
    end

    test "Markdown keeps a placeholder as a link's text, with the address localised", c do
      notes = "#{c.prefix}/refs/notes/text"

      target = with_source(c, %{notes: "[{{ entry.title }}](/no/side)"})
      texts = Map.put(english(c), notes, "[{{ entry.title }}](/en/page)")
      assert problems([translate(target, texts)], c.user) == []
    end

    test "a placeholder the source has in an attribute or inside tags is kept there", c do
      intro = "#{c.prefix}/vars/intro/value"

      target =
        with_source(c, %{
          intro: ~s(<p><a href="https://example.com/{{entry.slug}}">Les <strong>{{ entry.title }}</strong></a></p>)
        })

      kept = ~s(<p><a href="https://example.com/{{entry.slug}}">Read <strong>{{ entry.title }}</strong></a></p>)
      assert problems([translate(target, Map.put(english(c), intro, kept))], c.user) == []

      # Swapped, each is somewhere the source does not have it
      swapped = ~s(<p><a href="https://example.com/{{entry.slug}}">Read {{ entry.title }}</a></p>)
      assert {0, :unsafe_text, intro} in problems([translate(target, Map.put(english(c), intro, swapped))], c.user)
    end
  end

  describe "refused, per unit" do
    setup c, do: %{target: create_translation(c)}

    test "an answer with extra, missing or blank units", c do
      texts =
        english(c) |> Map.delete("title") |> Map.put("subtitle", "Sub") |> Map.put("#{c.prefix}/refs/heading/text", " ")

      assert problems([translate(c.target, texts)], c.user) |> Enum.sort() ==
               Enum.sort([
                 {0, :extra_key, "subtitle"},
                 {0, :missing_key, "title"},
                 {0, :blank_text, "#{c.prefix}/refs/heading/text"}
               ])
    end

    test "lost HTML and lost or changed placeholders", c do
      body = "#{c.prefix}/refs/body/text"
      intro = "#{c.prefix}/vars/intro/value"
      texts = english(c) |> Map.put(body, "<p>First paragraph on {{ entry.name }}</p>") |> Map.put(intro, "Introduction")

      assert problems([translate(c.target, texts)], c.user) |> Enum.sort() ==
               Enum.sort([
                 {0, :html_changed, body},
                 {0, :placeholders_changed, body},
                 # A placeholder the source does not have is a { like any other
                 {0, :unsafe_text, body},
                 {0, :html_changed, intro}
               ])
    end

    test "a placeholder the source has is kept, and another { is refused", c do
      # The body keeps {{ entry.title }}: no problem
      assert problems([translate(c.target, english(c))], c.user) == []

      texts = Map.put(english(c), "title", "Title {% raw %}")
      assert {0, :unsafe_text, "title"} in problems([translate(c.target, texts)], c.user)
      assert {0, :placeholders_changed, "title"} in problems([translate(c.target, texts)], c.user)

      texts = Map.put(english(c), "#{c.prefix}/refs/heading/text", "Heading &#123;")
      assert [{0, :unsafe_text, _}] = problems([translate(c.target, texts)], c.user)
    end

    test "markup in plain text, and unsafe rich text and Markdown", c do
      heading = "#{c.prefix}/refs/heading/text"
      intro = "#{c.prefix}/vars/intro/value"
      notes = "#{c.prefix}/refs/notes/text"

      texts =
        english(c)
        |> Map.put(heading, "<b>Heading</b>")
        |> Map.put(intro, ~s{<p onclick="x()">Introduction</p>})
        |> Map.put(notes, "**Note** [this](javascript:alert(1))")

      found = problems([translate(c.target, texts)], c.user)
      assert {0, :unsafe_text, heading} in found
      assert {0, :unsafe_text, intro} in found
      assert {0, :unsafe_text, notes} in found
    end

    test "a text for a unit that is not answered with text", c do
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2001}, c.user)
      assert {:shared_update, "year"} in open_items(c.target.id)

      texts = Map.put(english(c), "year", "2001")
      assert problems([translate(c.target, texts)], c.user) == [{0, :extra_key, "year"}]
    end

    test "each problem names its unit by its label, in the admin's language", c do
      body = "#{c.prefix}/refs/body/text"
      texts = english(c) |> Map.delete(body) |> Map.put("title", " ")

      messages = fn ->
        {:ok, proposal} = Proposals.prepare([translate(c.target, texts)], c.user)
        Map.new(proposal.problems, &{&1.key, &1.message})
      end

      english = messages.()
      assert english[body] =~ "Text › Body"
      refute english[body] =~ body
      assert english["title"] =~ "Title"

      norwegian = Gettext.with_locale(Brando.Gettext, "no", messages)
      assert Map.keys(norwegian) == Map.keys(english)
      refute norwegian[body] == english[body]
      refute norwegian["title"] == english["title"]
    end

    test "the review prepare_proposal returns gives each problem's unit key", c do
      body = "#{c.prefix}/refs/body/text"
      texts = Map.put(english(c), body, "<p>First paragraph on {{ entry.title }}</p>")

      {:ok, proposal} = Proposals.propose([translate(c.target, texts)], c.user)
      review = Brando.Content.Proposals.Tools.review(proposal)

      assert [%{operation: 0, code: :html_changed, key: ^body}] = review.problems
    end

    test "a token for another entry, or a changed one", c do
      assert [{0, :stale, nil}] = problems([translate(c.target, english(c), digest: "nonsense")], c.user)

      other = %{type: to_string(Article), id: c.source.id, language: "en"}
      digest = Work.token(other, units(c.target))
      assert [{0, :stale, nil}] = problems([translate(c.target, english(c), digest: digest)], c.user)
    end

    test "a malformed answer", c do
      assert [{0, :malformed, nil} | _] =
               problems([translate(c.target, ["title"], reviewed: "title")], c.user)
    end

    test "another operation on the same translation; other entries are not affected", c do
      ops = [
        translate(c.target, english(c)),
        %SetFields{target: {Article, c.target.id}, fields: %{"subtitle" => "Sub"}},
        %SetFields{target: {Article, c.source.id}, fields: %{"subtitle" => "Undertittel"}}
      ]

      assert problems(ops, c.user) == [{1, :translate_only, nil}]
    end

    test "a source, or an entry outside a group", c do
      op = %Translate{target: {Article, c.source.id}, source_digest: digest(c.target), texts: %{}}
      assert [{0, :not_translation, nil}] = problems([op], c.user)

      {:ok, lone} =
        SyncTest.create_article(%{title: "Alone", slug: "alone-#{c.source.id}", language: "no", status: "draft"}, c.user)

      op = %Translate{target: {Article, lone.id}, source_digest: digest(c.target), texts: %{}}
      assert [{0, :not_translation, nil}] = problems([op], c.user)
    end

    test "a field the forms lock, for anyone but a superuser", c do
      alias Brando.SyncLockedTest.Article, as: LockedArticle

      {:ok, source} =
        Brando.SyncLockedTest.create_article(
          %{title: "Tittel", slug: "laast-#{c.source.id}", subtitle: "Undertittel", language: "no", status: "draft"},
          c.user
        )

      {:ok, target} = Translations.create_target(LockedArticle, source.id, :en, c.user)
      {:ok, %{units: units}} = Work.translation_units(LockedArticle, target.id)
      digest = Work.token(%{type: to_string(LockedArticle), id: target.id, language: "en"}, units)

      op = %Translate{
        target: {LockedArticle, target.id},
        source_digest: digest,
        texts: %{"title" => "Title", "subtitle" => "Subtitle"}
      }

      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      assert problems([op], editor) == [{0, :protected_field, "subtitle"}]
      assert problems([op], Factory.insert(:random_user, role: :superuser)) == []
    end

    test "a locked field's unit is outside an editor's batch, which the editor can answer", c do
      alias Brando.Content.Proposals.Tools
      alias Brando.SyncLockedTest.Article, as: LockedArticle

      {:ok, source} =
        Brando.SyncLockedTest.create_article(
          %{title: "Tittel", slug: "laast-#{c.source.id}", subtitle: "Undertittel", language: "no", status: "draft"},
          c.user
        )

      {:ok, target} = Translations.create_target(LockedArticle, source.id, :en, c.user)
      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      context = %Tools.Context{actor: editor}
      args = %{"content_type" => "Brando.SyncLockedTest.Article", "id" => target.id}
      assert {:ok, work} = Tools.call("translation_work", args, context)

      assert %{answerable: false, locked: true, reason: _} = Enum.find(work.units, &(&1.key == "subtitle"))
      assert %{answerable: true} = Enum.find(work.units, &(&1.key == "title"))

      op = %Translate{target: {LockedArticle, target.id}, source_digest: work.source_digest, texts: %{"title" => "Title"}}
      assert problems([op], editor) == []

      op = %{op | texts: %{"title" => "Title", "subtitle" => "Subtitle"}}
      assert problems([op], editor) == [{0, :extra_key, "subtitle"}]

      # The units a new translation would have, read on a source without one
      {:ok, other} =
        Brando.SyncLockedTest.create_article(
          %{title: "Annen", slug: "annen-#{c.source.id}", subtitle: "Undertittel", language: "no", status: "draft"},
          c.user
        )

      args = %{"content_type" => "Brando.SyncLockedTest.Article", "id" => other.id, "language" => "en"}
      assert {:ok, work} = Tools.call("translation_work", args, context)
      assert %{answerable: false, locked: true} = Enum.find(work.units, &(&1.key == "subtitle"))
    end

    test "an actor who may not update the translation", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}
      reader = Factory.insert(:random_user, role: :user)

      {:ok, group} =
        Groups.create(Scope.standalone(c.user), %{name: "Article readers"}, [
          Catalog.get(:read, Article).key,
          "brando.admin.access"
        ])

      {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, reader.id)

      assert {:error, _} = Proposals.prepare([translate(c.target, english(c))], reader)
    end
  end

  describe "a translation the proposal creates" do
    test "is created and filled in, in one apply", c do
      units = Work.new_translation_units(Article, c.source.id) |> elem(1) |> Map.fetch!(:units)
      digest = Work.token(%{type: to_string(Article), id: {:new, c.source.id}, language: "en"}, units)

      ops = [
        %CreateTranslation{source: {Article, c.source.id}, language: "en", ref: "english"},
        %Translate{target: {:new, "english"}, source_digest: digest, texts: english(c)}
      ]

      {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      {:ok, receipt} = approve_and_apply(proposal, c.user)
      id = receipt.mappings["created"]["english"]

      assert %{role: :target, synchronized: true} = Translations.get_member(Article, id)
      assert %{title: "Title", body: body, intro: "<p>Introduction</p>"} = saved_texts(id)
      assert body =~ "paragraph"
      assert open_items(id) == []
      assert Repo.get!(Article, id).status == :draft
      # Rendered in its own language, not the source's
      rendered = Repo.get!(Article, id).rendered_blocks
      assert rendered =~ "First"
      refute rendered =~ "Første"

      # Undo removes it
      assert {:ok, _} = Proposals.undo(proposal.id, c.user)
      assert Repo.get(Article, id) == nil
    end

    test "is refused without the create_translation it names", c do
      op = %Translate{target: {:new, "english"}, source_digest: "x", texts: %{}}
      assert [{0, :unknown_target, nil}] = problems([op], c.user)
    end

    test "is checked against the units it will have", c do
      units = Work.new_translation_units(Article, c.source.id) |> elem(1) |> Map.fetch!(:units)
      digest = Work.token(%{type: to_string(Article), id: {:new, c.source.id}, language: "en"}, units)

      ops = [
        %CreateTranslation{source: {Article, c.source.id}, language: "en", ref: "english"},
        %Translate{target: {:new, "english"}, source_digest: digest, texts: Map.delete(english(c), "title")}
      ]

      assert problems(ops, c.user) == [{1, :missing_key, "title"}]
    end
  end

  test "the review shows each unit with its source text and translation, and the reviewed ones", c do
    target = create_translation(c)
    keys = ["title", "#{c.prefix}/refs/heading/text"]
    op = translate(target, %{"title" => "Title"}, keys: keys, reviewed: ["#{c.prefix}/refs/heading/text"])
    {:ok, proposal} = Proposals.propose([op], c.user)

    assert [%{action: :update, changes: [change]}] = Review.entries(proposal)
    assert %{type: :translate, language: "en", operations: [0], units: units} = change

    assert [
             %{key: "title", label: "Title", source: "Tittel", text: "Title", reviewed?: false},
             %{key: heading, label: "Text › Heading", source: "Overskrift", text: "Overskrift", reviewed?: true}
           ] = units

    assert heading == "#{c.prefix}/refs/heading/text"
  end

  describe "the review" do
    test "shows the translation's text for a unit marked reviewed", c do
      target = create_translation(c)
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: english(c)}, c.user)
      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)
      assert {:review, "title"} in open_items(target.id)

      op = translate(target, %{}, keys: ["title"], reviewed: ["title"])
      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []

      assert [%{changes: [%{units: [unit]}]}] = Review.entries(proposal)
      assert %{key: "title", source: "Ny tittel", text: "Title", reviewed?: true} = unit
    end

    test "shows a review unit's source before and now, and its translation before and now", c do
      target = create_translation(c)
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: english(c)}, c.user)
      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)

      op = translate(target, %{"title" => "New title"}, keys: ["title"])
      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []

      assert [%{changes: [%{units: [unit]}]}] = Review.entries(proposal)

      assert %{
               key: "title",
               source_previous: "Tittel",
               source: "Ny tittel",
               before: "Title",
               text: "New title",
               reviewed?: false
             } = unit
    end

    test "an applied proposal's review unit shows no before from a later review", c do
      target = create_translation(c)
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: english(c)}, c.user)
      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)

      op = translate(target, %{"title" => "New title"}, keys: ["title"])
      {:ok, proposal} = Proposals.propose([op], c.user)
      {:ok, _} = approve_and_apply(proposal, c.user)

      # A later change raises another review on the same path
      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Nyere tittel"}, c.user)
      assert {:review, "title"} in open_items(target.id)

      {:ok, applied} = Proposals.get(proposal.id, c.user)
      assert applied.status == "applied"
      assert [%{changes: [%{units: [unit]}]}] = Review.entries(applied)
      assert %{key: "title", source_previous: nil, before: nil, text: "New title"} = unit
    end

    test "a translate unit, and a review raised without the previous text, show no before", c do
      target = create_translation(c)
      heading = "#{c.prefix}/refs/heading/text"
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: Map.delete(english(c), heading)}, c.user)

      # Synced before the texts were kept
      from(m in Brando.Translations.Member, where: m.entry_id == ^target.id and m.role == :target)
      |> Repo.update_all(set: [baseline_texts: %{}])

      {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)
      assert {:review, "title"} in open_items(target.id)
      assert {:translate, heading} in open_items(target.id)

      op = translate(target, %{"title" => "New title", heading => "Heading"}, keys: ["title", heading])
      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []

      assert [%{changes: [%{units: [title, heading_unit]}]}] = Review.entries(proposal)
      assert %{key: "title", source_previous: nil, before: nil} = title
      assert %{key: ^heading, source_previous: nil, before: nil} = heading_unit
    end

    test "labels a unit in a block the source added from the pending version", c do
      target = create_translation(c)
      added = add_block(c.source, c.module, c.user, 1)
      Translations.source_saved(load(c.source.id))
      heading = "entry_blocks/#{added.uid}/refs/heading/text"

      op = translate(target, %{heading => "Heading"}, keys: [heading])
      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []

      assert [%{changes: [%{units: [unit]}]}] = Review.entries(proposal)
      assert %{key: ^heading, label: "Text › Heading"} = unit
    end

    test "says what else the apply saves only while the proposal can be applied", c do
      target = create_translation(c)
      {:ok, proposal} = Proposals.propose([translate(target, %{"title" => "Title"}, keys: ["title"])], c.user)
      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert open_items(target.id) != []

      {:ok, applied} = Proposals.get(proposal.id, c.user)
      assert applied.status == "applied"
      assert [%{changes: [%{type: :translate, pending: nil}]}] = Review.entries(applied)
    end

    test "says what else the apply saves: the source's structure changes and the texts left", c do
      target = create_translation(c)
      keys = ["title"]
      {:ok, proposal} = Proposals.propose([translate(target, %{"title" => "Title"}, keys: keys)], c.user)
      assert [%{changes: [%{pending: %{open: 7, structure?: false}}]}] = Review.entries(proposal)

      add_block(c.source, c.module, c.user, 1)
      Translations.source_saved(load(c.source.id))
      {:ok, proposal} = Proposals.propose([translate(target, %{"title" => "Title"}, keys: keys)], c.user)
      assert [%{changes: [%{pending: %{open: 14, structure?: true}}]}] = Review.entries(proposal)
    end
  end

  test "the codec decodes and encodes it" do
    map = %{
      "op" => "translate",
      "target" => %{"content_type" => "Brando.SyncTest.Article", "id" => 5},
      "source_digest" => "abc",
      "texts" => %{"title" => "Title"},
      "reviewed" => ["subtitle"]
    }

    assert {:ok, %Translate{target: {Article, 5}, source_digest: "abc"} = op} = Codec.decode(map)
    assert Codec.encode(op) == map

    new = %{map | "target" => %{"new" => "english"}}
    assert {:ok, %Translate{target: {:new, "english"}} = op} = Codec.decode(new)
    assert Codec.encode(op) == new

    assert {:ok, %Translate{texts: %{}, reviewed: []}} = Codec.decode(Map.drop(map, ["texts", "reviewed"]))
    assert {:error, _} = Codec.decode(Map.delete(map, "source_digest"))
  end
end
