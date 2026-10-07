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
      {:ok, challenge, options} = Passkeys.start_registration(user, "admin")

      {:ok, _, _} =
        Passkeys.register(user, "Laptop", SoftAuthenticator.register(authenticator, options, origin), challenge,
          keep_id: Users.token_id(get_session(conn, :user_token))
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

  describe "a screen that asks first, once open" do
    # The review's probe: open while confirmed, let the confirmation age, then
    # send a sensitive event over the open socket.
    test "holds an event when the confirmation has run out, and runs it once answered", %{conn: conn} do
      user = Factory.insert(:random_user, role: :editor, avatar: nil, config: %UserConfig{})
      secret = Brando.Users.TwoFactor.new_secret()
      {:ok, _} = Brando.Users.TwoFactor.enable(user, secret, Brando.Users.TwoFactor.current_code(secret), proof: "admin")

      confirmed_ago(conn, 1)
      {:ok, view, _html} = live(conn, "/admin/users/update/#{user.id}")
      confirmed_ago(conn, 60)

      html = render_click(view, "reset_two_factor", %{})
      assert html =~ "reauth-modal"
      assert Brando.Users.TwoFactor.enabled?(user)

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      refute Brando.Users.TwoFactor.enabled?(user)
    end

    test "is left for the confirm page when the confirmation runs out", %{conn: conn} do
      token = confirmed_ago(conn, 1)
      {:ok, view, _html} = live(conn, "/admin/users/sign-in-policy")
      confirmed_ago(conn, 60)

      send(view.pid, {Reauth, :check, Users.token_id(token)})
      assert_redirect(view, "/admin/confirm?return_to=%2Fadmin%2Fusers%2Fsign-in-policy")
    end

    test "is not left while the confirmation holds", %{conn: conn} do
      token = confirmed_ago(conn, 1)
      {:ok, view, _html} = live(conn, "/admin/users/sign-in-policy")

      send(view.pid, {Reauth, :check, Users.token_id(token)})
      assert render(view) =~ "sign-in-policy-form"
    end
  end

  describe "sensitive actions that ask again" do
    @guarded [
      {BrandoAdmin.Sites.SiteLive, ~w(delete suspend archive grant revoke)},
      {BrandoAdmin.Sites.PublishingLive, ~w(save_deploy_config deploy rollback request_build schedule_build)},
      {BrandoAdmin.Sites.EnvironmentLive,
       ~w(delete_environment queue_set_live schedule_set_live prune_archives queue_copy schedule_copy)},
      {BrandoAdmin.Users.UserListLive, ~w(disable_user enable_user confirm_transfer_delete)},
      {BrandoAdmin.Users.GroupsLive, ~w(save delete add_member remove_member)},
      {BrandoAdmin.Users.UserSecurityLive, ~w(open_setup new_passkey remove_passkey revoke_session revoke_other_sessions)}
    ]

    for {module, events} <- @guarded do
      test "#{inspect(module)} guards #{Enum.join(events, ", ")}" do
        guarded =
          for %{id: {Reauth, opts}} <- unquote(module).__live__()[:lifecycle].mount,
              is_list(opts),
              event <- opts[:events],
              do: event

        assert unquote(events) -- guarded == []
      end
    end

    for module <- [BrandoAdmin.Users.UserFormLive, BrandoAdmin.Users.SignInPolicyLive] do
      test "#{inspect(module)} asks for the whole screen" do
        assert Enum.any?(unquote(module).__live__()[:lifecycle].mount, &match?(%{id: {Reauth, :screen}}, &1))
      end
    end

    test "disabling a user waits for the password", %{conn: conn} do
      target = Factory.insert(:random_user, role: :editor, config: %UserConfig{})
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users")

      html = render_click(view, "disable_user", %{"id" => to_string(target.id)})
      assert html =~ "reauth-modal"
      assert Repo.get!(Brando.Users.User, target.id).active

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      refute Repo.get!(Brando.Users.User, target.id).active
    end

    test "logging out another session waits for the password", %{conn: conn, current_user: user} do
      other = Users.generate_user_session_token(user)
      confirmed_ago(conn, 30)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      html = view |> element("[data-testid=session-revoke]") |> render_click()
      assert html =~ "reauth-modal"
      assert Users.get_user_by_session_token(other)

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      refute Users.get_user_by_session_token(other)
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
