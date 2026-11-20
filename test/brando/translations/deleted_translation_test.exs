defmodule Brando.Translations.DeletedTranslationTest do
  # A synchronized translation deleted for good gives its language back; one in
  # the trash keeps it, and its place in the group, until it is restored or
  # purged (#3752). Not async: pages are made synchronized through the
  # application env.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.SoftDelete.Query
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.Group
  alias Brando.Translations.Member
  alias Brando.Translations.PendingVersion
  alias Brando.Translations.WorkItem

  setup do
    user = Factory.insert(:random_user, role: :superuser)

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

    %{user: user, module: module}
  end

  defp member_ids(schema, entry_id) do
    type = to_string(schema)
    Repo.all(from m in Member, where: m.entry_type == ^type and m.entry_id == ^entry_id, select: m.id)
  end

  defp work_of(member_id) do
    versions = Repo.all(from v in PendingVersion, where: v.member_id == ^member_id, select: v.id)
    items = Repo.all(from w in WorkItem, where: w.pending_version_id in ^versions, select: w.id)
    {versions, items}
  end

  defp expire(schema, id) do
    old = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -31 * 86_400)
    Repo.update_all(from(t in schema, where: t.id == ^id), set: [deleted_at: old])
  end

  defp linked_ids(schema, entry_id) do
    alternate = Module.concat(schema, Alternate)
    Repo.all(from a in alternate, where: a.entry_id == ^entry_id, select: a.linked_entry_id)
  end

  describe "a schema without a trash" do
    setup c do
      {:ok, source} =
        SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, c.user)

      TranslationFixtures.add_block(source, c.module, c.user, "Første avsnitt", 0)
      %{source: source}
    end

    test "a deleted translation leaves its group with its work, and its language can be created again", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      [member_id] = member_ids(Article, target.id)
      assert {[_ | _], [_ | _]} = work_of(member_id)

      assert {:ok, _} = SyncTest.delete_article(target.id, c.user)

      assert member_ids(Article, target.id) == []
      assert work_of(member_id) == {[], []}
      assert linked_ids(Article, c.source.id) == []
      assert Translations.missing_languages(Article, Repo.get!(Article, c.source.id)) == ["en"]

      assert {:ok, again} = Translations.create_target(Article, c.source.id, :en, c.user)
      assert %{role: :target, language: "en"} = Translations.get_member(Article, again.id)
    end

    test "a deleted source with no synchronized translation takes its group with it", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      %{group_id: group_id} = Translations.get_member(Article, c.source.id)
      {:ok, _} = Translations.make_independent(Article, target.id, c.user)

      assert {:ok, _} = SyncTest.delete_article(c.source.id, c.user)

      assert Repo.get(Group, group_id) == nil
      assert Translations.get_member(Article, target.id) == nil
      # The independent version is left as it was, outside any group
      assert %Article{} = Repo.get(Article, target.id)
    end

    test "a resync queued before the source was deleted finds its group gone, and is done", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      %{group_id: group_id, id: member_id} = Translations.get_member(Article, target.id)
      {:ok, _} = Translations.make_independent(Article, target.id, c.user)
      {:ok, _} = SyncTest.delete_article(c.source.id, c.user)

      assert {:error, :group_not_found} = Translations.resync_target(group_id, member_id)

      assert :ok = perform_job(Brando.Worker.TranslationSync, %{"group_id" => group_id, "member_id" => member_id})
    end

    test "a source with synchronized translations is still refused", c do
      {:ok, _target} = Translations.create_target(Article, c.source.id, :en, c.user)

      assert {:error, :group_has_synchronized_members} = SyncTest.delete_article(c.source.id, c.user)
      assert %{role: :source} = Translations.get_member(Article, c.source.id)
    end
  end

  describe "a schema with a trash" do
    setup c do
      # Pages have a trash; synchronized for these tests
      put_test_env(Page, translatable: [mode: :synchronized])
      put_test_env(:tenancy_mode, :none)
      page = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: c.user)
      {:ok, target} = Translations.create_target(Page, page.id, :en, c.user)
      {:ok, _} = Pages.delete_page(target.id, c.user)
      %{page: page, target: target}
    end

    test "a translation in the trash keeps its language, and creating it is refused as in the trash", c do
      assert [_member_id] = member_ids(Page, c.target.id)
      assert {:error, :language_in_trash} = Translations.create_target(Page, c.page.id, :en, c.user)
      assert Translations.missing_languages(Page, c.page) == []
    end

    test "a proposal to create the language is refused as in the trash", c do
      op = %Brando.Content.Proposals.CreateTranslation{source: {Page, c.page.id}, language: "en", ref: "english"}
      {:ok, proposal} = Brando.Content.Proposals.prepare([op], c.user)

      assert [%{operation: 0, code: :language_in_trash}] = proposal.problems
    end

    test "the source's delete is refused while the translation is in the trash, which counts", c do
      assert {:error, :group_has_synchronized_members} = Pages.delete_page(c.page.id, c.user)
      assert Translations.trashed_synchronized_targets?(Page, c.page.id)

      {:ok, _} = Brando.Authorization.Boundary.restore(c.user, Repo.get!(Page, c.target.id))

      refute Translations.trashed_synchronized_targets?(Page, c.page.id)
    end

    test "the listing marks a version in the trash", c do
      versions = Translations.listing_status(Page, [c.page])[c.page.id]

      assert [%{role: :source, in_trash: false}, %{language: "en", in_trash: true}] = versions
    end

    test "a restored translation is back in its group as it was", c do
      %{group_id: group_id, id: member_id} = Translations.get_member(Page, c.target.id)
      {pending, items} = work_of(member_id)

      {:ok, _} = Brando.Authorization.Boundary.restore(c.user, Repo.get!(Page, c.target.id))

      assert %{id: ^member_id, group_id: ^group_id, role: :target, synchronized: true} =
               Translations.get_member(Page, c.target.id)

      assert work_of(member_id) == {pending, items}
      assert [%{in_trash: false}, %{in_trash: false}] = Translations.listing_status(Page, [c.page])[c.page.id]
    end

    test "emptying the trash frees the language", c do
      [member_id] = member_ids(Page, c.target.id)
      expire(Page, c.target.id)

      refute Enum.any?(Query.clean_up_soft_deletions(), &match?({:error, _}, &1))

      refute Repo.get(Page, c.target.id)
      assert member_ids(Page, c.target.id) == []
      assert work_of(member_id) == {[], []}
      assert linked_ids(Page, c.page.id) == []
      assert Translations.missing_languages(Page, c.page) == ["en"]
      assert {:ok, _again} = Translations.create_target(Page, c.page.id, :en, c.user)
    end
  end
end
