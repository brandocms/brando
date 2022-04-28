defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Router for live-preview
  """

  import Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["__livepreview" | _suffix]} = conn, _) do
    key = conn.query_string && Plug.Conn.Query.decode(conn.query_string)["key"]

    case Brando.LivePreview.get_cache(key) do
      {:ok, nil} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, [
          "LIVE PREVIEW FAILED. NO DATA SET FOR KEY #{key}"
        ])
        |> halt()

      {:ok, initial_html} ->
        #! GRAB THE COMPLETE HTML FROM ETS AND TAG ON THE JAVASCRIPT PORTION.
        #! CONSECUTIVE UPDATES WILL ONLY TARGET <MAIN>

        require Logger

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
          #{File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.js"))}
          #{File.read!(Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"))}
          #{File.read!(Application.app_dir(:brando, "priv/static/js/livepreview.js"))}
          </script>
          <style>
            html.is-updated-live-preview [data-moonwalk],
            html.is-updated-live-preview [data-moonwalk-section],
            html.is-updated-live-preview [data-moonwalk-run],
            html.is-updated-live-preview [data-moonwalk-children] > *,
            html.is-updated-live-preview [data-ll-srcset] img[data-ll-loaded] {
              opacity: 1 !important;
              visibility: visible !important;
              transform: none !important;
              transition: none !important;
              clip-path: none !important;
            }
            html.is-updated-live-preview [data-smart-video] {
              opacity: 1 !important;
              visibility: visible !important;
            }
          </style>
          """

          [page | rest] = String.split(initial_html, "</body>")
          html = page <> inject_html <> Enum.join(["</body>" | rest], "")

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, [html])
          |> halt()
        rescue
          e ->
            require Logger

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(200, [
              "LIVE PREVIEW FAILED\n\n",
              inspect(e, pretty: true)
            ])
            |> halt()
        end
    end
  end

  def call(conn, _), do: conn
end
