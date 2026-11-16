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

  test "with groups authorization, in the trash's and the restore's transaction" do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    user = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Brando.Authorization.Migration.run()

    trash_and_restore(user)
  end
end
