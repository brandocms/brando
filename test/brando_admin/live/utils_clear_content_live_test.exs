defmodule BrandoAdmin.UtilsClearContentLiveTest do
  # Utilities → Clear content caches: for content a script or data migration
  # wrote outside the admin, on a server the script cannot reach. Superusers
  # only, recorded in Activity.
  #
  # Synchronous: it rebuilds the site caches and empties the query cache.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Pages.Page

  setup %{current_user: user} do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo, {Brando.Cache.Freshness, :tokens}])
    preserve_query_cache([Page])
    Brando.CacheSync.sync()
    on_exit(fn -> Brando.CacheSync.sync() end)
    Brando.endpoint().subscribe("user:#{user.id}")
    :ok
  end

  test "a superuser clears the caches: a cached page shows what a script wrote, and Activity records it", c do
    page = Factory.insert(:page, title: "Before", uri: "utils-clear-content")
    opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}
    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "After"])

    {:ok, view, _html} = live(c.conn, "/admin/config/utils")
    html = view |> element("#utils-content-caches button", "Clear content caches") |> render_click()

    assert {:ok, %{title: "After"}} = Brando.Pages.get_page(opts)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Content caches cleared."}}

    # What it cleared shows under the action
    assert html =~ ~r/Emptied \d+ cached entr/
    assert html =~ "Rebuilt identity, SEO, globals, palettes and menus"

    user_id = c.current_user.id

    assert [%Event{action: :caches_cleared, user_id: ^user_id, entry_id: nil, details: details}] =
             Repo.all(from(e in Event, where: e.action == :caches_cleared))

    assert details["scope"] == "site"
    assert is_integer(details["entries"]) and details["entries"] >= 1
    assert Enum.sort(details["caches"]) == ~w(globals identity navigation palettes seo)

    # The log says what happened
    {:ok, _activity, activity_html} = live(c.conn, "/admin/config/activity")
    assert activity_html =~ "Cleared caches"
    assert activity_html =~ "Content caches"
  end

  test "an administrator who is no superuser has no such action, and the event is refused" do
    admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    conn = Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), admin)
    Brando.endpoint().subscribe("user:#{admin.id}")

    page = Factory.insert(:page, title: "Before", uri: "utils-clear-content-admin")
    opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}
    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "After"])

    {:ok, view, _html} = live(conn, "/admin/config/utils")
    refute has_element?(view, "#utils-content-caches")

    render_click(view, "clear_content_caches", %{})

    assert_receive %Phoenix.Socket.Broadcast{
      event: "toast",
      payload: %{payload: "You do not have permission for this action."}
    }

    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    assert [] == Repo.all(from(e in Event, where: e.action == :caches_cleared))
  end
end
