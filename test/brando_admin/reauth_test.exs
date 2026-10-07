defmodule BrandoAdmin.ReauthTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Test.SoftAuthenticator
  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityEvent
  alias Brando.Users.UserConfig
  alias Brando.Users.UserToken
  alias BrandoAdmin.Reauth
  alias BrandoIntegration.Repo

  # A session that last gave its password `minutes` ago
  defp confirmed_ago(conn, minutes) do
    token = get_session(conn, :user_token)
    at = NaiveDateTime.add(NaiveDateTime.utc_now(), -minutes * 60, :second)
    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [confirmed_at: at])
    token
  end

  defp confirmed_at(token), do: Repo.one!(from t in UserToken, where: t.token == ^token, select: t.confirmed_at)

  describe "an action of a screen" do
    test "runs at once when the session confirmed lately", %{conn: conn} do
      confirmed_ago(conn, 2)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      html = view |> element("[data-testid=passkey-add]") |> render_click()
      assert html =~ "passkey-add-modal"
      refute html =~ "reauth-modal"
    end

    test "waits for the password when the session has not", %{conn: conn} do
      token = confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      html = view |> element("[data-testid=passkey-add]") |> render_click()
      assert html =~ "reauth-modal"
      refute html =~ "passkey-add-modal"

      html = view |> form("#reauth-form", reauth: %{proof: "wrong"}) |> render_submit()
      assert html =~ ~s(data-testid="reauth-error")
      refute html =~ "passkey-add-modal"

      # Answered: the held action runs, and the session counts as confirmed
      html = view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      refute html =~ "reauth-modal"
      assert html =~ "passkey-add-modal"
      assert NaiveDateTime.diff(NaiveDateTime.utc_now(), confirmed_at(token)) < 5
    end

    test "cancelling drops the held action", %{conn: conn} do
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      view |> element("[data-testid=passkey-add]") |> render_click()
      html = render_click(view, "brando:reauth:cancel", %{})
      refute html =~ "reauth-modal"
      refute html =~ "passkey-add-modal"
    end

    test "a wrong answer counts towards the lockout", %{conn: conn, current_user: user} do
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users/security")
      view |> element("[data-testid=passkey-add]") |> render_click()
      view |> form("#reauth-form", reauth: %{proof: "wrong"}) |> render_submit()

      assert [%{details: %{"reason" => "confirm"}}] =
               Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login_failed)
    end

    test "a passkey answers too", %{conn: conn, current_user: user} do
      authenticator = SoftAuthenticator.new()
      origin = Keyword.fetch!(Passkeys.relying_party(), :origin)
      {challenge, options} = Passkeys.registration_challenge(user)

      {:ok, _, _} =
        Passkeys.register(user, "Laptop", SoftAuthenticator.register(authenticator, options, origin), challenge,
          keep_token: get_session(conn, :user_token)
        )

      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users/security")
      html = view |> element("[data-testid=passkey-add]") |> render_click()
      assert html =~ ~s(data-testid="reauth-passkey")

      view |> element("#reauth-passkey") |> render_hook("brando:reauth:passkey_options", %{})
      assert_reply(view, %{publicKey: public_key})

      result =
        SoftAuthenticator.assert(authenticator, %{challenge: public_key.challenge, rpId: public_key.rpId}, origin: origin)

      html = view |> element("#reauth-passkey") |> render_hook("brando:reauth:passkey", result)
      assert html =~ "passkey-add-modal"
    end
  end

  describe "a screen" do
    test "sends a session that has not confirmed lately to confirm, and back", %{conn: conn} do
      confirmed_ago(conn, 30)

      assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/users/sign-in-policy")
      assert to == "/admin/confirm?return_to=%2Fadmin%2Fusers%2Fsign-in-policy"

      {:ok, view, _html} = live(conn, to)
      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      assert_redirect(view, "/admin/users/sign-in-policy")

      assert {:ok, _view, _html} = live(conn, "/admin/users/sign-in-policy")
    end

    test "opens at once for a session that confirmed lately", %{conn: conn} do
      confirmed_ago(conn, 1)
      assert {:ok, _view, _html} = live(conn, "/admin/users/sign-in-policy")
    end

    test "the user form asks too", %{conn: conn} do
      confirmed_ago(conn, 30)
      user = Factory.insert(:random_user, avatar: nil, config: %UserConfig{})
      assert {:error, {:redirect, %{to: "/admin/confirm" <> _}}} = live(conn, "/admin/users/update/#{user.id}")
    end
  end

  describe "the plug" do
    test "lets a fresh session through, and sends a stale one to confirm", %{conn: conn} do
      confirmed_ago(conn, 1)
      fresh = %{conn | path_info: ["admin", "x"]} |> Reauth.require_recent_auth([])
      refute fresh.halted

      confirmed_ago(conn, 30)
      stale = %{conn | method: "GET", path_info: ["admin", "x"], query_string: ""} |> Reauth.require_recent_auth([])
      assert stale.halted
      assert redirected_to(stale) == "/admin/confirm?return_to=%2Fadmin%2Fx"
    end
  end

  test "the way back stays in the admin" do
    assert Reauth.local_path("/admin/users?x=1") == "/admin/users?x=1"
    assert Reauth.local_path("https://evil.test/admin/users") == "/admin/users"
    assert Reauth.local_path("//evil.test/admin") == "/admin"
    assert Reauth.local_path("/other") == "/admin"
    assert Reauth.local_path(nil) == "/admin"
  end

  test "a new session counts as confirmed", %{current_user: user} do
    token = Users.generate_user_session_token(user)
    assert Reauth.fresh?(token)
    refute Reauth.fresh?(nil)
  end
end
