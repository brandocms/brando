defmodule Brando.Pages.DeletePageFragmentsGroupsTest do
  # Deleting a page with fragments under group authorization (#3621): the
  # fragments take rights of their own, and the dialog names only those the
  # viewer may read
  use Brando.ConnCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias BrandoAdmin.LiveView.Listing.DeleteDescription

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    on_exit(fn -> Boundary.put_scope(nil) end)

    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()

    parent = Factory.insert(:page, uri: "parent", title: "Parent", status: :draft)
    page = Factory.insert(:page, uri: "parent/child", title: "Child", parent_id: parent.id, status: :draft)
    fragment = Factory.insert(:fragment, page_id: page.id, title: "Secret footer", key: "footer", status: :draft)

    %{owner: owner, user: user, parent: parent, page: page, fragment: fragment, scope: Scope.standalone(owner)}
  end

  defp grant(c, keys) do
    {:ok, group} = Groups.create(c.scope, %{name: "Page deleters"}, ["brando.admin.access" | keys])
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
  end

  @pages ~w(brando.pages.read brando.pages.delete)

  test "without the right to move the fragments, the page is not deleted", c do
    grant(c, @pages)

    assert {:error, :forbidden} = Pages.delete_page(c.page.id, c.user)
    assert {:error, :forbidden} = Pages.delete_page(c.page.id, c.user, fragments: :delete)

    assert is_nil(Repo.get!(Page, c.page.id).deleted_at)
    assert %{page_id: page_id, deleted_at: nil} = Repo.get!(Fragment, c.fragment.id)
    assert page_id == c.page.id
  end

  test "with the right to update them, they move", c do
    grant(c, @pages ++ ~w(brando.pages_fragments.read brando.pages_fragments.update))

    assert {:ok, _} = Pages.delete_page(c.page.id, c.user)
    assert Repo.get!(Fragment, c.fragment.id).page_id == c.parent.id
    # Deleting them takes the right to delete them
    assert {:error, :forbidden} = Pages.delete_page(c.parent.id, c.user, fragments: :delete)
  end

  test "the dialog counts the fragments the viewer may not read, and offers no choice it may not take", c do
    grant(c, @pages)

    Boundary.with_scope(Scope.standalone(c.user), fn ->
      %{html: html, choice: choice} = DeleteDescription.describe(Page, Repo.get!(Page, c.page.id))

      refute html =~ "Secret footer"
      assert html =~ "One more you may not see"
      assert choice.options == []
      assert html =~ "can't be deleted"
    end)
  end
end
