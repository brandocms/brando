defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Serves live previews at `/__livepreview?key=<key>`: the cached page of an
  unsaved entry, with the script that keeps it up to date.

  The page holds the site's own markup, editor content included, on the admin
  origin. Its script connects to the admin socket with a token good only for
  this preview's channel (`Brando.LivePreview.SocketToken`), never the
  viewer's admin socket token; it gets a fresh one from
  `/__livepreview/token?key=<key>` when it has to connect again. The script
  itself is served from `/__livepreview/client-<hash>.js`, so a policy without
  `'unsafe-inline'` allows it.

  Every response carries a Content-Security-Policy with
  `frame-ancestors 'self'` and `base-uri 'self'`. Add directives with

      config :brando, :live_preview_content_security_policy, "script-src 'self' https://cdn.example.com"

  See the Live preview guide.
  """

  @behaviour Plug

  import Plug.Conn

  @external_resource Application.app_dir(:phoenix, "priv/static/phoenix.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/block_patch.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/livepreview.js")

  @client_js Enum.map_join(
               [
                 Application.app_dir(:phoenix, "priv/static/phoenix.js"),
                 Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"),
                 Application.app_dir(:brando, "priv/static/js/block_patch.js"),
                 Application.app_dir(:brando, "priv/static/js/livepreview.js")
               ],
               "\n;\n",
               &File.read!/1
             )
  @client_vsn :sha256 |> :crypto.hash(@client_js) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  @base_csp "frame-ancestors 'self'; base-uri 'self'"

  @override_css """
  html.is-updated-live-preview [data-moonwalk],
  html.is-updated-live-preview [data-moonwalk-section],
  html.is-updated-live-preview [data-moonwalk-run],
  html.is-updated-live-preview [data-moonwalk-children] > *,
  html.is-updated-live-preview [data-ll-srcset],
  html.is-updated-live-preview [data-ll-srcset] img[data-ll-loaded] {
    opacity: 1 !important;
    visibility: visible !important;
    transform: none !important;
    transition: none !important;
    clip-path: none !important;
  }
  html.is-updated-live-preview [data-smart-video],
  html.is-updated-live-preview [data-smart-video] video,
  html.is-updated-live-preview [data-smart-video] iframe {
    opacity: 1 !important;
    visibility: visible !important;
  }
  """

  def init(opts), do: opts

  # The hash in the path, not a query string, so a CDN that ignores query
  # strings does not keep an old script. Any hash gets the current script,
  # cached for good only under its own hash: a page from another release
  # (during a deploy) must not pin this one under its hash.
  def call(%Plug.Conn{path_info: ["__livepreview", "client-" <> file]} = conn, _) do
    cache_control =
      if file == @client_vsn <> ".js", do: "public, max-age=31536000, immutable", else: "no-cache"

    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", cache_control)
    |> send_resp(200, @client_js)
    |> halt()
  end

  def call(%Plug.Conn{path_info: ["__livepreview", "token"]} = conn, _) do
    key = preview_key(conn)

    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> fetch_session()
      |> BrandoAdmin.UserAuth.fetch_current_user(nil)

    user = conn.assigns[:current_user]

    with true <- is_binary(key) and key != "",
         %{id: user_id} <- user,
         :ok <- Brando.Authorization.Preview.authorize(key, user_id),
         token when is_binary(token) <- preview_socket_token(conn, key) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{token: token}))
      |> halt()
    else
      _ -> conn |> put_resp_content_type("application/json") |> send_resp(403, ~s({"error":"forbidden"})) |> halt()
    end
  end

  def call(%Plug.Conn{path_info: ["__livepreview" | _suffix]} = conn, _) do
    key = preview_key(conn)

    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-security-policy", content_security_policy())

    if Brando.Authorization.enabled?() do
      conn = conn |> fetch_session() |> BrandoAdmin.UserAuth.fetch_current_user(nil)
      user = conn.assigns[:current_user]

      if user && Brando.Authorization.Preview.authorize(key, user.id) == :ok do
        serve(conn, key)
      else
        conn |> put_resp_content_type("text/html") |> send_resp(403, "This preview is no longer available.") |> halt()
      end
    else
      serve(conn, key)
    end
  end

  def call(conn, _), do: conn

  @doc """
  The Content-Security-Policy of preview responses: `frame-ancestors 'self'`
  and `base-uri 'self'`, followed by the directives in the
  `:live_preview_content_security_policy` config, if any.
  """
  @spec content_security_policy() :: String.t()
  def content_security_policy do
    case Brando.config(:live_preview_content_security_policy) do
      extra when is_binary(extra) and extra != "" -> @base_csp <> "; " <> String.trim(extra)
      _ -> @base_csp
    end
  end

  @doc false
  def client_path, do: "/__livepreview/client-#{@client_vsn}.js"

  defp preview_key(conn), do: conn.query_string && Plug.Conn.Query.decode(conn.query_string)["key"]

  # Signed in, as the preview's socket requires; nil without a session
  defp preview_socket_token(conn, key) do
    with %{id: _} = user <- conn.assigns[:current_user],
         session_id when is_integer(session_id) <- Brando.Users.token_id(get_session(conn, :user_token)) do
      Brando.LivePreview.SocketToken.build(user, session_id, key)
    else
      _ -> nil
    end
  end

  defp serve(conn, key) do
    # Before the HTML: see `Brando.LivePreview.page_state/1`
    generation = Brando.LivePreview.page_state(key).generation

    case Brando.LivePreview.get_cache(key) do
      {:ok, nil} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, [
          "LIVE PREVIEW FAILED. NO DATA SET FOR KEY #{Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(key || ""))}"
        ])
        |> halt()

      {:ok, initial_html} ->
        #! GRAB THE COMPLETE HTML FROM ETS AND TAG ON THE JAVASCRIPT PORTION.
        #! CONSECUTIVE UPDATES WILL ONLY TARGET <MAIN>

        conn_copy =
          conn
          |> Plug.Conn.fetch_session()
          |> Phoenix.Controller.fetch_flash()
          |> BrandoAdmin.UserAuth.fetch_current_user(nil)

        try do
          socket_token = preview_socket_token(conn_copy, key) || raise "no admin session"

          inject_html = """
          <!-- BRANDO LIVE PREVIEW -->
          <meta name="brando-live-preview" data-key="#{attribute(key)}" data-version="#{generation}" data-token="#{attribute(socket_token)}">
          <script src="#{client_path()}"></script>
          <style>
          #{@override_css}
          </style>
          """

          [page | rest] = String.split(initial_html, "</body>")
          html = page <> inject_html <> Enum.join(["</body>" | rest])

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, [html])
          |> halt()
        rescue
          err ->
            require Logger
            Logger.error("Livepreview call failed: #{Exception.format(:error, err, __STACKTRACE__)}")

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(200, ["LIVE PREVIEW FAILED. Check server logs for details."])
            |> halt()
        end
    end
  end

  defp attribute(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
