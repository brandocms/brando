defmodule BrandoAdmin.UtilsClearCachesLiveTest do
  # Utilities → Clear caches: for content a script or data migration wrote
  # outside the admin, on a server the script cannot reach. Superusers only,
  # on every node, recorded in Activity. What it clears is
  # `Brando.Cache.clear_all/0`'s (test/brando/cache/clear_content_test.exs).
  #
  # Synchronous: it rebuilds the site caches and empties the query cache.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.CacheSync
  alias Brando.Pages.Page

  @site_caches ~w(globals identity navigation palettes seo)

  setup %{current_user: user} do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo, {Brando.Cache.Freshness, :tokens}])
    preserve_query_cache([Page])
    CacheSync.sync()
    on_exit(fn -> CacheSync.sync() end)
    Brando.endpoint().subscribe("user:#{user.id}")
    :ok
  end

  test "a superuser clears the caches: a cached page shows what a script wrote, and Activity records it", c do
    page = Factory.insert(:page, title: "Before", uri: "utils-clear-caches")
    opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}
    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "After"])

    {:ok, view, _html} = live(c.conn, "/admin/config/utils")
    html = view |> element("#utils-caches button", "Clear caches") |> render_click()

    assert {:ok, %{title: "After"}} = Brando.Pages.get_page(opts)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Caches cleared."}}

    # What it cleared shows under the action
    assert html =~ ~r/Emptied \d+ cached entr/
    assert html =~ "Rebuilt identity, SEO, globals, palettes and menus"

    user_id = c.current_user.id

    assert [%Event{action: :caches_cleared, user_id: ^user_id, entry_id: nil, details: details}] =
             Repo.all(from(e in Event, where: e.action == :caches_cleared))

    assert details["scope"] == "all"
    assert is_integer(details["entries"]) and details["entries"] >= 1
    assert Enum.sort(details["caches"]) == @site_caches
    assert details["site_structure"] == []

    # The log says what happened
    {:ok, activity, _html} = live(c.conn, "/admin/config/activity")
    assert has_element?(activity, ".activity-action", "Cleared")
    assert has_element?(activity, ".activity-entry", "Caches")
    assert has_element?(activity, ".activity-detail", "Every site")
    assert has_element?(activity, ".activity-detail", "Rebuilt identity, SEO, globals, palettes and menus")
  end

  test "the other nodes clear theirs: every site's query cache and site caches", c do
    Phoenix.PubSub.subscribe(Brando.pubsub(), CacheSync.topic())

    {:ok, view, _html} = live(c.conn, "/admin/config/utils")
    view |> element("#utils-caches button") |> render_click()

    assert_received {:brando_cache_sync, origin, {Brando.Cache.Query, {:clear, :all}}}
    assert origin == CacheSync.origin()

    for cache <- ~w(identity seo globals palettes navigation)a,
        do: assert_received({:brando_cache_sync, _, {Brando.Cache, {^cache, nil}}})
  end

  test "an administrator who is no superuser has no such action, and the event is refused" do
    admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    conn = Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), admin)
    Brando.endpoint().subscribe("user:#{admin.id}")

    page = Factory.insert(:page, title: "Before", uri: "utils-clear-caches-admin")
    opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}
    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "After"])

    {:ok, view, _html} = live(conn, "/admin/config/utils")
    refute has_element?(view, "#utils-caches")

    render_click(view, "clear_caches", %{})

    assert_receive %Phoenix.Socket.Broadcast{
      event: "toast",
      payload: %{payload: "You do not have permission for this action."}
    }

    assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
    assert [] == Repo.all(from(e in Event, where: e.action == :caches_cleared))
  end

  # The screen that had "Empty all caches" is gone; bookmarks of it land here
  test "the Cache screen's address redirects to Utilities", c do
    assert c.conn |> get("/admin/config/cache") |> redirected_to() == "/admin/config/utils"
    assert {:error, {:redirect, %{to: "/admin/config/utils"}}} = live(c.conn, "/admin/config/cache")
  end
end
