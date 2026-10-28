defmodule Brando.Plug.SiteAssets do
  @moduledoc """
  Serves files from the active persistent frontend asset set, or from a set a
  shared preview has pinned.

  Place this plug before the application's release `Plug.Static`. Cached
  `MapSet`s reject misses without touching the filesystem; misses fall through
  unchanged so release assets remain the fallback. Pinned sets only serve the
  content-addressed files their Vite manifest lists, at their original URLs,
  so a preview rendered against an older build keeps loading its stylesheets,
  chunks, and fonts after the active set or release changes.

  Its files, and those of the plugs after it that answer before the router
  (the release's `Plug.Static`, `Brando.Plug.Media`), are sent with
  `Access-Control-Allow-Origin: *`. Live previews and shared preview snapshots
  are sandboxed (`Brando.Plug.LivePreview.sandbox_policy/0`), so their origin
  is opaque and their module scripts, fonts and other `crossorigin` requests
  are cross-origin: without the header, the browser refuses them. The files
  are public and the header allows no credentials, so it exposes nothing a
  request without cookies would not get. Admin paths, preview pages and
  everything the router answers are left alone.
  """

  import Plug.Conn, only: [get_resp_header: 2, halt: 1, put_resp_header: 3, register_before_send: 2, send_file: 3]

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant.Frontend

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @allowed_methods do
    conn = allow_any_origin(conn)

    with relative_path when is_binary(relative_path) <- relative_path(conn.path_info),
         {:ok, site} <- request_scope(conn),
         file when is_binary(file) <- SiteAssets.serve_path(site, relative_path) do
      conn
      |> put_resp_header("content-type", MIME.from_path(relative_path))
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_file(200, file)
      |> halt()
    else
      _miss -> conn
    end
  end

  def call(conn, _opts), do: conn

  @no_cors_roots ["admin", "__livepreview"]
  @static_statuses [200, 206, 304]

  defp allow_any_origin(%Plug.Conn{path_info: [root | _]} = conn) when root in @no_cors_roots, do: conn
  defp allow_any_origin(conn), do: register_before_send(conn, &put_allow_origin/1)

  # Only a file a plug before the router sent: the router marks every
  # connection it handles
  defp put_allow_origin(conn) do
    if conn.status in @static_statuses and not Map.has_key?(conn.private, :phoenix_router) and
         get_resp_header(conn, "access-control-allow-origin") == [] do
      put_resp_header(conn, "access-control-allow-origin", "*")
    else
      conn
    end
  end

  defp request_scope(conn) do
    case Brando.Tenant.mode() do
      :multi ->
        case Frontend.resolve(conn.host) do
          {site, _environment} -> {:ok, site}
          nil -> :error
        end

      _standalone ->
        {:ok, nil}
    end
  end

  defp relative_path(path_info) do
    decoded = Enum.map(path_info, &URI.decode/1)

    if decoded == [] or Enum.any?(decoded, &(&1 in ["", ".", ".."] or String.contains?(&1, ["/", "\\"]))) do
      nil
    else
      Path.join(decoded)
    end
  end
end
