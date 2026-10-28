defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Serves live previews at `/__livepreview?key=<key>`: the cached page of an
  unsaved entry, with the script that keeps it up to date.

  The page holds the site's own markup, editor content included. Every
  response carries a Content-Security-Policy that sandboxes it
  (`sandbox_policy/0`): its scripts run in an opaque origin, apart from the
  admin pages that frame or open it and from the viewer's cookies.
  `frame-ancestors 'self'` and `base-uri 'self'` follow. Add directives with

      config :brando, :live_preview_content_security_policy, "script-src 'self' https://cdn.example.com"

  The page's script connects to `BrandoAdmin.LivePreviewSocket`, which the
  endpoint mounts at `/__livepreview/socket`, with a token good only for this
  preview's channel (`Brando.LivePreview.SocketToken`), never the viewer's
  admin socket token; the channel hands it a fresh one before it expires.
  Without that socket, the page reports live updates unavailable, and the
  log names the endpoint line to add. The script is
  served from `/__livepreview/client-<hash>.js`, and the storage stand-ins the
  site's own scripts need in an opaque origin (`put_storage_script/1`) from
  `/__livepreview/storage-<hash>.js`, so a policy without `'unsafe-inline'`
  allows both.

  See the Live preview guide.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @external_resource Application.app_dir(:phoenix, "priv/static/phoenix.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/block_patch.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/livepreview.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/livepreview_highlight.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/livepreview_storage.js")

  @client_js Enum.map_join(
               [
                 Application.app_dir(:phoenix, "priv/static/phoenix.js"),
                 Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"),
                 Application.app_dir(:brando, "priv/static/js/block_patch.js"),
                 Application.app_dir(:brando, "priv/static/js/livepreview.js"),
                 Application.app_dir(:brando, "priv/static/js/livepreview_highlight.js")
               ],
               "\n;\n",
               &File.read!/1
             )
  @client_vsn :sha256 |> :crypto.hash(@client_js) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  @storage_js File.read!(Application.app_dir(:brando, "priv/static/js/livepreview_storage.js"))
  @storage_vsn :sha256 |> :crypto.hash(@storage_js) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  # No `allow-same-origin`, so the page's origin is opaque, and no top
  # navigation, so content cannot take the admin page away. A popup the page
  # opens (a link with `target="_blank"`) leaves the sandbox, as that link
  # opened from any other site would: it holds whatever page it links to, with
  # no access to this one.
  @sandbox_flags "allow-scripts allow-forms allow-modals allow-downloads allow-popups allow-popups-to-escape-sandbox"
  @sandbox "sandbox " <> @sandbox_flags
  @base_csp @sandbox <> "; frame-ancestors 'self'; base-uri 'self'"

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
  def call(%Plug.Conn{path_info: ["__livepreview", "client-" <> file]} = conn, _),
    do: send_script(conn, @client_js, file == @client_vsn <> ".js")

  def call(%Plug.Conn{path_info: ["__livepreview", "storage-" <> file]} = conn, _),
    do: send_script(conn, @storage_js, file == @storage_vsn <> ".js")

  # The endpoint answers its sockets before any plug runs, so a request for
  # the preview socket that gets here means the endpoint does not mount it.
  # The preview's script tells the admin page that live updates are
  # unavailable; the log says why, once.
  def call(%Plug.Conn{path_info: ["__livepreview", "socket" | _]} = conn, _) do
    endpoint = conn.private[:phoenix_endpoint] || Brando.endpoint()

    if :persistent_term.get({__MODULE__, :socket_missing}, false) == false do
      :persistent_term.put({__MODULE__, :socket_missing}, true)

      Logger.error("""
      Live preview updates are unavailable: #{inspect(endpoint)} does not mount the preview socket. \
      Add this line to it, next to `socket "/admin/socket"`, or run `mix brando.migrate55`:

          #{BrandoAdmin.LivePreviewSocket.endpoint_line()}
      """)
    end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "The endpoint does not mount the live preview socket.")
    |> halt()
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
  The Content-Security-Policy of preview responses: `sandbox_policy/0`,
  `frame-ancestors 'self'` and `base-uri 'self'`, followed by the directives
  in the `:live_preview_content_security_policy` config, if any.
  """
  @spec content_security_policy() :: String.t()
  def content_security_policy do
    case Brando.config(:live_preview_content_security_policy) do
      extra when is_binary(extra) and extra != "" -> @base_csp <> "; " <> String.trim(extra)
      _ -> @base_csp
    end
  end

  @doc """
  The CSP `sandbox` directive of preview pages and shared preview snapshots.
  Scripts, forms, dialogs, downloads and popups work, in an opaque origin: the
  page can neither reach the admin pages that frame or open it nor send a
  request with the viewer's `SameSite=Lax` cookies.
  """
  @spec sandbox_policy() :: String.t()
  def sandbox_policy, do: @sandbox

  @doc """
  The same flags for an admin page's preview `<iframe sandbox>`. The response
  header sandboxes the preview; the attribute keeps sandboxed whatever else
  the frame navigates to, such as another page of the site.
  """
  @spec sandbox_flags() :: String.t()
  def sandbox_flags, do: @sandbox_flags

  @doc """
  Puts the script that stands in for `localStorage`, `sessionStorage` and
  `document.cookie` first in `html`'s `<head>`, before the site's own scripts.
  In a sandboxed page these throw, and a site script that reads them would
  stop there; the stand-ins keep what is written in memory for the page's life.
  """
  @spec put_storage_script(iodata()) :: String.t()
  def put_storage_script(html) when is_list(html), do: html |> IO.iodata_to_binary() |> put_storage_script()

  def put_storage_script(html) when is_binary(html) do
    tag = ~s(<script src="#{storage_path()}"></script>)

    # After `<head>`; without one, where the parser opens it
    match =
      Enum.find_value([~r/<head(?:\s[^>]*)?>/i, ~r/<html(?:\s[^>]*)?>/i, ~r/<!doctype[^>]*>/i], fn pattern ->
        Regex.run(pattern, html, return: :index)
      end)

    case match do
      [{at, length}] ->
        split = at + length
        binary_part(html, 0, split) <> tag <> binary_part(html, split, byte_size(html) - split)

      nil ->
        tag <> html
    end
  end

  @doc false
  def client_path, do: "/__livepreview/client-#{@client_vsn}.js"

  @doc """
  The path of the storage stand-ins `put_storage_script/1` puts in a page,
  under `/__livepreview/` with the script's hash.
  """
  @spec storage_path() :: String.t()
  def storage_path, do: "/__livepreview/storage-#{@storage_vsn}.js"

  defp send_script(conn, script, current?) do
    cache_control = if current?, do: "public, max-age=31536000, immutable", else: "no-cache"

    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", cache_control)
    |> send_resp(200, script)
    |> halt()
  end

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
          <meta name="brando-live-preview" data-key="#{attribute(key)}" data-version="#{generation}" data-token="#{attribute(socket_token)}" data-token-max-age="#{Brando.LivePreview.SocketToken.max_age()}">
          <script src="#{client_path()}"></script>
          <style>
          #{@override_css}
          </style>
          """

          [page | rest] = String.split(initial_html, "</body>")
          html = put_storage_script(page <> inject_html <> Enum.join(["</body>" | rest]))

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, [html])
          |> halt()
        rescue
          err ->
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
