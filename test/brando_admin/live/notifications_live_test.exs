defmodule BrandoAdmin.Sites.NotificationsLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Notifications.Route
  alias Brando.Notifications.Routing
  alias Brando.Users.User
  alias Brando.Users.UserToken
  alias Brando.WebhookReceiver
  alias BrandoIntegration.Repo

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})
    :ok
  end

  @slack_url "https://hooks.example.com/services/T000/B000/topsecretkey"

  # A session that last gave its password `minutes` ago
  defp confirmed_ago(conn, minutes) do
    token = get_session(conn, :user_token)
    at = NaiveDateTime.add(NaiveDateTime.utc_now(), -minutes * 60, :second)
    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [confirmed_at: at])
  end

  defp create_route(user, attrs \\ %{}) do
    {:ok, route} =
      Routing.create_route(
        Map.merge(%{"name" => "Editors", "kind" => "slack", "url" => @slack_url, "events" => ["mention"]}, attrs),
        user
      )

    route
  end

  describe "Integrations" do
    test "has a Notifications row that sets up, then manages, routes", %{conn: conn, current_user: user} do
      {:ok, view, _html} = live(conn, "/admin/config/integrations")
      assert has_element?(view, "#integration-notifications a[href='/admin/config/notifications/new']")

      create_route(user)
      {:ok, view, _html} = live(conn, "/admin/config/integrations")
      assert has_element?(view, "#integration-notifications", "1 route")
      assert has_element?(view, "#integration-notifications a[href='/admin/config/notifications/deliveries']")
      assert has_element?(view, "#integration-notifications a[href='/admin/config/notifications']")
    end

    test "is for administrators", %{conn: conn} do
      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

      for path <- ~w(/admin/config/notifications /admin/config/notifications/new /admin/config/notifications/deliveries) do
        assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(log_in_user(conn, editor), path)
      end
    end
  end

  describe "creating" do
    test "a Slack route: the URL is stored encrypted and never shown again", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/notifications/new")

      view
      |> form("#notification-route-form",
        route: %{name: "Editors", kind: "slack", url: @slack_url, events: ["mention", "failed_job"]}
      )
      |> render_submit()

      assert [%Route{kind: :slack, events: ["mention", "failed_job"]} = route] = Routing.list_routes()
      assert_patch(view, "/admin/config/notifications/#{route.id}/edit")
      assert Routing.url(route) == {:ok, @slack_url}

      html = render(view)
      refute html =~ "topsecretkey"
      refute inspect(:sys.get_state(view.pid)) =~ "topsecretkey"
      assert has_element?(view, "[data-testid=notification-url-masked]", "hooks.example.com/…tkey")

      {:ok, _view, html} = live(conn, "/admin/config/notifications/#{route.id}/edit")
      refute html =~ "topsecretkey"
    end

    test "an email route to chosen users, for some content types", %{conn: conn, current_user: user} do
      reader = Factory.insert(:random_user, name: "Kari Nordmann")
      {:ok, view, _html} = live(conn, "/admin/config/notifications/new")

      html = view |> form("#notification-route-form", route: %{kind: "email"}) |> render_change()
      refute has_element?(view, "#route-url")
      assert html =~ "Kari Nordmann"
      # Nothing chosen yet is not an error until the form is saved
      refute html =~ "Choose at least one."

      view
      |> form("#notification-route-form",
        route: %{
          name: "Desk",
          kind: "email",
          recipient_ids: [reader.id, user.id],
          events: ["scheduled_publish", "scheduled_unpublish"],
          entry_types: ["pages.page"]
        }
      )
      |> render_submit()

      assert [%Route{kind: :email, recipient_ids: ids, entry_types: ["pages.page"], url_ciphertext: nil}] =
               Routing.list_routes()

      assert Enum.sort(ids) == Enum.sort([reader.id, user.id])
    end

    test "explains what is missing or refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/notifications/new")

      html =
        view
        |> form("#notification-route-form", route: %{name: "Internal", kind: "slack", url: "https://db.internal.test/"})
        |> render_submit()

      assert html =~ "private or local network"
      assert html =~ "Choose at least one."
      assert Routing.list_routes() == []
    end

    test "asks for the password first when the session has not confirmed lately", %{conn: conn} do
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/config/notifications/new")

      html =
        view
        |> form("#notification-route-form",
          route: %{name: "Editors", kind: "slack", url: @slack_url, events: ["mention"]}
        )
        |> render_submit()

      assert html =~ "reauth-modal"
      assert Routing.list_routes() == []

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      assert [_] = Routing.list_routes()
    end
  end

  describe "editing" do
    test "keeps the URL unless it is replaced", %{conn: conn, current_user: user} do
      route = create_route(user)
      {:ok, view, _html} = live(conn, "/admin/config/notifications/#{route.id}/edit")

      view |> form("#notification-route-form", route: %{name: "Desk"}) |> render_submit()
      assert %{name: "Desk"} = updated = Repo.get!(Route, route.id)
      assert Routing.url(updated) == {:ok, @slack_url}

      view |> element("[data-testid=notification-replace-url]") |> render_click()
      # An empty field, not the saved URL
      assert has_element?(view, "#route-url")
      refute has_element?(view, "#route-url[value]")

      view
      |> form("#notification-route-form", route: %{url: "https://hooks.example.com/services/T1/B1/newkey"})
      |> render_submit()

      assert Routing.url(Repo.get!(Route, route.id)) == {:ok, "https://hooks.example.com/services/T1/B1/newkey"}
    end

    test "pausing, resuming and deleting", %{conn: conn, current_user: user} do
      route = create_route(user)
      {:ok, view, _html} = live(conn, "/admin/config/notifications/#{route.id}/edit")

      view |> element("[data-testid=notification-pause]") |> render_click()
      assert %{active: false, paused_reason: :manual} = Repo.get!(Route, route.id)
      assert has_element?(view, "[data-testid=notification-route-state]", "Paused")

      view |> element("[data-testid=notification-resume]") |> render_click()
      assert %{active: true} = Repo.get!(Route, route.id)

      view |> element("[data-testid=notification-delete]") |> render_click()
      assert_redirect(view, "/admin/config/notifications")
      assert Routing.list_routes() == []
    end

    test "an id that isn't a route of this environment", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/config/notifications"}}} =
               live(conn, "/admin/config/notifications/999999/edit")

      assert {:error, {:live_redirect, %{to: "/admin/config/notifications"}}} =
               live(conn, "/admin/config/notifications/not-an-id/deliveries")
    end
  end

  describe "the delivery log" do
    test "shows what was sent, and sends a test", %{conn: conn, current_user: user} do
      receiver = WebhookReceiver.start()
      route = create_route(user, %{"url" => WebhookReceiver.url(receiver, "/services/x")})
      {:ok, view, _html} = live(conn, "/admin/config/notifications/#{route.id}/deliveries")

      view |> element("[data-testid=notification-send-test]") |> render_click()
      assert_receive {:webhook_request, %{body: body}}, 5_000
      assert body =~ "Test notification"

      assert [delivery] = Routing.list_deliveries(route)
      assert has_element?(view, "#notification-delivery-#{delivery.id}", "Delivered")

      {:ok, all, _html} = live(conn, "/admin/config/notifications/deliveries")
      assert has_element?(all, "#notification-delivery-#{delivery.id}", "Editors")
    end
  end

  describe "redelivering" do
    test "a failed delivery shows Redeliver, which sends it again", %{conn: conn, current_user: user} do
      receiver = WebhookReceiver.start()
      route = create_route(user, %{"url" => WebhookReceiver.url(receiver, "/services/x")})

      failed =
        Repo.insert!(%Brando.Notifications.Delivery{
          route_id: route.id,
          event: "failed_job",
          notification: %{
            "event" => "failed_job",
            "job" => %{"worker" => "MyApp.Sync", "attempt" => 3, "max_attempts" => 3}
          },
          state: "failed",
          error: "HTTP 500"
        })

      {:ok, view, _html} = live(conn, "/admin/config/notifications/#{route.id}/deliveries")
      assert has_element?(view, "#notification-delivery-#{failed.id} [data-testid=notification-redeliver]")

      view |> element("#notification-delivery-#{failed.id} [data-testid=notification-redeliver]") |> render_click()
      assert_receive {:webhook_request, %{body: body}}, 5_000
      assert body =~ "MyApp.Sync"

      assert [again, old] = Routing.list_deliveries(route)
      assert old.id == failed.id

      assert again.state == "succeeded"
      refute has_element?(view, "#notification-delivery-#{again.id} [data-testid=notification-redeliver]")
    end

    test "only a delivery of this environment", %{conn: conn, current_user: user} do
      route = create_route(user)
      {:ok, view, _html} = live(conn, "/admin/config/notifications/#{route.id}/deliveries")
      render_click(view, "redeliver", %{"id" => "999999"})
      assert Routing.list_deliveries(route) == []
    end
  end

  describe "the dashboard" do
    test "tells those who manage routes that one was paused after failures, linking to it", %{current_user: user} do
      route = create_route(user)
      {:ok, _} = Routing.pause(route, :failures, :system)

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      assert html =~ "dashboard-notifications-paused"
      assert html =~ "Editors"
      assert html =~ ~s(href="/admin/config/notifications/#{route.id}/edit")

      # Several: the list
      other = create_route(user, %{"name" => "Desk"})
      {:ok, _} = Routing.pause(other, :failures, :system)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      assert html =~ "2 notification routes were paused"
      assert html =~ ~s(href="/admin/config/notifications")

      editor = Factory.insert(:random_user, role: :editor)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: editor)
      refute html =~ "dashboard-notifications-paused"
    end

    test "says nothing about routes paused by hand", %{current_user: user} do
      {:ok, _} = user |> create_route() |> Routing.pause(user)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      refute html =~ "dashboard-notifications-paused"
    end
  end

  describe "with group authorization" do
    alias Brando.Authorization.{Catalog, Groups, Migration, Scope}

    test "the Notifications permission opens the routes and the Integrations row, without webhooks", %{
      conn: conn,
      current_user: owner
    } do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      manager = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

      {:ok, group} =
        Groups.create(Scope.standalone(owner), %{name: "Notifications"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:manage, :notifications).key
        ])

      {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, manager.id)
      assert Catalog.get(:manage, :notifications).key == "brando.notifications.manage"

      conn = log_in_user(conn, manager)
      {:ok, view, _html} = live(conn, "/admin/config/integrations")
      assert has_element?(view, "#integration-notifications")
      refute has_element?(view, "#integration-webhooks")

      assert {:ok, _view, _html} = live(conn, "/admin/config/notifications/new")
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/webhooks")
    end
  end

  describe "the profile" do
    test "a user chooses a daily or weekly summary instead of single emails", %{conn: conn} do
      user = Factory.insert(:random_user, avatar: nil, config: %Brando.Users.UserConfig{})
      conn = log_in_user(conn, user)
      {form, _html} = live_form(conn, "/admin/users/update/#{user.id}", "user_form")

      for value <- ~w(off daily weekly) do
        assert has_element?(form, "input[type=radio][name='user[config][notification_digest]'][value=#{value}]")
      end

      form |> form("#user_form_form", %{"user" => %{"config" => %{"notification_digest" => "weekly"}}}) |> render_submit()

      assert eventually(fn -> Repo.get!(User, user.id).config.notification_digest == :weekly end)
      assert Brando.Notifications.Digest.period(user.id) == :weekly
    end
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
