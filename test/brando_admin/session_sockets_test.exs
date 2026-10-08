defmodule BrandoAdmin.SessionSocketsTest do
  @moduledoc """
  Ending a session — revoking it, logging out, a password change or reset, a
  two-factor reset, deactivating or deleting the account — disconnects its
  sockets, its LiveViews and its admin socket alike, and their old tokens
  are turned away. The user's other sessions keep theirs.
  """
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]
  require Phoenix.ChannelTest

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.UserConfig

  @password %{"password" => "a much longer password", "password_confirmation" => "a much longer password"}

  defp user(attrs \\ []) do
    Factory.insert(
      :random_user,
      Keyword.merge([role: :editor, config: %UserConfig{reset_password_on_first_login: false}], attrs)
    )
  end

  defp socket_token(user, session), do: Users.build_socket_token(user, Users.token_id(session))
  defp connect_admin(token), do: Phoenix.ChannelTest.connect(BrandoAdmin.AdminSocket, %{"token" => token})

  # Stands in for a socket's transport process: subscribed to the socket's
  # id, it stops on "disconnect", as Phoenix's transports do.
  defp transport(socket_id) do
    test = self()

    pid =
      spawn(fn ->
        @endpoint.subscribe(socket_id)
        send(test, {:subscribed, self()})

        receive do
          %Phoenix.Socket.Broadcast{event: "disconnect"} -> exit(:disconnected)
        end
      end)

    assert_receive {:subscribed, ^pid}
    ref = Process.monitor(pid)
    on_exit(fn -> Process.exit(pid, :kill) end)
    ref
  end

  # A transport that, told to disconnect, at once tries to connect again
  # with its old token, as the browser does, and reports how that went
  defp reconnecting_transport(socket_id, token) do
    test = self()

    pid =
      spawn(fn ->
        @endpoint.subscribe(socket_id)
        send(test, {:subscribed, self()})

        receive do
          %Phoenix.Socket.Broadcast{event: "disconnect"} ->
            send(test, :told)
            result = if match?({:ok, _}, Users.verify_socket_token(token)), do: :ok, else: :error
            send(test, {:reconnected, result})
        end
      end)

    assert_receive {:subscribed, ^pid}
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  # Two sessions of `user`, each with its admin socket connected
  defp two_sessions(user) do
    for _ <- 1..2 do
      session = Users.generate_user_session_token(user)
      token = socket_token(user, session)
      assert {:ok, socket} = connect_admin(token)
      %{session: session, id: Users.token_id(session), token: token, transport: transport(socket.id)}
    end
  end

  defp assert_disconnected(%{transport: ref, token: token}) do
    assert_receive {:DOWN, ^ref, :process, _pid, :disconnected}
    assert :error = connect_admin(token)
  end

  defp assert_connected(%{transport: ref, token: token}) do
    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 50
    assert {:ok, _socket} = connect_admin(token)
  end

  describe "the admin socket" do
    test "connects with a token for its session, and goes by the session" do
      user = user()
      [a, b] = for _ <- 1..2, do: Users.generate_user_session_token(user)

      assert {:ok, socket_a} = connect_admin(socket_token(user, a))
      assert {:ok, socket_b} = connect_admin(socket_token(user, b))
      assert socket_a.assigns.user_id == user.id
      assert socket_a.id == Users.live_socket_id(a)
      assert socket_b.id == Users.live_socket_id(b)
    end

    test "turns away a token that does not name a live session of its user" do
      user = user()
      other = user()
      session = Users.generate_user_session_token(user)
      session_id = Users.token_id(session)

      # Signed for the user alone, as before
      assert :error = connect_admin(Phoenix.Token.sign(@endpoint, "user_token", user.id))
      # Someone else's session
      assert :error = connect_admin(Users.build_socket_token(other, session_id))
      # Older than a day
      stale =
        Phoenix.Token.sign(@endpoint, "brando_admin_socket", %{"user_id" => user.id, "session_id" => session_id},
          signed_at: System.system_time(:second) - 86_401
        )

      assert :error = connect_admin(stale)
      assert :error = connect_admin("not a token")
      assert :error = Phoenix.ChannelTest.connect(BrandoAdmin.AdminSocket, %{})

      # An expired session
      Repo.update_all(from(t in Users.UserToken, where: t.id == ^session_id), set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert :error = connect_admin(socket_token(user, session))
    end

    test "revoking a session disconnects its socket and no other" do
      user = user()
      [a, b] = two_sessions(user)

      assert :ok = Users.revoke_session(user, a.id)

      assert_disconnected(a)
      assert_connected(b)
    end

    test "logging out everywhere else keeps this session" do
      user = user()
      [a, b] = two_sessions(user)

      assert :ok = Users.log_out_everywhere(user, user, except_id: b.id)

      assert_disconnected(a)
      assert_connected(b)
    end

    test "an administrator logging the user out everywhere", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert :ok = Users.log_out_everywhere(user, admin)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "changing the password keeps the session that changed it" do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.update_user_password(user, "admin", @password, b.session)

      assert_disconnected(a)
      assert_connected(b)
    end

    test "a password reset ends every session" do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.reset_user_password(user, @password)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "an administrator setting the password ends every session", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.set_user_password(user.id, @password, admin)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "an administrator resetting two-factor authentication ends every session", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.TwoFactor.reset(user.id, admin)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "deactivating the account ends every session", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.set_active(user.id, false, admin)

      assert_disconnected(a)
      assert_disconnected(b)
      # Activated again, the account logs in anew
      assert {:ok, _} = Users.set_active(user.id, true, admin)
      assert :error = connect_admin(a.token)
    end

    test "deleting the account ends every session", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.delete_user(user.id, admin)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "deleting the account and handing its content on ends every session", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, _} = Users.delete_user_with_transfer(user.id, admin.id, admin)

      assert_disconnected(a)
      assert_disconnected(b)
    end

    test "logging out ends that session alone", %{conn: conn, current_user: user} do
      this = get_session(conn, :user_token)
      other = Users.generate_user_session_token(user)
      this_token = socket_token(user, this)
      other_token = socket_token(user, other)
      assert {:ok, this_socket} = connect_admin(this_token)
      assert {:ok, other_socket} = connect_admin(other_token)
      this_ref = transport(this_socket.id)
      other_ref = transport(other_socket.id)

      conn = delete(conn, "/admin/logout")
      assert redirected_to(conn) == "/admin/login"

      assert_disconnected(%{transport: this_ref, token: this_token})
      assert_connected(%{transport: other_ref, token: other_token})
    end

    test "is told apart by session in groups authorization too" do
      user = user()
      put_test_env(:authorization_mode, :groups)
      # Gives the editor its group, and with it the way in
      {:ok, _} = Brando.Authorization.Migration.run()
      [a, b] = two_sessions(user)

      assert :ok = Users.revoke_session(user, a.id)

      assert_disconnected(a)
      assert_connected(b)
    end
  end

  describe "inside a transaction" do
    # A socket told before the commit reconnects at once, still finds the
    # session, and is never told again.
    test "the disconnect waits for the commit, and a reconnect then is refused", %{current_user: admin} do
      user = user()
      put_test_env(:authorization_mode, :groups)
      # Gives the editor its group, and with it the way in
      {:ok, _} = Brando.Authorization.Migration.run()
      session = Users.generate_user_session_token(user)
      token = socket_token(user, session)
      assert {:ok, socket} = connect_admin(token)
      reconnecting_transport(socket.id, token)

      # Deactivating runs in Brando.Authorization.Boundary's transaction,
      # here inside one more
      {:ok, _} =
        Brando.Repo.transaction(fn ->
          assert {:ok, _} = Users.set_active(user.id, false, admin)
          refute_receive :told, 50
        end)

      assert_receive :told
      assert_receive {:reconnected, :error}
      assert :error = connect_admin(token)
      refute Users.session_valid?(Users.token_id(session), user.id)
    end

    test "a rolled back revocation disconnects nothing" do
      user = user()
      [a] = Enum.take(two_sessions(user), 1)

      {:error, :undone} =
        Brando.Repo.transaction(fn ->
          :ok = Users.revoke_session(user, a.id)
          Brando.Repo.rollback(:undone)
        end)

      assert_connected(a)
    end

    test "handing content on disconnects the sessions it deletes", %{current_user: admin} do
      user = user()
      [a, b] = two_sessions(user)

      assert {:ok, %{"users_tokens" => 2}} = Users.transfer_user_content(user.id, admin.id)

      assert_disconnected(a)
      assert_disconnected(b)
    end
  end

  describe "the admin socket's channels" do
    test "refuse a join once the session is gone, told or not" do
      user = user()
      session = Users.generate_user_session_token(user)
      assert {:ok, socket} = connect_admin(socket_token(user, session))
      assert {:ok, _, _} = Phoenix.ChannelTest.subscribe_and_join(socket, Brando.UserChannel, "user:#{user.id}")

      # Ended between the socket's connect and its subscribing to its id
      Repo.delete_all(from(t in Users.UserToken, where: t.token == ^session))

      assert {:error, %{reason: "forbidden"}} =
               Phoenix.ChannelTest.subscribe_and_join(socket, Brando.UserChannel, "user:#{user.id}")

      assert {:error, %{reason: "forbidden"}} =
               Phoenix.ChannelTest.subscribe_and_join(socket, Brando.LobbyChannel, "lobby", %{"url" => "/admin"})

      assert {:error, %{reason: "forbidden"}} =
               Phoenix.ChannelTest.subscribe_and_join(socket, Brando.LivePreviewChannel, "live_preview:key")
    end
  end

  describe "socket ids" do
    test "hold no session token, and the ids from before still disconnect" do
      user = user()
      session = Users.generate_user_session_token(user)
      assert {:ok, socket} = connect_admin(socket_token(user, session))

      state = :erlang.term_to_binary({socket.id, socket.assigns})
      assert :binary.match(state, session) == :nomatch
      assert :binary.match(state, Base.url_encode64(session)) == :nomatch
      assert socket.id == Users.live_socket_id(session)
      refute socket.id == Users.legacy_live_socket_id(session)

      # A tab opened before the upgrade goes by the raw id
      legacy = transport(Users.legacy_live_socket_id(session))
      current = transport(socket.id)
      :ok = Users.revoke_session(user, Users.token_id(session))

      assert_receive {:DOWN, ^legacy, :process, _pid, :disconnected}
      assert_receive {:DOWN, ^current, :process, _pid, :disconnected}
    end

    test "a session from before the upgrade gets the hashed id on its next request", %{conn: conn} do
      token = get_session(conn, :user_token)

      conn =
        conn
        |> put_session(:live_socket_id, Users.legacy_live_socket_id(token))
        |> get("/admin/logout")

      assert get_session(conn, :live_socket_id) == Users.live_socket_id(token)
    end
  end

  describe "LiveViews" do
    test "go by the session that logged in" do
      user = user()

      conn =
        post(build_conn(), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})

      live_socket_id = get_session(conn, :live_socket_id)
      assert live_socket_id == Users.live_socket_id(get_session(conn, :user_token))

      # What the LiveView socket takes for its id
      assert Phoenix.LiveView.Socket.id(%Phoenix.Socket{
               private: %{connect_info: %{session: %{"live_socket_id" => live_socket_id}}}
             }) == live_socket_id
    end

    test "of a revoked session are disconnected, and do not come back", %{conn: conn, current_user: user} do
      this = get_session(conn, :user_token)
      other = Users.generate_user_session_token(user)
      {:ok, _view, _html} = live(conn, "/admin/users/security")
      this_ref = transport(Users.live_socket_id(this))
      other_ref = transport(Users.live_socket_id(other))

      # From the other session's security page
      assert :ok = Users.revoke_session(user, Users.token_id(this))

      assert_receive {:DOWN, ^this_ref, :process, _pid, :disconnected}
      refute_receive {:DOWN, ^other_ref, :process, _pid, _reason}, 50
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, "/admin/users/security")
    end
  end

  describe "logging out" do
    test "GET only asks, with a form that sends a DELETE", %{conn: conn, current_user: user} do
      html = conn |> get("/admin/logout") |> html_response(200)

      assert html =~ ~s(id="logout_form")
      assert html =~ ~s(action="/admin/logout")
      assert html =~ ~r/name="_method"[^>]*value="delete"/
      assert html =~ ~s(name="_csrf_token")
      assert html =~ user.email

      # Still signed in, also once the page is connected
      {:ok, _view, _html} = live(conn, "/admin/logout")
      assert Users.get_user_by_session_token(get_session(conn, :user_token))
    end

    test "GET without a session goes to log in" do
      conn = build_conn() |> init_test_session(%{}) |> get("/admin/logout")
      assert redirected_to(conn) == "/admin/login"
    end

    test "DELETE logs out, as does POST", %{conn: conn, current_user: user} do
      token = get_session(conn, :user_token)
      @endpoint.subscribe(Users.live_socket_id(token))

      conn = delete(conn, "/admin/logout")
      assert redirected_to(conn) == "/admin/login"
      refute get_session(conn, :user_token)
      refute Users.get_user_by_session_token(token)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      token = Users.generate_user_session_token(user)
      conn = build_conn() |> init_test_session(%{user_token: token}) |> post("/admin/logout")
      assert redirected_to(conn) == "/admin/login"
      refute Users.get_user_by_session_token(token)
    end

    # `Phoenix.ConnTest` skips the CSRF check; these requests go through
    # the endpoint as a browser's would.
    test "without the CSRF token, DELETE does nothing", %{current_user: user} do
      token = Users.generate_user_session_token(user)

      conn = Plug.Test.init_test_session(Plug.Test.conn(:delete, "/admin/logout"), %{user_token: token})
      assert %Plug.CSRFProtection.InvalidCSRFTokenError{} = unwrap(catch_error(@endpoint.call(conn, [])))
      assert Users.get_user_by_session_token(token)

      # With it, as the sign-out forms send it
      masked = Plug.CSRFProtection.get_csrf_token()
      state = Plug.CSRFProtection.dump_state()

      conn =
        :delete
        |> Plug.Test.conn("/admin/logout", %{"_csrf_token" => masked})
        |> Plug.Test.init_test_session(%{"user_token" => token, "_csrf_token" => state})
        |> @endpoint.call([])

      assert redirected_to(conn) == "/admin/login"
      refute Users.get_user_by_session_token(token)
    end

    test "the account menu signs out with a DELETE", %{conn: conn} do
      html = conn |> get("/admin/users/security") |> html_response(200)
      [form] = Regex.run(~r/<form[^>]*id="logout-form".*?<\/form>/s, html)

      assert form =~ ~s(action="/admin/logout")
      assert form =~ ~s(method="post")
      assert form =~ ~r/name="_method"[^>]*value="delete"/
      assert form =~ ~s(name="_csrf_token")
      refute html =~ ~s(href="/admin/logout")
    end

    test "the access-denied page signs out with a DELETE", %{conn: conn} do
      html = conn |> get("/admin/access-denied") |> html_response(403)
      [form] = Regex.run(~r/<form[^>]*action="\/admin\/logout".*?<\/form>/s, html)

      assert form =~ ~s(method="post")
      assert form =~ ~r/name="_method"[^>]*value="delete"/
      assert [_, csrf] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, form)
      assert csrf != ""
      refute html =~ ~s(href="/admin/logout")
    end
  end

  defp unwrap(%Plug.Conn.WrapperError{reason: reason}), do: reason
  defp unwrap(error), do: error
end
