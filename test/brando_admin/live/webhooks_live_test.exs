defmodule BrandoAdmin.Sites.WebhooksLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Users.UserToken
  alias Brando.WebhookReceiver
  alias Brando.Webhooks
  alias Brando.Webhooks.Webhook
  alias BrandoIntegration.Repo

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})
    :ok
  end

  # A session that last gave its password `minutes` ago
  defp confirmed_ago(conn, minutes) do
    token = get_session(conn, :user_token)
    at = NaiveDateTime.add(NaiveDateTime.utc_now(), -minutes * 60, :second)
    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [confirmed_at: at])
  end

  defp create_webhook(user, url \\ "https://hooks.example.com/brando") do
    {:ok, webhook, _secret} = Webhooks.create_webhook(%{"name" => "Shop cache", "url" => url}, user)
    webhook
  end

  describe "Integrations" do
    test "lists Plausible, Search Console and webhooks", %{conn: conn, current_user: user} do
      {:ok, view, html} = live(conn, "/admin/config/integrations")
      assert html =~ "Integrations"
      assert html =~ "Plausible"
      assert html =~ "Google Search Console"
      assert has_element?(view, "#integration-webhooks a[href='/admin/config/webhooks/new']")

      create_webhook(user)
      {:ok, view, _html} = live(conn, "/admin/config/integrations")
      assert has_element?(view, "#integration-webhooks", "1 webhook")
      assert has_element?(view, "#integration-webhooks a[href='/admin/config/webhooks/deliveries']")
      assert has_element?(view, "#integration-webhooks a[href='/admin/config/webhooks']")
    end

    test "is for the people who manage webhooks", %{conn: conn} do
      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

      for path <- ~w(/admin/config/integrations /admin/config/webhooks /admin/config/webhooks/new) do
        assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(log_in_user(conn, editor), path)
      end
    end
  end

  describe "creating" do
    test "shows the secret once, by push event, never in the LiveView's state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/new")

      view
      |> form("#webhook-form", webhook: %{name: "Shop cache", url: "https://hooks.example.com/brando"})
      |> render_submit()

      assert_push_event(view, "brando:webhook-secret", %{secret: secret})
      assert "whsec_" <> _ = secret

      [webhook] = Webhooks.list_webhooks()
      assert_patch(view, "/admin/config/webhooks/#{webhook.id}/edit")

      refute inspect(:sys.get_state(view.pid)) =~ secret
      refute render(view) =~ secret
      assert has_element?(view, "[data-testid=webhook-secret][hidden]")
    end

    test "chosen events and filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/new")

      view
      |> form("#webhook-form", webhook: %{events_mode: "chosen"})
      |> render_change()

      view
      |> form("#webhook-form",
        webhook: %{
          name: "Published only",
          url: "https://hooks.example.com/published",
          events_mode: "chosen",
          events: ["entry.published", "entry.unpublished"],
          entry_types: ["pages.page"]
        }
      )
      |> render_submit()

      assert [%Webhook{events: ["entry.published", "entry.unpublished"], entry_types: ["pages.page"]}] =
               Webhooks.list_webhooks()
    end

    test "explains a refused URL", %{conn: conn} do
      put_test_env(Brando.Webhooks, resolver: {Brando.WebhookTestResolver, :resolve})
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/new")

      html =
        view
        |> form("#webhook-form", webhook: %{name: "Internal", url: "https://db.internal.test/"})
        |> render_submit()

      assert html =~ "private or local network"

      html =
        view
        |> form("#webhook-form", webhook: %{name: "Plain", url: "http://hooks.example.com/"})
        |> render_change()

      assert html =~ "https://"
      assert Webhooks.list_webhooks() == []
    end

    test "asks for the password first when the session has not confirmed lately", %{conn: conn} do
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/new")

      html =
        view
        |> form("#webhook-form", webhook: %{name: "Shop cache", url: "https://hooks.example.com/brando"})
        |> render_submit()

      assert html =~ "reauth-modal"
      assert Webhooks.list_webhooks() == []

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      assert_push_event(view, "brando:webhook-secret", %{secret: "whsec_" <> _})
      assert [_] = Webhooks.list_webhooks()
    end
  end

  describe "editing" do
    test "rotating the secret, pausing, resuming and deleting", %{conn: conn, current_user: user} do
      webhook = create_webhook(user)
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/#{webhook.id}/edit")

      view |> element("[data-testid=webhook-rotate]") |> render_click()
      assert_push_event(view, "brando:webhook-secret", %{secret: secret})
      assert Webhooks.secret(Repo.get!(Webhook, webhook.id)) == {:ok, secret}
      refute inspect(:sys.get_state(view.pid)) =~ secret

      view |> element("[data-testid=webhook-pause]") |> render_click()
      assert %{active: false, paused_reason: :manual} = Repo.get!(Webhook, webhook.id)

      view |> element("[data-testid=webhook-resume]") |> render_click()
      assert %{active: true} = Repo.get!(Webhook, webhook.id)

      view |> element("[data-testid=webhook-delete]") |> render_click()
      assert_redirect(view, "/admin/config/webhooks")
      assert Webhooks.list_webhooks() == []
    end

    test "rotating asks for the password when the session has not confirmed lately", %{conn: conn, current_user: user} do
      webhook = create_webhook(user)
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/#{webhook.id}/edit")

      html = view |> element("[data-testid=webhook-rotate]") |> render_click()
      assert html =~ "reauth-modal"
      assert Repo.get!(Webhook, webhook.id).secret_ciphertext == webhook.secret_ciphertext
    end

    test "an id that isn't a webhook of this environment", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/config/webhooks"}}} =
               live(conn, "/admin/config/webhooks/999999/edit")

      assert {:error, {:live_redirect, %{to: "/admin/config/webhooks"}}} =
               live(conn, "/admin/config/webhooks/not-an-id/deliveries")
    end
  end

  describe "the delivery log" do
    test "shows deliveries, sends a test event and redelivers", %{conn: conn, current_user: user} do
      receiver = WebhookReceiver.start()
      webhook = create_webhook(user, WebhookReceiver.url(receiver))
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/#{webhook.id}/deliveries")

      view |> element("[data-testid=webhook-send-test]") |> render_click()
      assert_receive {:webhook_request, %{body: body}}, 5_000
      assert body =~ "webhook.test"

      assert [delivery] = Webhooks.list_deliveries(webhook)
      assert has_element?(view, "#delivery-#{delivery.id}", "200")

      view |> element("#delivery-#{delivery.id} [data-testid=webhook-redeliver]") |> render_click()
      assert_receive {:webhook_request, _}, 5_000
      assert length(Webhooks.list_deliveries(webhook)) == 2

      {:ok, all, _html} = live(conn, "/admin/config/webhooks/deliveries")
      assert has_element?(all, "#delivery-#{delivery.id}", "Shop cache")
    end

    test "redelivery checks the delivery belongs to this environment", %{conn: conn, current_user: user} do
      webhook = create_webhook(user)
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/#{webhook.id}/deliveries")
      render_click(view, "redeliver", %{"id" => "999999"})
      assert length(Webhooks.list_deliveries(webhook)) == 0
    end
  end

  describe "with group authorization" do
    alias Brando.Authorization.{Catalog, Groups, Migration, Scope}

    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      manager = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

      {:ok, group} =
        Groups.create(Scope.standalone(owner), %{name: "Integrations"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:manage, :webhooks).key
        ])

      {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, manager.id)

      {:ok, page} =
        Brando.Pages.create_page(
          %{title: "Secret draft", uri: "secret-draft", language: "en", template: "default.html", status: :draft},
          :system
        )

      %{manager: manager, page: page}
    end

    test "a manager who may not read a content type sees its entries by type and id only", c do
      webhook = create_webhook(c.current_user)

      Repo.insert!(%Brando.Webhooks.Delivery{
        webhook_id: webhook.id,
        delivery_id: Ecto.UUID.generate(),
        event: "entry.created",
        entry_schema: to_string(Brando.Pages.Page),
        entry_type: "pages.page",
        entry_id: c.page.id,
        payload: %{},
        state: "succeeded"
      })

      {:ok, _view, html} = live(log_in_user(c.conn, c.manager), "/admin/config/webhooks/#{webhook.id}/deliveries")
      refute html =~ "Secret draft"
      assert html =~ "Pages ##{c.page.id}"

      # Someone who may read pages sees the title, linked
      {:ok, _view, html} = live(c.conn, "/admin/config/webhooks/#{webhook.id}/deliveries")
      assert html =~ "Secret draft"
    end

    test "the content-type filter offers readable types, and keeps the others chosen", c do
      {:ok, webhook, _} =
        Webhooks.create_webhook(
          %{"name" => "Pages", "url" => "https://hooks.example.com/pages", "entry_types" => ["pages.page"]},
          c.current_user
        )

      {:ok, view, _html} = live(log_in_user(c.conn, c.manager), "/admin/config/webhooks/#{webhook.id}/edit")
      refute has_element?(view, ~s(input[type=checkbox][name="webhook[entry_types][]"][value="pages.page"]))
      assert has_element?(view, ~s(input[type=hidden][name="webhook[entry_types][]"][value="pages.page"]))

      view |> form("#webhook-form", webhook: %{name: "Renamed"}) |> render_submit()
      assert %{name: "Renamed", entry_types: ["pages.page"]} = Repo.get!(Webhook, webhook.id)
    end
  end

  describe "the URL of a saved webhook" do
    test "shows its scheme and host only, until it is replaced", %{conn: conn, current_user: user} do
      webhook = create_webhook(user, "https://hooks.example.com/build/s3cr3t-key?token=abc")
      {:ok, view, html} = live(conn, "/admin/config/webhooks/#{webhook.id}/edit")

      refute html =~ "s3cr3t-key"
      refute html =~ "token=abc"
      assert render(element(view, "[data-testid=webhook-url-masked]")) =~ "https://hooks.example.com/••••••"
      refute has_element?(view, "#webhook-url")

      # Saving other fields keeps the URL
      view |> form("#webhook-form", webhook: %{name: "Build"}) |> render_submit()

      assert %{name: "Build", url: "https://hooks.example.com/build/s3cr3t-key?token=abc"} =
               Repo.get!(Webhook, webhook.id)

      html = view |> element("[data-testid=webhook-replace-url]") |> render_click()
      refute html =~ "s3cr3t-key"
      assert has_element?(view, "#webhook-url[value='']")

      view |> form("#webhook-form", webhook: %{url: "https://hooks.example.com/new"}) |> render_submit()
      assert %{url: "https://hooks.example.com/new"} = Repo.get!(Webhook, webhook.id)
    end

    test "changing the form while the new URL is still empty keeps the screen and the URL", %{
      conn: conn,
      current_user: user
    } do
      webhook = create_webhook(user, "https://hooks.example.com/build/key")
      {:ok, view, _html} = live(conn, "/admin/config/webhooks/#{webhook.id}/edit")
      view |> element("[data-testid=webhook-replace-url]") |> render_click()

      html =
        view
        |> form("#webhook-form", webhook: %{url: "", languages: ["en"]})
        |> render_change()

      assert Process.alive?(view.pid)
      assert html =~ "webhook-form"

      # An emptied name is an error to show, too
      view |> form("#webhook-form", webhook: %{name: "", url: ""}) |> render_change()
      assert Process.alive?(view.pid)

      assert %{url: "https://hooks.example.com/build/key", name: "Shop cache"} = Repo.get!(Webhook, webhook.id)
    end
  end

  describe "the dashboard" do
    test "warns the people who manage webhooks when one was paused after failures", %{current_user: user} do
      webhook = create_webhook(user)
      {:ok, _} = Webhooks.pause(webhook, :failures, :system)

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      assert html =~ "dashboard-webhooks-paused"
      assert html =~ "Shop cache"
      assert html =~ ~s(href="/admin/config/webhooks/#{webhook.id}/edit")

      editor = Factory.insert(:random_user, role: :editor)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: editor)
      refute html =~ "dashboard-webhooks-paused"
    end
  end
end
