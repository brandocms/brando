defmodule BrandoAdmin.PasskeyLoginTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Test.SoftAuthenticator
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityEvent
  alias Brando.Users.Throttle
  alias Brando.Users.UserConfig
  alias Brando.Users.UserToken

  @remember_me "_brando_user_remember_me"

  defp anonymous do
    %{Phoenix.ConnTest.build_conn() | remote_ip: {10, 98, :rand.uniform(250), :rand.uniform(250)}}
  end

  defp next(conn), do: conn |> recycle() |> Map.put(:remote_ip, conn.remote_ip)

  defp origin, do: Keyword.fetch!(Passkeys.relying_party(), :origin)

  setup do
    user =
      Factory.insert(:random_user, role: :editor, config: %UserConfig{reset_password_on_first_login: false})

    authenticator = SoftAuthenticator.new()
    {challenge, options} = Passkeys.registration_challenge(user)

    {:ok, _passkey, _codes} =
      Passkeys.register(user, "Laptop", SoftAuthenticator.register(authenticator, options, origin()), challenge)

    {:ok, user: user, authenticator: authenticator}
  end

  # The hook's two requests: the options, then the answer
  defp passkey_login(conn, mode, authenticator, extra \\ %{}) do
    conn = post(conn, "/admin/login/passkey/options", %{"mode" => mode})
    %{"publicKey" => public_key} = json_response(conn, 200)
    options = %{challenge: public_key["challenge"], rpId: public_key["rpId"]}
    result = SoftAuthenticator.assert(authenticator, options, origin: origin())
    conn |> next() |> post("/admin/login/passkey", Map.merge(%{"passkey" => result}, extra))
  end

  defp sessions(user),
    do: Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")

  test "a passkey alone logs in, and remembers when asked", %{user: user, authenticator: authenticator} do
    conn = passkey_login(anonymous(), "passwordless", authenticator, %{"remember_me" => "true"})

    assert redirected_to(conn) == "/admin"
    assert get_session(conn, :user_token)
    assert conn.resp_cookies[@remember_me]
    assert [%{ip: "10.98." <> _}] = sessions(user)

    assert [%{details: %{"method" => "passkey"}}] =
             Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login)
  end

  test "an answer works once, even with an old copy of the session", %{authenticator: authenticator} do
    conn = post(anonymous(), "/admin/login/passkey/options", %{"mode" => "passwordless"})
    %{"publicKey" => public_key} = json_response(conn, 200)
    options = %{challenge: public_key["challenge"], rpId: public_key["rpId"]}
    result = SoftAuthenticator.assert(authenticator, options, origin: origin())

    first = conn |> next() |> post("/admin/login/passkey", %{"passkey" => result})
    assert redirected_to(first) == "/admin"

    # The cookie from before the login still carries the challenge
    replay = conn |> next() |> post("/admin/login/passkey", %{"passkey" => result})
    assert redirected_to(replay) == "/admin/login"
    refute get_session(replay, :user_token)
  end

  test "an unknown passkey does not log in" do
    conn = passkey_login(anonymous(), "passwordless", SoftAuthenticator.new())
    assert redirected_to(conn) == "/admin/login"
    refute get_session(conn, :user_token)
  end

  test "a locked account does not log in with a passkey", %{user: user, authenticator: authenticator} do
    for _ <- 1..Throttle.config()[:lockout_after], do: Throttle.failed(user, :password)

    conn = passkey_login(anonymous(), "passwordless", authenticator)
    assert redirected_to(conn) == "/admin/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
    assert sessions(user) == []
  end

  test "a passkey is the second step after the password", %{user: user, authenticator: authenticator} do
    conn = post(anonymous(), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})
    assert redirected_to(conn) == "/admin/login/two-factor"
    assert sessions(user) == []

    conn = passkey_login(next(conn), "second_factor", authenticator)
    assert redirected_to(conn) == "/admin"
    assert [_] = sessions(user)
  end

  test "the second step refuses another user's passkey", %{user: user} do
    other = Factory.insert(:random_user, role: :editor, config: %UserConfig{reset_password_on_first_login: false})
    other_authenticator = SoftAuthenticator.new()
    {challenge, options} = Passkeys.registration_challenge(other)

    {:ok, _, _} =
      Passkeys.register(other, "Theirs", SoftAuthenticator.register(other_authenticator, options, origin()), challenge)

    conn = post(anonymous(), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})
    conn = passkey_login(next(conn), "second_factor", other_authenticator)

    assert redirected_to(conn) == "/admin/login/two-factor"
    assert sessions(user) == []
  end

  test "second-step options need a waiting sign-in" do
    conn = post(anonymous(), "/admin/login/passkey/options", %{"mode" => "second_factor"})
    assert json_response(conn, 422)
  end
end
