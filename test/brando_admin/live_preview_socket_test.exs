defmodule BrandoAdmin.LivePreviewSocketTest do
  @moduledoc """
  The live-preview document runs editor markup on the admin origin, so the
  socket token it is served (`Brando.LivePreview.SocketToken`) must open only
  that preview's channel: not the lobby, not the user channel, not another
  preview, and not after it expires or its session ends.
  """
  use Brando.ConnCase
  import Phoenix.ChannelTest, only: [subscribe_and_join: 2, subscribe_and_join: 3]
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

      for key <- keys do
        Preview.cleanup(key)
        Cachex.del(:cache, "__live_preview__#{key}")
      end
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

  test "the preview's token opens its own preview channel and no admin channel", c do
    token = served_token(c)
    assert {:error, :invalid} = Users.verify_socket_token(token)

    assert {:ok, socket} = connect_admin(token)
    refute Map.has_key?(socket.assigns, :user_id)

    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "lobby", %{"url" => "/admin"})
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "user:#{c.editor.id}")
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "live_preview:#{c.other_key}")

    assert {:ok, user_id, _} = subscribe_and_join(socket, "live_preview:#{c.key}")
    assert user_id == c.editor.id
  end

  test "the admin socket token still opens the admin channels", c do
    token = Users.build_socket_token(c.editor, Users.token_id(c.session))
    assert {:ok, socket} = connect_admin(token)
    assert {:ok, _, _} = subscribe_and_join(socket, "user:#{c.editor.id}")
    assert {:ok, _, _} = subscribe_and_join(socket, "live_preview:#{c.key}")
  end

  test "the preview's token expires", c do
    session_id = Users.token_id(c.session)
    stale = System.system_time(:second) - SocketToken.max_age() - 1
    assert :error = connect_admin(SocketToken.build(c.editor, session_id, c.key, signed_at: stale))

    fresh = System.system_time(:second) - SocketToken.max_age() + 60
    assert {:ok, _} = connect_admin(SocketToken.build(c.editor, session_id, c.key, signed_at: fresh))
  end

  test "the preview's token ends with its session", c do
    token = served_token(c)
    assert {:ok, socket} = connect_admin(token)

    Users.delete_session_token(c.session)
    assert :error = connect_admin(token)
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

    assert {:ok, socket} = connect_admin(forged)
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "live_preview:#{c.key}")
  end

  test "the token endpoint hands a fresh preview token only to the preview's viewer", c do
    conn =
      build_conn(:get, "/__livepreview/token?key=#{c.key}")
      |> init_test_session(%{user_token: c.session})
      |> Brando.Plug.LivePreview.call([])

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert {:ok, %{key: key}} = SocketToken.verify(Jason.decode!(conn.resp_body)["token"])
    assert key == c.key

    other = Factory.insert(:random_user, role: :editor, avatar: nil)

    for session <- [%{user_token: Users.generate_user_session_token(other)}, %{}] do
      conn =
        build_conn(:get, "/__livepreview/token?key=#{c.key}")
        |> init_test_session(session)
        |> Brando.Plug.LivePreview.call([])

      assert conn.status == 403
      refute conn.resp_body =~ "token\":"
    end
  end
end
