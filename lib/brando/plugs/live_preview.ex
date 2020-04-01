defmodule Brando.Plug.LivePreview do
  @moduledoc """
  Router for live-preview
  """

  import Plug.Conn
  @behaviour Plug

  @phoenix_path Application.app_dir(:phoenix, "priv/static/phoenix.js")
  @morphdom_path Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js")
  @external_resource @phoenix_path
  @external_resource @morphdom_path

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

    inject_html = """
    <!-- BRANDO LIVE PREVIEW -->
    <script>
    #{File.read!(@phoenix_path)}
    #{File.read!(@morphdom_path)}

    /* Add live preview class to html */
    document.documentElement.classList.add('is-live-preview');
    var token = localStorage.getItem('token');
    var previewSocket = new Phoenix.Socket('/admin/socket', { params: { guardian_token: token } });
    var main = document.querySelector('main')
    var parser = new DOMParser();
    previewSocket.connect();
    var channel = previewSocket.channel("live_preview:#{key}")
    channel.on('update', function (payload) {
      var doc = parser.parseFromString(payload.html, "text/html");
      var newMain = doc.querySelector('main');
      morphdom(main, newMain, {
        onBeforeElUpdated: (a, b) => {
          if (a.isEqualNode(b)) {
            return false // Skip this entire sub-tree
          }

          return !(a.dataset.src && b.dataset.src && a.dataset.src === b.dataset.src);
        },

        onBeforeNodeAdded: (node) => {
          console.log(node);
          return node;
        },

        childrenOnly: true
      });
    });
    channel.join();
    </script>
    <style>
      html.is-live-preview [data-moonwalk],
      html.is-live-preview [data-moonwalk-section],
      html.is-live-preview [data-moonwalk-run] {
        opacity: 1 !important;
        visibility: visible !important;
        transform: none !important;
      }
    </style>
    """

    [page | rest] = String.split(initial_html, "</body>")
    html = page <> inject_html <> Enum.join(["</body>" | rest], "")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, [html])
    |> halt()
  end

  def call(conn, _), do: conn
end
