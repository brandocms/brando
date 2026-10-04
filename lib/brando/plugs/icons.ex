defmodule Brando.Plug.Icons do
  @moduledoc """
  Serves the Lucide icon stylesheet (`Brando.Icons.stylesheet/0`).

  `Brando.Router.admin_routes/3` forwards `/__brando/icons` here, outside the
  admin path and its authentication, because the login page and front-end edit
  mode render icons too. The file name carries a content hash, so responses are
  cached forever. Any other file name is a 404.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method, path_info: [file]} = conn, _opts) when method in ~w(GET HEAD) do
    if file == Brando.Icons.stylesheet_file() do
      conn
      |> put_resp_header("content-type", "text/css")
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("vary", "accept-encoding")
      |> send_stylesheet()
      |> halt()
    else
      not_found(conn)
    end
  end

  def call(conn, _opts), do: not_found(conn)

  # Gzipped at compile time: about 800 KB of CSS goes over the wire as 90 KB.
  defp send_stylesheet(conn) do
    if accepts_gzip?(conn) do
      conn
      |> put_resp_header("content-encoding", "gzip")
      |> send_resp(200, Brando.Icons.stylesheet_gzip())
    else
      send_resp(conn, 200, Brando.Icons.stylesheet())
    end
  end

  defp accepts_gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.any?(&String.contains?(&1, "gzip"))
  end

  defp not_found(conn), do: conn |> send_resp(404, "Not found") |> halt()
end
