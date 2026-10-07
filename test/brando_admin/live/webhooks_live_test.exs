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

  describe "the dashboard" do
    test "warns the people who manage webhooks when one was paused after failures", %{current_user: user} do
      webhook = create_webhook(user)
      {:ok, _} = Webhooks.pause(webhook, :failures, :system)

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      assert html =~ "dashboard-webhooks-paused"
      assert html =~ "Shop cache"

      editor = Factory.insert(:random_user, role: :editor)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: editor)
      refute html =~ "dashboard-webhooks-paused"
    end
  end
end
