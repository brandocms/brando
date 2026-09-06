defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Router for live-preview
  """

  @behaviour Plug

  import Plug.Conn

  @external_resource Application.app_dir(:phoenix, "priv/static/phoenix.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/livepreview.js")

  @phoenix_js File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.js"))
  @morphdom_js File.read!(Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"))
  @livepreview_js File.read!(Application.app_dir(:brando, "priv/static/js/livepreview.js"))

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

  def call(%Plug.Conn{path_info: ["__livepreview" | _suffix]} = conn, _) do
    key = conn.query_string && Plug.Conn.Query.decode(conn.query_string)["key"]
    conn = put_resp_header(conn, "cache-control", "private, no-store")

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

  defp serve(conn, key) do
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

        current_user = conn_copy.assigns[:current_user]

        try do
          inject_html = """
          <!-- BRANDO LIVE PREVIEW -->
          <meta name="user_token" content="#{Brando.Users.build_token(current_user.id)}">
          <script>
          var livePreviewKey = '#{key}';
          #{@phoenix_js}
          #{@morphdom_js}
          #{@livepreview_js}
          </script>
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
end
