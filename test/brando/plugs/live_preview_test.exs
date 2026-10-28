defmodule Brando.Plug.LivePreviewTest do
  use ExUnit.Case
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Factory
  alias Brando.Plug.LivePreview

  setup do
    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

    Cachex.del!(:cache, "__live_preview__LIVEPREVIEWKEY")
    user = Factory.insert(:random_user)
    {:ok, %{opts: opts, user: user}}
  end

  test "live preview plug pass through", %{opts: opts} do
    conn =
      :get
      |> build_conn("/pass")
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call(LivePreview.init([]))

    assert conn.status == nil
  end

  test "live preview halts on missing cache", %{opts: opts} do
    capture_log(fn ->
      conn =
        :get
        |> build_conn("/__livepreview?key=LIVEPREVIEWKEY")
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(opts)
        |> LivePreview.call([])

      assert conn.halted == true
      assert conn.resp_body == "LIVE PREVIEW FAILED. NO DATA SET FOR KEY LIVEPREVIEWKEY"
    end)
  end

  test "live preview fails on weird data", %{opts: opts, user: user} do
    capture_log(fn ->
      Brando.LivePreview.store_cache(
        "LIVEPREVIEWKEY",
        [nil, []]
      )

      token = Brando.Users.generate_user_session_token(user)

      conn =
        :get
        |> build_conn("/__livepreview?key=LIVEPREVIEWKEY")
        |> init_test_session(%{user_token: token})
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(opts)
        |> LivePreview.call([])

      assert conn.halted == true

      assert conn.resp_body =~ "LIVE PREVIEW FAILED. Check server logs for details."
    end)
  end

  test "unknown preview keys cannot inject HTML into the legacy error page" do
    key = URI.encode_www_form("<script>alert(1)</script>")
    conn = build_conn(:get, "/__livepreview?key=#{key}") |> LivePreview.call([])
    refute conn.resp_body =~ "<script>"
    assert conn.resp_body =~ "&lt;script&gt;"
  end

  test "live preview succeeds", %{opts: opts, user: user} do
    Brando.LivePreview.store_cache(
      "LIVEPREVIEWKEY",
      "<html><head></head><body>
      <main><h1>test</h1></main></body></html>"
    )

    token = Brando.Users.generate_user_session_token(user)

    conn =
      :get
      |> build_conn("/__livepreview?key=LIVEPREVIEWKEY")
      |> init_test_session(%{user_token: token})
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call([])

    assert conn.halted == true
    assert conn.resp_body =~ "</main><!-- BRANDO LIVE PREVIEW -->"
    assert conn.resp_body =~ ~r"<script src=\"/__livepreview/client-[0-9a-f]{16}\.js\"></script>"

    # The page holds editor markup, so its socket token opens only this
    # preview's channel, for this session; the admin socket token stays out
    refute conn.resp_body =~ ~s(name="user_token")
    [_, socket_token] = Regex.run(~r/data-token="([^"]+)"/, conn.resp_body)
    session_id = Brando.Users.token_id(token)
    assert {:error, :invalid} = Brando.Users.verify_socket_token(socket_token)

    assert {:ok, %{session_id: ^session_id, key: "LIVEPREVIEWKEY"}} =
             Brando.LivePreview.SocketToken.verify(socket_token)

    refute conn.resp_body =~ Brando.Users.build_socket_token(user, session_id)

    # Sandboxed: the page's origin is opaque, apart from the admin pages
    # that frame or open it and from the viewer's cookies
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp == LivePreview.sandbox_policy() <> "; frame-ancestors 'self'; base-uri 'self'"
    assert csp =~ ~r/^sandbox allow-scripts /
    refute csp =~ "allow-same-origin"
    refute csp =~ "allow-top-navigation"

    # The storage stand-ins run before any of the site's scripts
    assert conn.resp_body =~ ~r"^<html><head><script src=\"/__livepreview/storage-[0-9a-f]{16}\.js\"></script></head>"
    assert conn.resp_body =~ ~s(data-token-max-age="#{Brando.LivePreview.SocketToken.max_age()}")
  end

  test "the preview key is escaped into the page", %{user: user} do
    key = ~s(K'"></script><b id="x">)
    Brando.LivePreview.store_cache(key, "<html><body><main>test</main></body></html>")
    on_exit(fn -> Brando.LivePreview.cleanup_cache(key) end)

    conn =
      build_conn(:get, "/__livepreview?key=#{URI.encode_www_form(key)}")
      |> init_test_session(%{user_token: Brando.Users.generate_user_session_token(user)})
      |> LivePreview.call([])

    assert conn.status == 200
    refute conn.resp_body =~ key
    assert conn.resp_body =~ ~s(data-key="K&#39;&quot;&gt;&lt;/script&gt;&lt;b id=&quot;x&quot;&gt;")
  end

  test "projects add directives to the preview's Content-Security-Policy" do
    put_test_env(:live_preview_content_security_policy, "script-src 'self' https://cdn.example.com")
    conn = build_conn(:get, "/__livepreview?key=missing") |> LivePreview.call([])

    assert get_resp_header(conn, "content-security-policy") == [
             LivePreview.sandbox_policy() <>
               "; frame-ancestors 'self'; base-uri 'self'; script-src 'self' https://cdn.example.com"
           ]
  end

  test "the storage stand-ins go first in the head, wherever the parser opens it" do
    tag = ~s(<script src="#{LivePreview.storage_path()}"></script>)

    assert LivePreview.put_storage_script(
             ~s(<!DOCTYPE html><html lang="no"><HEAD data-x="1"><script src="/a.js"></script>)
           ) ==
             ~s(<!DOCTYPE html><html lang="no"><HEAD data-x="1">#{tag}<script src="/a.js"></script>)

    # `<header>` is not the head
    assert LivePreview.put_storage_script("<!doctype html><html><body><header>x</header>") ==
             "<!doctype html><html>#{tag}<body><header>x</header>"

    assert LivePreview.put_storage_script("<!doctype html><p>x</p>") == "<!doctype html>#{tag}<p>x</p>"
    assert LivePreview.put_storage_script(["<p>", "x</p>"]) == tag <> "<p>x</p>"
  end

  test "the storage stand-ins are served from a path a script-src policy can allow" do
    conn = build_conn(:get, LivePreview.storage_path()) |> LivePreview.call([])

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert conn.resp_body =~ "localStorage"

    conn = build_conn(:get, "/__livepreview/storage-0123456789abcdef.js") |> LivePreview.call([])
    assert conn.resp_body =~ "localStorage"
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
  end

  # The endpoint answers the sockets it mounts before any plug runs: the
  # preview socket's path reaching the plug means the endpoint lacks the line
  test "without the preview socket in the endpoint, the log names the line to add, once" do
    :persistent_term.erase({LivePreview, :socket_missing})
    on_exit(fn -> :persistent_term.erase({LivePreview, :socket_missing}) end)
    request = fn -> build_conn(:get, "/__livepreview/socket/websocket?vsn=2.0.0") |> LivePreview.call([]) end

    log = capture_log(fn -> assert %{status: 404, halted: true} = request.() end)
    assert log =~ "Live preview updates are unavailable"
    assert log =~ BrandoAdmin.LivePreviewSocket.endpoint_line()

    assert capture_log(fn -> assert %{status: 404} = request.() end) == ""
  end

  # The cookie-based token route went with the sandbox: the page has no
  # cookies to send it (the channel hands over fresh tokens instead)
  test "there is no token route; it is a preview page like any other path" do
    conn = build_conn(:get, "/__livepreview/token?key=missing") |> LivePreview.call([])
    assert conn.halted
    refute conn.resp_body =~ "token"
    assert [_] = get_resp_header(conn, "content-security-policy")
  end

  test "the preview's script is served from a path a script-src policy can allow" do
    conn = build_conn(:get, LivePreview.client_path()) |> LivePreview.call([])

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert conn.resp_body =~ "brando-live-preview"

    # Another release's hash gets this script, but not cached under that hash
    conn = build_conn(:get, "/__livepreview/client-0123456789abcdef.js") |> LivePreview.call([])
    assert conn.resp_body =~ "brando-live-preview"
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
  end
end
