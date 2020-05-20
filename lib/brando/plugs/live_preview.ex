defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Router for live-preview
  """

  import Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["__livepreview" | _suffix]} = conn, _) do
    key = conn.query_string && Plug.Conn.Query.decode(conn.query_string)["key"]

    {:ok, initial_html} =
      case Brando.LivePreview.get_cache(key) do
        {:ok, nil} ->
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, [
            "LIVE PREVIEW FAILED. NO DATA SET FOR KEY #{key}"
          ])
          |> halt()

        {:ok, initial_html} ->
          {:ok, initial_html}
      end

    #! GRAB THE COMPLETE HTML FROM ETS AND TAG ON THE JAVASCRIPT PORTION.
    #! CONSECUTIVE UPDATES WILL ONLY TARGET <MAIN>

    try do
      inject_html = """
      <!-- BRANDO LIVE PREVIEW -->
      <script>
      var livePreviewKey = '#{key}';
      #{File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.js"))}
      #{File.read!(Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"))}
      #{File.read!(Application.app_dir(:brando, "priv/static/js/livepreview.js"))}
      </script>
      <style>
      html.is-live-preview [data-moonwalk],
      html.is-live-preview [data-moonwalk-section],
        html.is-live-preview [data-moonwalk-run] {
          opacity: 1 !important;
          visibility: visible !important;
          transform: none !important;
          clip-path: none !important;
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
        Logger.error(inspect(e, pretty: true))
    end
  end

  def call(conn, _), do: conn
end
