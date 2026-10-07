defmodule BrandoAdmin.TwoFactorLoginTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.Security
  alias Brando.Users.SecurityEvent
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.Throttle
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserConfig
  alias Brando.Users.UserToken

  @remember_me "_brando_user_remember_me"

  # Each test signs in from its own address, so the per-IP limits of the
  # tests running alongside do not add up.
  defp anonymous do
    ip = {10, 99, :rand.uniform(250), :rand.uniform(250)}
    %{Phoenix.ConnTest.build_conn() | remote_ip: ip}
  end

  defp user(attrs \\ []),
    do:
      Factory.insert(
        :random_user,
        Keyword.merge([role: :editor, config: %UserConfig{reset_password_on_first_login: false}], attrs)
      )

  defp enable(user) do
    secret = TwoFactor.new_secret()
    {:ok, codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret), proof: "admin")
    Repo.update_all(from(s in Security, where: s.user_id == ^user.id), set: [totp_last_step: nil])
    {secret, codes}
  end

  defp log_in(conn, user, extra \\ %{}) do
    post(conn, "/admin/login", %{"user" => Map.merge(%{"email" => user.email, "password" => "admin"}, extra)})
  end

  defp session_tokens(user) do
    Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session", select: t.token)
  end

  defp next(conn), do: conn |> recycle() |> Map.put(:remote_ip, conn.remote_ip)

  describe "without two-factor authentication" do
    test "the password logs the user in" do
      user = user()
      conn = log_in(anonymous(), user)

      assert redirected_to(conn) == "/admin"
      assert get_session(conn, :user_token)
      assert [_] = session_tokens(user)
    end
  end

  describe "with two-factor authentication" do
    setup do
      user = user()
      {secret, codes} = enable(user)
      {:ok, user: user, secret: secret, codes: codes}
    end

    test "the password alone gives no session, and remember-me waits for the code",
         %{user: user, secret: secret} do
      conn = log_in(anonymous(), user, %{"remember_me" => "true"})

      assert redirected_to(conn) == "/admin/login/two-factor"
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_login_token)
      refute conn.resp_cookies[@remember_me]
      assert session_tokens(user) == []

      # The pending token is not a session
      assert is_nil(Users.get_user_by_session_token(get_session(conn, :pending_login_token)))

      # Nothing behind the login opens with it
      admin = conn |> next() |> get("/admin/users")
      assert redirected_to(admin) == "/admin/login"

      conn =
        conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => TwoFactor.current_code(secret)}})

      assert redirected_to(conn) == "/admin"
      assert get_session(conn, :user_token)
      refute get_session(conn, :pending_login_token)
      assert conn.resp_cookies[@remember_me]
      assert [_] = session_tokens(user)

      assert [%{details: %{"method" => "totp"}}] =
               Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login)
    end

    test "the code screen asks in the user's language", %{user: user} do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [language: "no"])
      conn = log_in(anonymous(), user)

      {:ok, _view, html} = live(next(conn), "/admin/login/two-factor")
      assert html =~ "two_factor_form"
      assert html =~ user.email
    end

    test "a remember-me cookie holding the waiting sign-in's token is no way around it", %{user: user} do
      conn = log_in(anonymous(), user, %{"remember_me" => "true"})
      pending = get_session(conn, :pending_login_token)

      # Signed as the real cookie is, from a fresh browser
      forged =
        %{anonymous() | secret_key_base: Brando.endpoint().config(:secret_key_base)}
        |> put_resp_cookie(@remember_me, pending, sign: true)
        |> recycle()
        |> get("/admin/users")

      assert redirected_to(forged) == "/admin/login"
    end

    test "a recovery code works once in place of the app's code", %{user: user, codes: [code | _]} do
      conn = log_in(anonymous(), user)
      conn = conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => code}})
      assert redirected_to(conn) == "/admin"

      conn = log_in(anonymous(), user)
      conn = conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => code}})
      assert redirected_to(conn) == "/admin/login/two-factor"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not work"
    end

    test "a code works once", %{user: user, secret: secret} do
      code = TwoFactor.current_code(secret)
      conn = log_in(anonymous(), user)

      assert redirected_to(conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => code}})) ==
               "/admin"

      conn = log_in(anonymous(), user)

      assert redirected_to(conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => code}})) ==
               "/admin/login/two-factor"
    end

    test "wrong codes lock the account, and end the waiting sign-in", %{user: user, secret: secret} do
      conn = log_in(anonymous(), user)

      conn =
        Enum.reduce(1..(Throttle.config()[:lockout_after] - 1), conn, fn _, conn ->
          conn = conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => "000000"}})
          assert redirected_to(conn) == "/admin/login/two-factor"
          conn
        end)

      conn = conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => "000000"}})
      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert Throttle.locked_until(user)

      # Locked: the right password and code do not get in
      conn = log_in(anonymous(), user)
      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"

      Throttle.clear(user)
      conn = log_in(anonymous(), user)

      conn =
        conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => TwoFactor.current_code(secret)}})

      assert redirected_to(conn) == "/admin"
    end

    test "a waiting sign-in expires", %{user: user, secret: secret} do
      conn = log_in(anonymous(), user)

      Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "pending_2fa"),
        set: [inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60)]
      )

      conn =
        conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => TwoFactor.current_code(secret)}})

      assert redirected_to(conn) == "/admin/login"
      refute get_session(conn, :user_token)
    end

    test "the code screen sends a visitor without a waiting sign-in back to log in" do
      assert {:error, {:live_redirect, %{to: "/admin/login"}}} = live(anonymous(), "/admin/login/two-factor")
    end
  end

  describe "wrong passwords" do
    test "lock the account, and the answer then is the same for an unknown address" do
      user = user()
      lockout_after = Throttle.config()[:lockout_after]

      for _ <- 1..(lockout_after - 1) do
        conn = log_in(anonymous(), user, %{"password" => "wrong"})
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      end

      known = log_in(anonymous(), user, %{"password" => "wrong"})
      assert Throttle.locked_until(user)

      unknown_email = "nobody-#{System.unique_integer([:positive])}@example.test"

      unknown =
        Enum.reduce(1..lockout_after, nil, fn _, _ ->
          post(anonymous(), "/admin/login", %{"user" => %{"email" => unknown_email, "password" => "wrong"}})
        end)

      assert Phoenix.Flash.get(known.assigns.flash, :error) == Phoenix.Flash.get(unknown.assigns.flash, :error)
      assert Phoenix.Flash.get(known.assigns.flash, :error) =~ "Too many attempts"
    end

    test "too many from one address are refused before the password is checked" do
      user = user()
      conn = anonymous()

      for _ <- 1..Throttle.config()[:login_per_ip] do
        post(%{Phoenix.ConnTest.build_conn() | remote_ip: conn.remote_ip}, "/admin/login", %{
          "user" => %{"email" => "x#{System.unique_integer()}@example.test", "password" => "x"}
        })
      end

      conn = log_in(%{Phoenix.ConnTest.build_conn() | remote_ip: conn.remote_ip}, user)
      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
    end
  end

  describe "when the sign-in policy requires it" do
    setup do
      admin = user(role: :superuser)
      enable(admin)
      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "selected", "two_factor_roles" => ["editor"]}, admin)
      :ok
    end

    test "a user without it sets it up before they get a session" do
      user = user()
      conn = log_in(anonymous(), user, %{"remember_me" => "true"})

      assert redirected_to(conn) == "/admin/login/two-factor/setup"
      refute get_session(conn, :user_token)
      refute conn.resp_cookies[@remember_me]

      # Completing without having set it up does not log in
      early = conn |> next() |> post("/admin/login/two-factor/complete")
      assert redirected_to(early) == "/admin/login/two-factor/setup"
      assert session_tokens(user) == []

      {:ok, view, html} = live(next(conn), "/admin/login/two-factor/setup")
      [secret_text] = Regex.run(~r/data-testid="two-factor-secret"[^>]*>([^<]+)</, html, capture: :all_but_first)
      {:ok, secret} = Base.decode32(String.replace(secret_text, " ", ""), padding: false)

      view
      |> form("#two-factor-setup-form", setup: %{code: TwoFactor.current_code(secret)})
      |> render_submit()

      assert render(view) =~ "recovery-code"
      assert TwoFactor.enabled?(user)

      conn = conn |> next() |> post("/admin/login/two-factor/complete")
      assert redirected_to(conn) == "/admin"
      assert get_session(conn, :user_token)
      assert conn.resp_cookies[@remember_me]
    end

    test "the setup screen checks its waiting sign-in on every event" do
      user = user()
      conn = log_in(anonymous(), user)
      {:ok, view, _html} = live(next(conn), "/admin/login/two-factor/setup")

      # Ended without a word to the screen: too old
      Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "pending_2fa"),
        set: [inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60)]
      )

      assert {:error, {:live_redirect, %{to: "/admin/login"}}} = render_click(view, "method", %{"method" => "app"})
      refute TwoFactor.enabled?(user)
    end

    test "an open setup screen is closed when its sign-in ends, and adds nothing" do
      user = user()
      conn = log_in(anonymous(), user)
      {:ok, view, html} = live(next(conn), "/admin/login/two-factor/setup")
      pending_id = Users.token_id(get_session(conn, :pending_login_token), "pending_2fa")

      # The review's probe: someone with the password holds the setup screen
      # open; the owner resets their password, which ends that sign-in
      {:ok, _} = Users.reset_user_password(user, %{password: "a new one", password_confirmation: "a new one"})
      assert_redirect(view, "/admin/login")

      # and what the screen would have sent no longer adds a factor
      [secret_text] = Regex.run(~r/data-testid="two-factor-secret"[^>]*>([^<]+)</, html, capture: :all_but_first)
      {:ok, secret} = Base.decode32(String.replace(secret_text, " ", ""), padding: false)

      assert {:error, :invalid_proof} =
               TwoFactor.enable(user, secret, TwoFactor.current_code(secret), proof: {:signed_in_now, pending_id})
    end

    test "a user with it signs in with a code as usual" do
      user = user()
      {secret, _codes} = enable(user)

      conn = log_in(anonymous(), user)
      assert redirected_to(conn) == "/admin/login/two-factor"

      conn =
        conn |> next() |> post("/admin/login/two-factor", %{"two_factor" => %{"code" => TwoFactor.current_code(secret)}})

      assert redirected_to(conn) == "/admin"
    end

    test "a user it does not apply to signs in with the password" do
      user = user(role: :user)
      assert redirected_to(log_in(anonymous(), user)) == "/admin"
    end
  end
end
