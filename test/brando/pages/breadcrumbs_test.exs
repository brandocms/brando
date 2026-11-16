defmodule Brando.Pages.BreadcrumbsTest do
  # Grouped: groups authorization takes the authorization lock
  # (Brando.Authorization.Groups.lock!/0) until the test ends
  use Brando.ConnCase, async: true, group: :shared_locks

  alias Brando.Authorization.Boundary
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  defp page!(user, attrs) do
    params = Map.merge(%{language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp trail(page), do: Enum.map(Repo.get!(Page, page.id).breadcrumbs, & &1["title"])

  defp trash_and_restore(user) do
    about = page!(user, %{title: "About", uri: "about"})
    team = page!(user, %{title: "Team", uri: "about/team", parent_id: about.id})
    people = page!(user, %{title: "People", uri: "about/team/people", parent_id: team.id})
    app_name = Brando.config(:app_name)

    assert trail(people) == [app_name, "About", "Team", "People"]

    # A cached query of the child is evicted with the recompute
    {:ok, cached} = Pages.get_page(%{matches: %{id: team.id}, cache: {:ttl, :timer.minutes(5)}})
    assert Enum.map(cached.breadcrumbs, & &1["title"]) == [app_name, "About", "Team"]

    {:ok, _} = Pages.delete_page(about.id, user)
    assert trail(team) == [app_name, "Team"]
    assert trail(people) == [app_name, "Team", "People"]

    {:ok, cached} = Pages.get_page(%{matches: %{id: team.id}, cache: {:ttl, :timer.minutes(5)}})
    assert Enum.map(cached.breadcrumbs, & &1["title"]) == [app_name, "Team"]

    {:ok, _} = Boundary.restore(user, Repo.get!(Page, about.id))
    assert trail(about) == [app_name, "About"]
    assert trail(team) == [app_name, "About", "Team"]
    assert trail(people) == [app_name, "About", "Team", "People"]
  end

  test "trashing and restoring a page recompute its descendants' trails" do
    put_test_env(:tenancy_mode, :none)
    trash_and_restore(Factory.insert(:random_user, role: :superuser))
  end

  describe "a live page under a trashed page" do
    setup do
      put_test_env(:tenancy_mode, :none)
      user = Factory.insert(:random_user, role: :superuser)
      a = page!(user, %{title: "A", uri: "a"})
      b = page!(user, %{title: "B", uri: "a/b", parent_id: a.id})
      c = page!(user, %{title: "C", uri: "a/b/c", parent_id: b.id})
      %{user: user, a: a, b: b, c: c, app_name: Brando.config(:app_name)}
    end

    test "loses a page trashed above the trashed one", %{user: user, a: a, b: b, c: c, app_name: app_name} do
      {:ok, _} = Pages.delete_page(b.id, user)
      assert trail(c) == [app_name, "A", "C"]

      {:ok, _} = Pages.delete_page(a.id, user)
      assert trail(c) == [app_name, "C"]
    end

    test "takes back a page restored above the trashed one", %{user: user, a: a, b: b, c: c, app_name: app_name} do
      {:ok, _} = Pages.delete_page(a.id, user)
      {:ok, _} = Pages.delete_page(b.id, user)
      assert trail(c) == [app_name, "C"]

      {:ok, _} = Boundary.restore(user, Repo.get!(Page, a.id))
      assert trail(c) == [app_name, "A", "C"]
    end
  end

  test "restoring a revision of a page does not bring back its old trail" do
    put_test_env(:tenancy_mode, :none)
    user = Factory.insert(:random_user, role: :superuser)
    about = page!(user, %{title: "About", uri: "about"})
    team = page!(user, %{title: "Team", uri: "about/team", parent_id: about.id})
    {:ok, revision} = Brando.Revisions.create_revision(Repo.get!(Page, team.id), user)

    {:ok, _} = Pages.update_page(about.id, %{title: "About us"}, user)
    assert trail(team) == [Brando.config(:app_name), "About us", "Team"]

    {:ok, _} = Brando.Revisions.set_entry_to_revision(Page, team.id, revision.revision, user)
    assert trail(team) == [Brando.config(:app_name), "About us", "Team"]
  end

  describe "a parent cycle" do
    setup do
      put_test_env(:tenancy_mode, :none)
      user = Factory.insert(:random_user, role: :superuser)
      a = page!(user, %{title: "A", uri: "a"})
      b = page!(user, %{title: "B", uri: "a/b", parent_id: a.id})
      %{user: user, a: a, b: b}
    end

    test "is refused as a page's parent: the page itself or a page under it", %{user: user, a: a, b: b} do
      assert {:error, %Ecto.Changeset{errors: [parent_id: _]}} = Pages.update_page(a.id, %{parent_id: a.id}, user)
      assert {:error, %Ecto.Changeset{errors: [parent_id: _]}} = Pages.update_page(a.id, %{parent_id: b.id}, user)
      assert %{parent_id: nil} = Repo.get!(Page, a.id)
    end

    @tag timeout: 15_000
    test "a revision restore that would close one is refused", %{user: user, a: a, b: b} do
      {:ok, revision} = Brando.Revisions.create_revision(Repo.get!(Page, b.id), user)
      {:ok, _} = Pages.update_page(b.id, %{parent_id: nil}, user)
      {:ok, _} = Pages.update_page(a.id, %{parent_id: b.id}, user)

      assert {:error, %Ecto.Changeset{errors: [parent_id: _]}} =
               Brando.Revisions.set_entry_to_revision(Page, b.id, revision.revision, user)

      assert %{parent_id: nil} = Repo.get!(Page, b.id)
    end

    @tag timeout: 15_000
    test "already stored ends the trail and the descendants' walk", %{a: a, b: b} do
      Repo.update_all(from(p in Page, where: p.id == ^a.id), set: [parent_id: b.id])

      assert {:ok, _} = Pages.update_breadcrumbs(Repo.get!(Page, a.id))
      assert trail(a) == [Brando.config(:app_name), "B", "A"]
      assert trail(b) == [Brando.config(:app_name), "A", "B"]
    end
  end

  test "with groups authorization, in the trash's and the restore's transaction" do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    user = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Brando.Authorization.Migration.run()

    trash_and_restore(user)
  end
end
