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
  The admin's host and the installation's other hosts
  (`Brando.Tenant.InstallationHosts`), also one a site was bound to before
  that was refused, an inactive site's host and a host no site has count for
  nobody. Nothing about the request is kept but the site, the day, one
  request and the bytes of the response body as the application sends it:

    * a body's length; 0 for HEAD, 304 and 204;
    * for a file, a range response's range, or the length of the file the
      serving code names with `put_file/2`, as Brando's own do. The release's
      `Plug.Static` names nothing: its file is the one under
      `Brando.Assets.SiteAssets.Capture.release_root/0` the URL decodes to. A
      file response nobody named counts 0 bytes;
    * 0 for a chunked response, whose chunks are sent after it is counted.

  Not counted:

    * WebSocket and long-poll connections, dispatched before the endpoint's
      plugs;
    * an error raised by a plug before the router (`Plug.Parsers` answering
      400 or 413): Phoenix renders it from the request as the endpoint
      received it, without this plug's hook. A path no route matches and an
      error in a controller are counted;
    * requests answered before the counters start or after their last flush
      at shutdown: the endpoint starts before Brando's processes and stops
      after them.

  The plug does one counter update and nothing else
  (`Brando.Sites.Usage.Traffic.count/3`).
  """
  @behaviour Plug

  import Plug.Conn, only: [get_resp_header: 2, put_private: 3, register_before_send: 2]

  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Sites.Usage.Traffic
  alias Brando.Tenant.Cache
  alias Brando.Tenant.InstallationHosts

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

  @doc """
  Names the file a plug is about to send with `Plug.Conn.send_file/3` (or
  `Phoenix.Controller.send_download/3`), so its bytes are counted: the path on
  disk, as sent.
  """
  @spec put_file(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_file(conn, path), do: put_private(conn, @file_key, path)

  # A site bound to one of the installation's hosts before that was refused
  # still resolves there, but what the installation answers on it is nobody's
  defp site_id(host) do
    with {%{id: site_id}, _environment} <- Cache.get_env_by_domain(host) || Cache.get_redirect(host),
         false <- InstallationHosts.member?(host) do
      site_id
    else
      _ -> nil
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

  defp file_path(%Plug.Conn{private: %{@file_key => path}}), do: path

  # The release's `Plug.Static` names nothing. Its file responses, and no
  # one else's here, say they take ranges; it decodes the URL's segments and
  # sends a precompressed copy beside the file when it says so.
  defp file_path(conn) do
    if get_resp_header(conn, "accept-ranges") == ["bytes"] do
      path = Path.join([Capture.release_root() | Enum.map(conn.path_info, &URI.decode/1)])

      case get_resp_header(conn, "content-encoding") do
        ["gzip"] -> path <> ".gz"
        ["br"] -> path <> ".br"
        _ -> path
      end
    end
  end

  defp file_size(nil), do: 0

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _reason} -> 0
    end
  end
end
