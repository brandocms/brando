defmodule BrandoAdmin.ActivitySecurityLiveTest do
  # Configuration → Activity → Security: every user's sign-in security events,
  # for those who may see them, enforced on the server.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Users
  alias Brando.Users.SecurityEvent
  alias Brando.Users.SecurityLog
  alias Brando.Users.TwoFactor

  @path "/admin/config/activity?view=security"
  @chrome "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/129.0 Safari/537.36"

  defp user(attrs),
    do: Factory.insert(:random_user, Keyword.merge([role: :editor, config: %Brando.Users.UserConfig{}], attrs))

  defp record(action, user, opts \\ []) do
    :ok =
      SecurityLog.record(
        action,
        user,
        Keyword.merge([meta: %{ip: "203.0.113.9", user_agent: @chrome}], opts)
      )
  end

  describe "without group authorization" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
    end

    test "an administrator sees every user's events, with the person, the IP and the browser", %{conn: conn} do
      ola = user(name: "Ola Nordmann")
      kari = user(name: "Kari Nordmann")
      record(:login, ola, details: %{"method" => "totp"})
      record(:login_failed, kari, details: %{"reason" => "password"})
      record(:two_factor_reset, kari, actor: ola)

      {:ok, view, _html} = live(conn, @path)

      assert has_element?(view, ".activity-views [aria-current=page]", "Security")
      assert has_element?(view, "[data-testid=security-log]")
      assert has_element?(view, ".security-log-row .activity-person-name", "Ola Nordmann")
      assert has_element?(view, ".security-log-row .activity-person-name", "Kari Nordmann")
      assert has_element?(view, ".security-log-row .activity-action", "Logged in with an authenticator code")
      assert has_element?(view, ".security-log-row .activity-action.is-negative", "Wrong password")
      assert has_element?(view, ".security-log-row .activity-detail", "by Ola Nordmann")
      assert has_element?(view, ".security-log-row .security-log-ip", "203.0.113.9")
      assert has_element?(view, ".security-log-row .security-log-origin", "Chrome on macOS")
      assert has_element?(view, ".activity-count", "3 events")

      # The content log stays where it was, without the security events.
      {:ok, view, _html} = live(conn, "/admin/config/activity")
      assert has_element?(view, ".activity-views [aria-current=page]", "Content")
      refute has_element?(view, "[data-testid=security-log]")
    end

    test "an editor can't open Activity at all", %{conn: conn} do
      conn = log_in_user(conn, user(role: :editor))
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, @path)
    end

    test "with several sites, only superusers may see it", %{current_user: superuser} do
      admin = user(role: :admin)
      assert SecurityLog.readable_by?(admin)
      refute SecurityLog.readable_by?(user(role: :editor))

      put_test_env(:tenancy_mode, :multi)
      refute SecurityLog.readable_by?(admin)
      assert SecurityLog.readable_by?(superuser)
    end

    test "filters by person and by event, in the URL", %{conn: conn} do
      ola = user(name: "Ola Nordmann")
      kari = user(name: "Kari Nordmann")
      record(:login, ola)
      record(:password_changed, ola)
      record(:login, kari)

      {:ok, view, _html} = live(conn, @path)
      assert has_element?(view, ".activity-count", "3 events")

      view |> form("#security-filters", %{user: to_string(ola.id)}) |> render_change()
      assert_patch(view, "/admin/config/activity?user=#{ola.id}&view=security")
      assert has_element?(view, ".activity-count", "2 events")
      refute has_element?(view, ".activity-person-name", "Kari Nordmann")

      view |> form("#security-filters", %{user: to_string(ola.id), event: "password_changed"}) |> render_change()
      assert_patch(view, "/admin/config/activity?event=password_changed&user=#{ola.id}&view=security")
      assert has_element?(view, ".activity-count", "1 event")
      assert has_element?(view, ".security-log-row .activity-action", "Password changed")
      refute has_element?(view, ".security-log-row .activity-action", "Logged in")

      # A value that is no event type is ignored rather than trusted.
      {:ok, view, _html} = live(conn, @path <> "&event=drop_table")
      assert has_element?(view, ".activity-count", "3 events")
    end

    test "pages through older events", %{conn: conn} do
      ola = user(name: "Ola Nordmann")
      for _ <- 1..55, do: record(:login, ola)

      {:ok, view, _html} = live(conn, @path)
      assert has_element?(view, ".activity-count", "55 events")
      assert view |> element("[data-testid=security-log]") |> render() |> count_rows() == 50
      assert has_element?(view, ".activity-more", "Showing 50 of 55")

      view |> element(".activity-more button") |> render_click()
      assert view |> element("[data-testid=security-log]") |> render() |> count_rows() == 55
      refute has_element?(view, ".activity-more")
    end

    test "events older than the period are left out", %{conn: conn} do
      ola = user(name: "Ola Nordmann")
      record(:login, ola)
      record(:locked, ola)

      old = DateTime.add(DateTime.utc_now(), -20 * 86_400, :second)
      Repo.update_all(from(e in SecurityEvent, where: e.action == :locked), set: [inserted_at: old])

      {:ok, view, _html} = live(conn, @path)
      assert has_element?(view, ".activity-count", "1 event")

      {:ok, view, _html} = live(conn, @path <> "&period=30")
      assert has_element?(view, ".activity-count", "2 events")
    end

    test "shows no codes, secrets or tokens", %{conn: conn} do
      ola = user(name: "Ola Nordmann")
      secret = TwoFactor.new_secret()
      {:ok, codes} = TwoFactor.enable(ola, secret, TwoFactor.current_code(secret), proof: "admin")
      session_token = Users.generate_user_session_token(ola)
      record(:login, ola, details: %{"method" => "totp", "token" => "tok-secret-value", "code" => "123456"})

      {:ok, _view, html} = live(conn, @path)

      assert html =~ "Two-factor authentication turned on"
      refute html =~ TwoFactor.display_secret(secret)
      refute html =~ Base.encode32(secret, padding: false)
      refute html =~ Base.url_encode64(session_token, padding: false)
      refute html =~ "tok-secret-value"
      refute html =~ "123456"
      for code <- codes, do: refute(html =~ code)
    end
  end

  describe "with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      owner = user(role: :superuser)
      {:ok, _} = Migration.run()
      %{scope: Scope.standalone(owner)}
    end

    defp member(c, keys) do
      user = user(role: :user)
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      {user, log_in_user(build_conn(), user)}
    end

    test "the Activity permission alone shows the content log, not the security log", c do
      record(:login, user(name: "Ola Nordmann"))
      {_user, conn} = member(c, ["brando.admin.access", "brando.activity.read"])

      {:ok, view, html} = live(conn, @path)
      refute has_element?(view, ".activity-views")
      refute has_element?(view, "[data-testid=security-log]")
      refute html =~ "Ola Nordmann"

      # Asking for it with an event does not reach it either.
      assert render_hook(view, "load_more", %{}) =~ "activity-workspace"
      refute render(view) =~ "Ola Nordmann"
    end

    test "brando.security_log.read shows the security log", c do
      record(:login, user(name: "Ola Nordmann"))
      {_user, conn} = member(c, ["brando.admin.access", "brando.activity.read", "brando.security_log.read"])

      {:ok, view, _html} = live(conn, @path)
      assert has_element?(view, ".activity-views [aria-current=page]", "Security")
      assert has_element?(view, ".security-log-row .activity-person-name", "Ola Nordmann")
    end

    test "without the Activity permission, the page stays closed", c do
      {_user, conn} = member(c, ["brando.admin.access", "brando.security_log.read"])
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, @path)
    end

    test "the admin preset grants it; the editor preset does not" do
      assert "brando.security_log.read" in Catalog.preset_permissions(:admin, :standalone)
      assert "brando.security_log.read" in Catalog.preset_permissions(:admin, :site)
      refute "brando.security_log.read" in Catalog.preset_permissions(:editor, :standalone)
    end
  end

  defp count_rows(html), do: html |> Floki.parse_fragment!() |> Floki.find(".security-log-row") |> length()
end
