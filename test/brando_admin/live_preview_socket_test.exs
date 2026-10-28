defmodule BrandoAdmin.LivePreviewSocketTest do
  @moduledoc """
  The live-preview document runs editor markup, so the socket token it is
  served (`Brando.LivePreview.SocketToken`) must open only that preview's
  channel: not the lobby, not the user channel, not another preview, and not
  after it expires or its session ends. The document is sandboxed, so it
  connects from origin `null`, to `BrandoAdmin.LivePreviewSocket` at
  `/__livepreview/socket`, which takes nothing but that token.
  """
  use Brando.ConnCase
  import Phoenix.ChannelTest, only: [subscribe_and_join: 2]
  require Phoenix.ChannelTest
  alias Brando.Authorization.{Boundary, Migration, Preview, Scope}
  alias Brando.Factory
  alias Brando.LivePreview.SocketToken
  alias Brando.Users

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    Brando.Tenant.put_prefix(nil)
    _owner = Factory.insert(:random_user, role: :superuser, avatar: nil)
    editor = Factory.insert(:random_user, role: :editor, avatar: nil)
    page = Factory.insert(:page, status: :draft)
    {:ok, _} = Migration.run()

    keys = for _ <- 1..2, do: "SOCKET-PREVIEW-#{Ecto.UUID.generate()}"

    for key <- keys do
      assert :ok =
               Boundary.with_scope(Scope.standalone(editor), fn -> Preview.register(key, Ecto.Changeset.change(page)) end)

      Brando.LivePreview.store_cache(key, "<html><body><main>Draft</main></body></html>")
    end

    on_exit(fn ->
      Boundary.put_scope(nil)

      Enum.each(keys, &Brando.LivePreview.cleanup_cache/1)
    end)

    session = Users.generate_user_session_token(editor)
    [key, other_key] = keys
    %{editor: editor, session: session, key: key, other_key: other_key}
  end

  defp served_token(c) do
    conn =
      build_conn(:get, "/__livepreview?key=#{c.key}")
      |> init_test_session(%{user_token: c.session})
      |> Brando.Plug.LivePreview.call([])

    assert conn.status == 200
    [_, token] = Regex.run(~r/data-token="([^"]+)"/, conn.resp_body)
    token
  end

  defp connect_admin(token), do: Phoenix.ChannelTest.connect(BrandoAdmin.AdminSocket, %{"token" => token})

  defp connect_preview(token), do: Phoenix.ChannelTest.connect(BrandoAdmin.LivePreviewSocket, %{"token" => token})

  # A WebSocket upgrade through the test endpoint, as a sandboxed page sends it
  defp upgrade(path, token), do: upgrade_at(path <> "/websocket", token)

  defp upgrade_at(path, token) do
    build_conn(:get, "#{path}?" <> URI.encode_query(%{"token" => token, "vsn" => "2.0.0"}))
    |> then(&%{&1 | req_headers: [{"host", "localhost"} | &1.req_headers]})
    |> put_req_header("origin", "null")
    |> put_req_header("connection", "Upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-version", "13")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> BrandoIntegrationWeb.Endpoint.call([])
  end

  test "the preview's token opens its own preview channel and no admin channel", c do
    token = served_token(c)
    assert {:error, :invalid} = Users.verify_socket_token(token)
    assert :error = connect_admin(token)

    assert {:ok, socket} = connect_preview(token)
    refute Map.has_key?(socket.assigns, :user_id)

    # No other channel is routed on the preview socket, and no other preview joins
    refute BrandoAdmin.LivePreviewSocket.__channel__("lobby")
    refute BrandoAdmin.LivePreviewSocket.__channel__("user:#{c.editor.id}")
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "live_preview:#{c.other_key}")

    assert {:ok, user_id, _} = subscribe_and_join(socket, "live_preview:#{c.key}")
    assert user_id == c.editor.id
  end

  test "the admin socket token still opens the admin channels, and not the preview socket", c do
    token = Users.build_socket_token(c.editor, Users.token_id(c.session))
    assert {:ok, socket} = connect_admin(token)
    assert {:ok, _, _} = subscribe_and_join(socket, "user:#{c.editor.id}")
    assert {:ok, _, _} = subscribe_and_join(socket, "live_preview:#{c.key}")

    assert :error = connect_preview(token)
  end

  # Origin `null` is every sandboxed document on the web; the preview socket
  # takes it because it takes no cookie, only the preview's token
  test "the preview socket takes origin null with a preview token; the admin socket keeps its origin check", c do
    conn = upgrade("/__livepreview/socket", served_token(c))
    assert conn.halted

    assert [{:websocket, {BrandoAdmin.LivePreviewSocket, {_, %{assigns: %{preview: _}}}, _opts}}] =
             Plug.Test.sent_upgrades(conn)

    admin_token = Users.build_socket_token(c.editor, Users.token_id(c.session))
    conn = upgrade("/__livepreview/socket", admin_token)
    assert conn.status == 403
    assert Plug.Test.sent_upgrades(conn) == []

    # However the path is spelled (Phoenix routes sockets on the path's segments)
    for path <- ["/__livepreview/socket/websocket/", "/__livepreview//socket/websocket"] do
      conn = upgrade_at(path, admin_token)
      assert conn.status == 403, path
      assert Plug.Test.sent_upgrades(conn) == [], path
    end

    conn = upgrade("/admin/socket", admin_token)
    assert conn.status == 403
    assert Plug.Test.sent_upgrades(conn) == []
  end

  # The page has no cookies to fetch a fresh token with; the channel hands
  # one over before the last expires, while the session and preview last
  test "the preview channel hands over a fresh token, while the preview lasts", c do
    {:ok, socket} = connect_preview(served_token(c))
    {:ok, _, socket} = subscribe_and_join(socket, "live_preview:#{c.key}")

    send(socket.channel_pid, :refresh_token)
    Phoenix.ChannelTest.assert_push("token", %{token: fresh})
    assert {:ok, %{key: key, user_id: user_id}} = SocketToken.verify(fresh)
    assert {key, user_id} == {c.key, c.editor.id}

    ref = Process.monitor(socket.channel_pid)
    Users.delete_session_token(c.session)
    send(socket.channel_pid, :refresh_token)
    assert_receive {:DOWN, ^ref, :process, _, _}
    Phoenix.ChannelTest.refute_push("token", _)
  end

  test "the preview's token expires", c do
    session_id = Users.token_id(c.session)
    stale = System.system_time(:second) - SocketToken.max_age() - 1
    assert :error = connect_preview(SocketToken.build(c.editor, session_id, c.key, signed_at: stale))

    fresh = System.system_time(:second) - SocketToken.max_age() + 60
    assert {:ok, _} = connect_preview(SocketToken.build(c.editor, session_id, c.key, signed_at: fresh))
  end

  test "the preview's token ends with its session", c do
    token = served_token(c)
    assert {:ok, socket} = connect_preview(token)

    Users.delete_session_token(c.session)
    assert :error = connect_preview(token)
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "live_preview:#{c.key}")
  end

  test "a preview token for another site or environment does not join", c do
    session_id = Users.token_id(c.session)

    forged =
      Phoenix.Token.sign(Brando.endpoint(), "brando_live_preview_socket", %{
        "user_id" => c.editor.id,
        "session_id" => session_id,
        "key" => c.key,
        "tenant" => [1, 1]
      })

    assert {:ok, socket} = connect_preview(forged)
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "live_preview:#{c.key}")
  end
end
