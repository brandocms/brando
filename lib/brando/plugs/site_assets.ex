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
  """

  import Plug.Conn, only: [halt: 1, put_resp_header: 3, send_file: 3]

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant.Frontend

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @allowed_methods do
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
