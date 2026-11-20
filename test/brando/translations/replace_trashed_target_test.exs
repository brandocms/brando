defmodule Brando.Translations.ReplaceTrashedTargetTest do
  # Creating a translation in a language whose version is in the trash, as the
  # admin does after asking: the version in the trash is deleted for good, the
  # way the trash's purge deletes it, and the new one is created, in one
  # transaction (#3762). Not async: pages are made synchronized through the
  # application env.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Translations
  alias Brando.Translations.Member
  alias Brando.Translations.PendingVersion
  alias Brando.Translations.WorkItem

  setup do
    put_test_env(Page, translatable: [mode: :synchronized])
    put_test_env(:tenancy_mode, :none)
    user = Factory.insert(:random_user, role: :superuser)
    page = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)
    {:ok, target} = Translations.create_target(Page, page.id, :en, user)
    {:ok, _} = Pages.delete_page(target.id, user)
    %{user: user, page: page, target: target}
  end

  defp work_of(member_id) do
    versions = Repo.all(from v in PendingVersion, where: v.member_id == ^member_id, select: v.id)
    items = Repo.all(from w in WorkItem, where: w.pending_version_id in ^versions, select: w.id)
    {versions, items}
  end

  defp linked_ids(entry_id),
    do: Repo.all(from a in Page.Alternate, where: a.entry_id == ^entry_id, select: a.linked_entry_id)

  test "deletes the version in the trash for good and creates the new one in the group", c do
    %{id: member_id, group_id: group_id} = Translations.get_member(Page, c.target.id)
    assert {[_ | _], [_ | _]} = work_of(member_id)

    assert {:ok, replacement} = Translations.replace_trashed_target(Page, c.page.id, :en, c.user)

    refute Repo.get(Page, c.target.id)
    refute Repo.get(Member, member_id)
    assert work_of(member_id) == {[], []}
    assert linked_ids(c.page.id) == [replacement.id]

    assert [%{entry_id: source_id, role: :source}, %{entry_id: new_id, language: "en", role: :target}] =
             Translations.list_members(group_id)

    assert {source_id, new_id} == {c.page.id, replacement.id}
    assert %{deleted_at: nil, language: :en} = Repo.get!(Page, replacement.id)
  end

  test "runs the page's before_purge: a child page of the version in the trash is let go", c do
    child = Factory.insert(:page, title: "Child", uri: "child", language: :en, parent_id: c.target.id, creator: c.user)

    assert {:ok, _} = Translations.replace_trashed_target(Page, c.page.id, :en, c.user)

    assert %{parent_id: nil} = Repo.get!(Page, child.id)
  end

  test "a language with no version in the trash is created as Create translation does", c do
    other = Factory.insert(:page, title: "Kontakt", uri: "kontakt", language: :no, creator: c.user)

    assert {:ok, target} = Translations.replace_trashed_target(Page, other.id, :en, c.user)
    assert %{role: :target, language: "en"} = Translations.get_member(Page, target.id)
    # The other page's version in the trash is left as it was
    assert %{deleted_at: %DateTime{}} = Repo.get!(Page, c.target.id)
  end

  test "a version not in the trash is not replaced", c do
    {:ok, _} = Brando.Authorization.Boundary.restore(c.user, Repo.get!(Page, c.target.id))

    assert {:error, :language_exists} = Translations.replace_trashed_target(Page, c.page.id, :en, c.user)
    assert %{deleted_at: nil} = Repo.get!(Page, c.target.id)
  end

  test "Create translation still refuses a language in the trash", c do
    assert {:error, :language_in_trash} = Translations.create_target(Page, c.page.id, :en, c.user)
  end

  describe "with groups authorization" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      %{scope: Scope.standalone(c.user)}
    end

    defp editor(scope, keys) do
      user = Factory.insert(:random_user, role: :user)
      {:ok, group} = Groups.create(scope, %{name: "Editors #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
      user
    end

    @creates ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.create brando.pages.duplicate)

    test "an editor who may not delete pages is refused as in the trash", c do
      editor = editor(c.scope, @creates)

      assert {:error, :language_in_trash} = Translations.replace_trashed_target(Page, c.page.id, :en, editor)
      assert %{deleted_at: %DateTime{}} = Repo.get!(Page, c.target.id)
      assert Translations.get_member(Page, c.target.id)
    end

    test "an editor who may delete pages replaces it", c do
      editor = editor(c.scope, @creates ++ ["brando.pages.delete"])

      assert {:ok, _} = Translations.replace_trashed_target(Page, c.page.id, :en, editor)
      refute Repo.get(Page, c.target.id)
    end

    test "a create that fails leaves the version in the trash as it was", c do
      # May delete, but not create: the copy is refused after the delete
      editor = editor(c.scope, ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.delete))
      %{id: member_id} = Translations.get_member(Page, c.target.id)
      work = work_of(member_id)

      assert {:error, _} = Translations.replace_trashed_target(Page, c.page.id, :en, editor)

      assert %{deleted_at: %DateTime{}} = Repo.get!(Page, c.target.id)
      assert %{id: ^member_id} = Translations.get_member(Page, c.target.id)
      assert work_of(member_id) == work
      assert linked_ids(c.page.id) == [c.target.id]
    end
  end

  describe "with legacy authorization" do
    test "an account that may not delete is refused as in the trash", c do
      reader = Factory.insert(:random_user, role: :user)

      assert {:error, :language_in_trash} = Translations.replace_trashed_target(Page, c.page.id, :en, reader)
      assert %{deleted_at: %DateTime{}} = Repo.get!(Page, c.target.id)
    end
  end
end
