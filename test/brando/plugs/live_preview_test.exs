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

    assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'self'; base-uri 'self'"]
  end

  test "the preview key is escaped into the page", %{user: user} do
    key = ~s(K'"></script><b id="x">)
    Brando.LivePreview.store_cache(key, "<html><body><main>test</main></body></html>")
    on_exit(fn -> Cachex.del(:cache, "__live_preview__" <> key) end)

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
             "frame-ancestors 'self'; base-uri 'self'; script-src 'self' https://cdn.example.com"
           ]
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
