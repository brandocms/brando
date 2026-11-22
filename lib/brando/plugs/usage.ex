defmodule Brando.Plug.Usage do
  @moduledoc """
  Counts each request that reaches the endpoint on one of a site's own hosts,
  for the site's usage (`Brando.Sites.Usage`), with `tenancy_mode: :multi`.

  Place it first in the endpoint, before `Brando.Plug.SiteAssets`, the
  release's `Plug.Static` and `Brando.Plug.Media`: those answer before the
  router, and a request is counted whatever answers it (a page, a file, a
  redirect, an error).

      plug Brando.Plug.Usage

  The site and the UTC day are fixed when the request arrives: a host that is
  an active site's environment domain or redirect host counts for that site.
  The admin's host, the installation's other hosts, an inactive site's and a
  host no site has count for nobody. Nothing about the request is kept but
  the site, the day, one request and the bytes of the response body as the
  application sends it:

    * a body's length; 0 for HEAD, 304 and 204;
    * for a file, its length, or a range response's range. Brando's own file
      plugs name the file (`put_file/2`); any other file is taken to be the
      release's `Plug.Static`'s;
    * 0 for a chunked response, whose chunks are sent after it is counted.

  WebSocket and long-poll connections are dispatched before the endpoint's
  plugs, so they are not counted. The plug does one counter update and
  nothing else (`Brando.Sites.Usage.Traffic.count/3`).
  """
  @behaviour Plug

  import Plug.Conn, only: [get_resp_header: 2, put_private: 3, register_before_send: 2]

  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Sites.Usage.Traffic
  alias Brando.Tenant.Cache

  @file_key :brando_usage_file

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with :multi <- Brando.Tenant.mode(),
         site_id when is_integer(site_id) <- site_id(conn.host) do
      day = Date.utc_today()
      head? = conn.method == "HEAD"
      register_before_send(conn, &count(&1, site_id, day, head?))
    else
      _ -> conn
    end
  end

  @doc "Names the file a plug is about to send with `Plug.Conn.send_file/3`, so its bytes are counted."
  @spec put_file(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_file(conn, path), do: put_private(conn, @file_key, path)

  defp site_id(host) do
    case Cache.get_env_by_domain(host) || Cache.get_redirect(host) do
      {%{id: site_id}, _environment} -> site_id
      nil -> nil
    end
  end

  defp count(conn, site_id, day, head?) do
    Traffic.count(site_id, day, if(head?, do: 0, else: body_bytes(conn)))
    conn
  end

  defp body_bytes(%Plug.Conn{status: status}) when status in [204, 304], do: 0
  defp body_bytes(%Plug.Conn{state: :set, resp_body: body}), do: IO.iodata_length(body)
  defp body_bytes(%Plug.Conn{state: :set_file} = conn), do: file_bytes(conn)
  defp body_bytes(_chunked), do: 0

  defp file_bytes(conn) do
    case get_resp_header(conn, "content-range") do
      ["bytes " <> range | _] -> range_bytes(range)
      _ -> conn |> file_path() |> file_size()
    end
  end

  defp range_bytes(range) do
    with [span | _] <- String.split(range, "/"),
         [first, last] <- String.split(span, "-"),
         {first, ""} <- Integer.parse(first),
         {last, ""} <- Integer.parse(last) do
      last - first + 1
    else
      _ -> 0
    end
  end

  # `Plug.Static` sends a precompressed copy beside the file when it says so
  defp file_path(conn) do
    path = conn.private[@file_key] || Path.join([Capture.release_root() | conn.path_info])

    case get_resp_header(conn, "content-encoding") do
      ["gzip"] when not is_map_key(conn.private, @file_key) -> path <> ".gz"
      ["br"] when not is_map_key(conn.private, @file_key) -> path <> ".br"
      _ -> path
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _reason} -> 0
    end
  end
end
