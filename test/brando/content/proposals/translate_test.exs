defmodule Brando.Content.Proposals.TranslateTest do
  # The translate operation: a batch of a synchronized translation's work,
  # answered as a reviewed proposal and saved as the translation form saves
  # it. Grouped: the authorization tests take the authorization lock
  # (Brando.Authorization.Groups.lock!/0) until they end.
  use Brando.ConnCase, async: true, group: :shared_locks

  import Brando.Test.Support, only: [put_test_env: 2]

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
  defp add_block(article, module, user) do
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

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
    block
  end

  # The English translations of every text
  defp english(c) do
    %{
      "title" => "Title",
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
    Enum.map(proposal.problems, &{&1.operation, &1.code, Map.get(&1, :key)})
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
      assert message =~ heading
      assert {:ok, %{status: "pending", problems: problems}} = Proposals.get(proposal.id, c.user)
      assert [%{code: :source_changed, key: ^heading}] = problems
      assert %{title: "Tittel"} = saved_texts(target.id)
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
             %{key: heading, label: "Text › Heading", source: "Overskrift", text: nil, reviewed?: true}
           ] = units

    assert heading == "#{c.prefix}/refs/heading/text"
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
