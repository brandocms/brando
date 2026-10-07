defmodule BrandoAdmin.ActivityLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Pages

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp create_page(user, title) do
    {:ok, page} =
      Pages.create_page(
        %{
          title: title,
          uri: "activity-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html",
          status: :draft
        },
        user
      )

    page
  end

  test "lists what happened, by day, with the person and the entry", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")
    {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel", meta_description: "By the sea"}, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    assert has_element?(view, "h1", "Activity")
    assert has_element?(view, ".activity-day h2", "Today")
    assert has_element?(view, ".activity-row .activity-action", "Created")
    assert has_element?(view, ".activity-row .activity-action", "Updated")
    assert has_element?(view, ".activity-row a.activity-entry", "Sommerro hotel")
    assert has_element?(view, ".activity-row .activity-person-name", user.name)
    assert has_element?(view, ".activity-detail", "Changed SEO description and title")
    assert has_element?(view, ".activity-count", "2 events")
  end

  test "filters by action and by title", %{conn: conn, current_user: user} do
    create_page(user, "Sommerro")
    page = create_page(user, "Villa Tide")
    {:ok, _} = Pages.delete_page(page.id, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    view |> form("#activity-filters", %{action: "trashed"}) |> render_change()
    assert_patch(view, "/admin/config/activity?action=trashed")
    assert has_element?(view, ".activity-row .activity-action", "Moved to trash")
    refute has_element?(view, ".activity-row .activity-action", "Created")
    assert has_element?(view, ".activity-row .utils-button", "Open trash")

    {:ok, view, _} = live(conn, "/admin/config/activity?q=sommer")
    assert has_element?(view, ".activity-entry", "Sommerro")
    refute has_element?(view, ".activity-entry", "Villa Tide")
  end

  test "compares a change with the revision before it", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")
    {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel"}, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    view |> element(".activity-row button", "Compare") |> render_click()

    assert has_element?(view, "#activity-compare-modal")
    assert render(element(view, "#activity-comparison")) =~ "Sommerro hotel"
  end

  test "an entry deleted for good keeps its title, without a link", %{conn: conn, current_user: user} do
    page = Factory.insert(:page, creator: user, title: "Gone")
    Brando.Repo.delete!(page)
    Brando.Activity.deleted(page, user, false)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    assert has_element?(view, ".activity-entry.is-gone", "Gone")
    refute has_element?(view, "a.activity-entry", "Gone")

    assert has_element?(view, ".activity-action", "Deleted permanently")
  end

  test "a change prepared over MCP names the tool, and the person who approved it", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")

    Brando.Activity.with_source(:mcp, %{"client" => "Claude Code"}, fn ->
      {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel"}, user)
    end)

    {:ok, view, _} = live(conn, "/admin/config/activity")
    assert has_element?(view, ".activity-person.is-source", "Claude Code via MCP")
    assert has_element?(view, ".activity-person.is-source small", "Approved by #{user.name}")
  end

  test "editors can't open it without group authorization", %{conn: conn} do
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    conn = log_in_user(conn, editor)

    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/activity")
  end
end
