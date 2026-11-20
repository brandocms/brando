defmodule Brando.Content.Proposals.CreateTranslationTest do
  # The create_translation operation: the editor's Create translation as a
  # reviewed proposal. Grouped: the authorization tests take the
  # authorization lock (Brando.Authorization.Groups.lock!/0) until they end.
  use Brando.ConnCase, async: true, group: :shared_locks

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.Content.Proposals.CreateTranslation
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.Review
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetFields
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    block = TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)

    %{user: user, module: module, source: source, block_uid: block.uid}
  end

  defp op(c, opts \\ []) do
    %CreateTranslation{
      source: Keyword.get(opts, :source, {Article, c.source.id}),
      language: Keyword.get(opts, :language, "en"),
      ref: Keyword.get(opts, :ref, "english")
    }
  end

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  defp codes(ops, user) do
    {:ok, proposal} = Proposals.prepare(ops, user)
    Enum.map(proposal.problems, &{&1.operation, &1.code})
  end

  defp open_items(id) do
    Article
    |> Translations.get_pending_version(id)
    |> Map.fetch!(:work_items)
    |> Enum.filter(&is_nil(&1.resolved_at))
    |> Enum.map(&{&1.kind, &1.path})
    |> Enum.sort()
  end

  defp articles, do: Repo.aggregate(Article, :count)

  test "applied, it creates the translation in the source's group, unpublished, with every copied text to translate",
       c do
    assert {:ok, proposal} = Proposals.propose([op(c)], c.user)
    assert proposal.problems == []
    assert proposal.effects.creates == 1
    # Nothing is written while the proposal is reviewed
    assert Translations.get_member(Article, c.source.id) == nil

    assert {:ok, receipt} = approve_and_apply(proposal, c.user)
    assert %{"english" => id} = receipt.mappings["created"]

    translation = Repo.get!(Article, id)
    assert translation.language == :en
    # Unpublished, though the source is published
    assert translation.status == :draft

    assert %{role: :source, group_id: group_id} = Translations.get_member(Article, c.source.id)
    assert %{role: :target, synchronized: true, group_id: ^group_id} = Translations.get_member(Article, id)
    assert Translations.alternate_languages(Article, c.source.id) == ["en"]

    # The state the admin's Create translation leaves
    {:ok, other} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "annen-#{c.source.id}", language: "no", status: "published"},
        c.user
      )

    other_block = TranslationFixtures.add_block(other, c.module, c.user, "<p>Første avsnitt</p>", 0)
    {:ok, admin} = Translations.create_target(Article, other.id, :en, c.user)

    assert open_items(id) == [{:translate, "entry_blocks/#{c.block_uid}/refs/body/text"}, {:translate, "title"}]

    assert open_items(admin.id) ==
             [{:translate, "entry_blocks/#{other_block.uid}/refs/body/text"}, {:translate, "title"}]
  end

  test "it is refused for a content type that is not synchronized", c do
    page = Factory.insert(:page, creator: c.user, language: :no)
    assert codes([op(c, source: {Page, page.id})], c.user) == [{0, :not_synchronized}]
  end

  test "it is refused for a source that is not there", c do
    assert codes([op(c, source: {Article, 0})], c.user) == [{0, :unknown_target}]
  end

  test "it is refused for a language the site lacks, and for the source's own", c do
    assert codes([op(c, language: "de")], c.user) == [{0, :unknown_language}]
    assert codes([op(c, language: "no")], c.user) == [{0, :same_language}]
  end

  test "it is refused when the group already has the language, or an independent version holds it", c do
    {:ok, _} = Translations.create_target(Article, c.source.id, :en, c.user)
    assert codes([op(c)], c.user) == [{0, :language_exists}]

    {:ok, lone} =
      SyncTest.create_article(%{title: "Alone", slug: "alone-#{c.source.id}", language: "no", status: "draft"}, c.user)

    {:ok, english} =
      SyncTest.create_article(%{title: "Alone", slug: "alone-en-#{c.source.id}", language: "en", status: "draft"}, c.user)

    :ok = Article.Alternate.add(lone.id, english.id)
    assert codes([op(c, source: {Article, lone.id})], c.user) == [{0, :language_exists}]
    # The refusal enrolled nothing
    assert Translations.get_member(Article, lone.id) == nil
  end

  test "it is refused when an earlier operation creates the same version, or uses the same ref", c do
    assert codes([op(c), op(c, ref: "again")], c.user) == [{1, :language_exists}]

    create = %CreateEntry{schema: Article, ref: "english", fields: %{title: "X", slug: "x", language: "en"}}
    assert {0, :duplicate_ref} in codes([create, op(c)], c.user)
  end

  test "named a translation, the problem names the group's source", c do
    {:ok, english} = Translations.create_target(Article, c.source.id, :en, c.user)

    {:ok, proposal} = Proposals.prepare([op(c, source: {Article, english.id}, language: "no")], c.user)
    assert [%{code: :not_source, message: message}] = proposal.problems
    assert message =~ ~s("id":#{c.source.id})
  end

  test "other operations on the new translation are refused, pointing at translate", c do
    target = {:new, "english"}

    ops = [
      op(c),
      %SetFields{target: target, fields: %{"title" => "Title"}},
      %InsertBlock{target: target, module: c.module.id},
      %SetBlockText{target: target, block_uid: c.block_uid, ref: "body", text: "<p>First</p>"}
    ]

    {:ok, proposal} = Proposals.prepare(ops, c.user)

    assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
             {1, :use_translate},
             {2, :use_translate},
             {3, :use_translate}
           ]

    assert Enum.all?(proposal.problems, &(&1.message =~ "translate"))
  end

  test "an apply after the language was taken says why, and creates nothing", c do
    {:ok, proposal} = Proposals.propose([op(c)], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Translations.create_target(Article, c.source.id, :en, c.user)
    count = articles()

    assert {:error, _message} = Proposals.apply(proposal.id, proposal.version, c.user)
    assert articles() == count
    assert {:ok, %{status: "pending", problems: [%{code: :language_exists}]}} = Proposals.get(proposal.id, c.user)
  end

  test "a later failure rolls the translation back with the rest of the apply", c do
    create = %CreateEntry{
      schema: Page,
      ref: "page",
      fields: %{title: "Page", uri: "taken-later", language: "en", template: "default.html"}
    }

    {:ok, proposal} = Proposals.propose([op(c), create], c.user)
    assert proposal.problems == []
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    Factory.insert(:page, uri: "taken-later", language: :en, creator: c.user)
    count = articles()

    assert {:error, message} = Proposals.apply(proposal.id, proposal.version, c.user)
    assert message =~ "already in use"
    assert articles() == count
    assert Translations.get_member(Article, c.source.id) == nil
    assert Translations.alternate_languages(Article, c.source.id) == []
  end

  test "undo removes the translation and the group the apply made", c do
    {:ok, proposal} = Proposals.propose([op(c)], c.user)
    {:ok, receipt} = approve_and_apply(proposal, c.user)
    id = receipt.mappings["created"]["english"]

    assert {:ok, _} = Proposals.undo(proposal.id, c.user)
    assert Repo.get(Article, id) == nil
    assert Translations.get_member(Article, id) == nil
    assert Translations.get_member(Article, c.source.id) == nil
    assert Translations.alternate_languages(Article, c.source.id) == []

    # The language is free again
    assert {:ok, _} = Translations.create_target(Article, c.source.id, :en, c.user)
  end

  test "undo leaves a group that was there before as it was", c do
    {:ok, source_member} = Translations.enroll_source(Article, c.source.id, c.user)
    {:ok, proposal} = Proposals.propose([op(c)], c.user)
    {:ok, receipt} = approve_and_apply(proposal, c.user)
    id = receipt.mappings["created"]["english"]

    assert {:ok, _} = Proposals.undo(proposal.id, c.user)
    assert Translations.get_member(Article, id) == nil
    assert Translations.list_members(source_member.group_id) == [Repo.reload!(source_member)]
  end

  # Another version joins the group after the apply. The test site has two
  # languages, so it joins under a third, with its own pending version.
  defp join_group(c, group_id) do
    {:ok, other} =
      SyncTest.create_article(
        %{title: "Titel", slug: "titel-#{System.unique_integer([:positive])}", language: "en", status: "draft"},
        c.user
      )

    member =
      Repo.insert!(%Translations.Member{
        group_id: group_id,
        entry_type: to_string(Article),
        entry_id: other.id,
        language: "de",
        role: :target,
        synchronized: true
      })

    {:ok, _} = Translations.resync_target(group_id, member.id)
    Repo.reload!(member)
  end

  test "undo keeps a group another version joined after the apply, with that version's work", c do
    {:ok, proposal} = Proposals.propose([op(c)], c.user)
    {:ok, receipt} = approve_and_apply(proposal, c.user)
    id = receipt.mappings["created"]["english"]
    %{group_id: group_id} = source_member = Translations.get_member(Article, c.source.id)

    later = join_group(c, group_id)
    pending = Translations.get_pending_version(Article, later.entry_id)
    assert pending.work_items != []

    assert {:ok, _} = Proposals.undo(proposal.id, c.user)
    assert Repo.get(Article, id) == nil
    assert Translations.get_member(Article, id) == nil
    assert Translations.get_member(Article, c.source.id) == source_member
    assert Translations.get_member(Article, later.entry_id) == later

    assert %{id: pending_id, work_items: items} = Translations.get_pending_version(Article, later.entry_id)
    assert pending_id == pending.id
    assert Enum.map(items, & &1.id) == Enum.map(pending.work_items, & &1.id)
  end

  test "undo is refused when the translation has since become its group's source", c do
    {:ok, proposal} = Proposals.propose([op(c)], c.user)
    {:ok, receipt} = approve_and_apply(proposal, c.user)
    id = receipt.mappings["created"]["english"]
    {:ok, _} = Translations.transfer_source(Article, id, c.user)

    assert {:error, _message} = Proposals.undo(proposal.id, c.user)
    assert Repo.get(Article, id)
    assert %{role: :source, group_id: group_id} = Translations.get_member(Article, id)
    assert %{role: :target, group_id: ^group_id} = Translations.get_member(Article, c.source.id)
    assert Translations.alternate_languages(Article, c.source.id) == ["en"]
    assert {:ok, %{status: "applied"}} = Proposals.get(proposal.id, c.user)
  end

  test "undo of a proposal that also changed the source leaves no synchronization that fails", c do
    ops = [%SetFields{target: {Article, c.source.id}, fields: %{"subtitle" => "Endret"}}, op(c)]
    {:ok, proposal} = Proposals.propose(ops, c.user)
    assert proposal.problems == []
    {:ok, _receipt} = approve_and_apply(proposal, c.user)

    jobs =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Proposals.undo(proposal.id, c.user)
        all_enqueued(worker: Brando.Worker.TranslationSync)
      end)

    assert Translations.get_member(Article, c.source.id) == nil
    assert jobs != []
    for job <- jobs, do: assert(:ok = perform_job(Brando.Worker.TranslationSync, job.args))
  end

  test "an actor without create is refused, with groups", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}
    editor = Factory.insert(:random_user, role: :user)

    grants = [Catalog.get(:read, Article).key, Catalog.get(:update, Article).key, "brando.admin.access"]
    {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Article editors"}, grants)
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)

    assert codes([op(c)], editor) == [{0, :forbidden}]
  end

  test "an actor who may create but not update is refused when the proposal is prepared, with groups", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}
    creator = Factory.insert(:random_user, role: :user)

    grants =
      Enum.map([:read, :create, :duplicate], &Catalog.get(&1, Article).key) ++ ["brando.admin.access"]

    {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Article creators"}, grants)
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, creator.id)

    assert codes([op(c)], creator) == [{0, :forbidden}]
  end

  test "an actor without create is refused, in legacy mode", c do
    editor = Factory.insert(:random_user, role: :user)
    assert codes([op(c)], editor) == [{0, :forbidden}]
  end

  test "the review shows it as its own card", c do
    {:ok, proposal} = Proposals.propose([op(c)], c.user)

    assert [%{action: :create, title: "Tittel", preview?: false, changes: [change]}] = Review.entries(proposal)
    assert %{type: :create_translation, language: "en", source: %{title: "Tittel", id: id}} = change
    assert id == c.source.id
  end

  test "the codec decodes and encodes it" do
    map = %{
      "op" => "create_translation",
      "source" => %{"content_type" => "Brando.SyncTest.Article", "id" => 5},
      "language" => "en",
      "ref" => "english"
    }

    assert {:ok, %CreateTranslation{source: {Article, 5}, language: "en", ref: "english"} = op} = Codec.decode(map)
    assert Codec.encode(op) == map

    assert {:error, _} = Codec.decode(%{map | "source" => %{"new" => "x"}})
    assert {:error, _} = Codec.decode(%{map | "source" => Map.put(map["source"], "new", "x")})
    assert {:error, _} = Codec.decode(Map.delete(map, "language"))
  end
end
