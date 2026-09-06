defmodule Brando.Authorization.ContextTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()
    page = Factory.insert(:page, status: :draft)
    %{owner: owner, user: user, page: page, scope: Scope.standalone(owner)}
  end

  test "direct generated mutations reject a user without grants and leave the row unchanged", c do
    assert {:error, :forbidden} = Pages.update_page(c.page.id, %{title: "Unauthorized"}, c.user)
    assert {:error, :forbidden} = Pages.delete_page(c.page.id, c.user)
    assert Repo.get!(Page, c.page.id).title == c.page.title
    assert Repo.get!(Page, c.page.id).deleted_at == nil
    before = Repo.aggregate(Page, :count)
    assert {:error, :forbidden} = Pages.create_page(%{title: "Denied"}, c.user)
    assert Repo.aggregate(Page, :count) == before
  end

  test "authorized context updates succeed and emit a current database result", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])
    assert {:ok, updated} = Pages.update_page(c.page.id, %{title: "Allowed"}, c.user)
    assert updated.title == "Allowed"
    assert Repo.get!(Page, c.page.id).title == "Allowed"
  end

  test "prebuilt changesets use the same checks as parameter maps", c do
    changeset = Ecto.Changeset.change(c.page, title: "Forged save")
    assert {:error, :forbidden} = Pages.update_page(changeset, c.user)
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])
    assert {:ok, updated} = Pages.update_page(changeset, c.user)
    assert updated.title == "Forged save"
  end

  test "a stale changeset cannot disguise a published entry as a draft", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])
    stale = Ecto.Changeset.change(c.page, title: "Must not go live")
    Repo.update!(Ecto.Changeset.change(c.page, status: :published))
    assert {:error, :forbidden} = Pages.update_page(stale, c.user)
    assert Repo.get!(Page, c.page.id).title == c.page.title
  end

  test "a user cannot unpublish or delete a live entry through ordinary CRUD", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update", "brando.pages.delete"])
    Repo.update!(Ecto.Changeset.change(c.page, status: :published))
    assert {:error, :forbidden} = Pages.update_page(c.page.id, %{status: :draft}, c.user)
    assert {:error, :forbidden} = Pages.delete_page(c.page.id, c.user)
    assert Repo.get!(Page, c.page.id).status == :published
  end

  test "scoped queries filter lists, ID lookups and counts while public reads remain available", c do
    Boundary.with_scope(Scope.standalone(c.user), fn ->
      assert {:ok, []} = Pages.list_pages(%{})
      assert {:error, {:page, :not_found}} = Pages.get_page(c.page.id)
      assert {:error, {:page, :not_found}} = Pages.get_page(%{matches: %{id: c.page.id}})
    end)

    assert {:ok, page} = Pages.get_page(c.page.id)
    assert page.id == c.page.id
    assert Boundary.current_scope() == nil
  end

  test "cached public results cannot bypass an admin scope", c do
    args = %{matches: %{id: c.page.id}, cache: true}
    assert {:ok, page} = Pages.get_page(args)
    assert page.id == c.page.id

    Boundary.with_scope(Scope.standalone(c.user), fn ->
      assert {:error, {:page, :not_found}} = Pages.get_page(args)
      assert {:ok, []} = Pages.list_pages(%{cache: true})
    end)
  end

  test "the last Superuser cannot be disabled through the generated User context", c do
    assert {:error, :last_superuser} = Brando.Users.update_user(c.owner.id, %{active: false}, c.owner)
    assert Repo.get!(Brando.Users.User, c.owner.id).active
  end

  test "group authority does not allow mass-assigning a legacy role", c do
    assert {:error, :forbidden} = Brando.Users.update_user(c.user.id, %{role: :superuser}, c.owner)
    assert Repo.get!(Brando.Users.User, c.user.id).role == :user
  end

  defp grant(c, keys) do
    {:ok, group} = Groups.create(c.scope, %{name: "Allowed actions"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    group
  end
end
