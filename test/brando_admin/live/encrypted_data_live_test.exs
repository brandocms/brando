defmodule BrandoAdmin.EncryptedDataLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Migration
  alias Brando.Crypto.Marker
  alias Brando.Factory
  alias Brando.Test.ForeignSecret
  alias Brando.Users.Security
  alias Brando.Users.UserConfig
  alias BrandoAdmin.Components.Dashboard

  # The dashboard's LiveView is the application's: this one stands in for it
  defmodule DashboardHost do
    use Phoenix.LiveView

    def mount(_params, %{"user_id" => user_id}, socket) do
      {:ok, user} = Brando.Users.get_user(user_id)
      {:ok, Phoenix.Component.assign(socket, :current_user, user)}
    end

    def render(assigns) do
      ~H"""
      <.live_component module={BrandoAdmin.Components.Dashboard} id="dashboard" current_user={@current_user} />
      """
    end
  end

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp user(role), do: Factory.insert(:random_user, role: role, config: %UserConfig{})

  defp log_in(user), do: Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), user)

  defp foreign_marker!(host),
    do: Repo.insert!(%Marker{id: 1, value: ForeignSecret.encrypt("brando", "brando.crypto_marker"), host: host})

  defp moved!(paused) do
    Repo.insert!(%Marker{
      id: 1,
      value: Brando.Crypto.encrypt("brando", "brando.crypto_marker"),
      host: Marker.host(),
      moved_from: "prod.example.com",
      moved_at: DateTime.utc_now(),
      moved_key: "ours",
      paused: paused
    })
  end

  defp confirmed_long_ago(conn) do
    token = get_session(conn, :user_token)
    at = NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 60, :second)
    Repo.update_all(from(t in Brando.Users.UserToken, where: t.token == ^token), set: [confirmed_at: at])
    conn
  end

  describe "the dashboard's notice of a move" do
    test "names where the database came from and links what was paused here, for those who manage them", %{
      current_user: admin
    } do
      hook = ForeignSecret.webhook!(nil, true, name: "Deploy hook")

      moved!([
        %{"prefix" => nil, "kind" => "webhook", "count" => 3, "named" => [%{"id" => hook.id, "name" => "Deploy hook"}]},
        %{"prefix" => "tenant_other_production", "kind" => "notification_route", "count" => 2, "named" => []}
      ])

      html = render_component(Dashboard, id: "dashboard", current_user: admin)
      assert html =~ "dashboard-database-moved"
      assert html =~ "prod.example.com"
      assert html =~ ~s(href="/admin/config/webhooks/#{hook.id}/edit")
      # Two more than named here
      assert html =~ ~s(href="/admin/config/webhooks")

      html = render_component(Dashboard, id: "dashboard", current_user: user(:editor))
      refute html =~ "dashboard-database-moved"
    end

    test "is dismissed for everyone", %{conn: conn, current_user: admin} do
      moved!([%{"prefix" => nil, "kind" => "webhook", "count" => 1, "named" => []}])
      {:ok, view, _html} = live_isolated(conn, DashboardHost, session: %{"user_id" => admin.id})

      assert has_element?(view, "[data-testid=dashboard-database-moved]")
      view |> element("[data-testid=dashboard-database-moved] button") |> render_click()

      refute has_element?(view, "[data-testid=dashboard-database-moved]")
      assert %Marker{paused_dismissed_at: %DateTime{}} = Repo.one(Marker)
      assert is_nil(Marker.move_notice())
    end
  end

  describe "the dashboard's notice of another secret" do
    test "is shown to superusers only, with a link to Encrypted data", %{current_user: superuser} do
      foreign_marker!(Marker.host())
      ForeignSecret.two_factor!(user(:editor), false)

      html = render_component(Dashboard, id: "dashboard", current_user: superuser)
      assert html =~ "dashboard-encrypted-data"
      assert html =~ ~s(href="/admin/config/encrypted-data")

      for role <- [:admin, :editor] do
        refute render_component(Dashboard, id: "dashboard", current_user: user(role)) =~ "dashboard-encrypted-data"
      end
    end

    test "is worked out once when the dashboard mounts, not on each update", %{conn: conn, current_user: superuser} do
      foreign_marker!(Marker.host())
      ForeignSecret.two_factor!(user(:editor), false)
      {:ok, view, _html} = live_isolated(conn, DashboardHost, session: %{"user_id" => superuser.id})
      assert has_element?(view, "[data-testid=dashboard-encrypted-data]")

      # The audit reads every two-factor secret
      parent = self()
      handler = "dashboard-audit-#{inspect(parent)}"

      :telemetry.attach(
        handler,
        Brando.repo().config()[:telemetry_prefix] ++ [:query],
        fn _event, _measurements, %{source: source}, _config ->
          if source == "users_security", do: send(parent, :audit_read)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      Phoenix.LiveView.send_update(view.pid, Dashboard, id: "dashboard", current_user: superuser)
      assert has_element?(view, "[data-testid=dashboard-encrypted-data]")
      refute_received :audit_read
    end

    test "is left out when the audit fails, and the dashboard renders", %{current_user: superuser} do
      ForeignSecret.two_factor!(user(:editor), false)
      # Without a marker the audit decrypts each secret, and an unusable secret raises
      put_test_env(Brando.Crypto, secret: "too short")

      {html, log} =
        ExUnit.CaptureLog.with_log(fn -> render_component(Dashboard, id: "dashboard", current_user: superuser) end)

      refute html =~ "dashboard-encrypted-data"
      assert log =~ "Could not check the encrypted data"
    end

    test "is not there when everything is readable", %{current_user: superuser} do
      ForeignSecret.two_factor!(user(:editor), true)
      refute render_component(Dashboard, id: "dashboard", current_user: superuser) =~ "dashboard-encrypted-data"
    end
  end

  describe "Encrypted data" do
    test "lists what cannot be read and forgets it after the confirm dialog and the password", %{conn: conn} do
      other = user(:editor)
      ForeignSecret.two_factor!(other, false)
      ForeignSecret.webhook!(nil, false)
      foreign_marker!("prod.example.com")
      conn = confirmed_long_ago(conn)

      {:ok, view, _html} = live(conn, "/admin/config/encrypted-data")

      assert has_element?(view, "[data-testid=encrypted-data-items] li", "prod.example.com") == false
      assert view |> element("[data-testid=encrypted-data-items]") |> render() =~ "<li>"
      button = element(view, "[data-testid=encrypted-data-forget]")
      # The dialog shows the counts and why
      assert render(button) =~ "data-confirm-title"
      assert render(button) =~ "prod.example.com"

      assert render_click(button) =~ "reauth-modal"
      assert Repo.get_by(Security, user_id: other.id).totp_secret

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()

      assert has_element?(view, "[data-testid=encrypted-data-forgotten]")
      assert is_nil(Repo.get_by(Security, user_id: other.id).totp_secret)
      assert Marker.state().key == :ours
      refute has_element?(view, "[data-testid=encrypted-data-forget]")
    end

    test "the superuser who runs it keeps their session", %{conn: conn, current_user: superuser} do
      ForeignSecret.two_factor!(superuser, false)
      {:ok, view, _html} = live(conn, "/admin/config/encrypted-data")

      view |> element("[data-testid=encrypted-data-forget]") |> render_click()

      assert is_nil(Repo.get_by(Security, user_id: superuser.id).totp_secret)
      assert Brando.Users.get_user_by_session_token(get_session(conn, :user_token))
    end

    for mode <- [:legacy, :groups] do
      @tag authorization: mode
      test "is for superusers only, #{mode} authorization", %{authorization: mode} do
        admin = user(:admin)
        superuser = user(:superuser)
        ForeignSecret.two_factor!(user(:editor), false)

        # The groups the roles map to
        if mode == :groups do
          put_test_env(:authorization_mode, :groups)
          {:ok, _} = Migration.run()
        end

        assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(log_in(admin), "/admin/config/encrypted-data")
        assert {:error, :forbidden} = Brando.Crypto.Audit.forget(admin)

        assert {:ok, view, _html} = live(log_in(superuser), "/admin/config/encrypted-data")
        assert has_element?(view, "[data-testid=encrypted-data-forget]")
      end
    end
  end
end
