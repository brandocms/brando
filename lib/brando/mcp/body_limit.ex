defmodule Brando.MCP.BodyLimit do
  @moduledoc """
  An optional plug for the application's endpoint that refuses a POST to
  `/mcp` with a `Transfer-Encoding` (400), without a `Content-Length` (411),
  or with one over the MCP endpoint's `max_request_bytes` (512 KB by
  default, 413), before `Plug.Parsers` reads it. It refuses a PUT to an
  upload URL (`Brando.MCP.Uploads`) with a JSON or form `Content-Type`
  (415) for the same reason: an upload's bytes are read, and held to the
  image config's size limit, by the upload URL alone.

  Put it just before `Plug.Parsers`:

      plug Brando.MCP.BodyLimit

      plug Plug.Parsers,
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

  Without it the MCP endpoint applies the same limit itself, from the same
  header, but only after the parser has read up to its own `:length`. It
  answers the same way whether the endpoint is on or off, so it tells
  nobody which. With `tenancy_mode: :multi` it passes every request through
  on a host that does not serve MCP (`BrandoAdmin.AdminHost`), where `/mcp`
  answers as a missing path.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: "POST", path_info: ["mcp" | _]} = conn, _opts) do
    if BrandoAdmin.AdminHost.serves_admin?(conn) do
      case Brando.MCP.HTTP.length_check(conn, Brando.MCP.config(:max_request_bytes, 512_000)) do
        :ok -> conn
        {:error, :transfer_encoding} -> refuse(conn, 400)
        {:error, :length_required} -> refuse(conn, 411)
        {:error, :too_large} -> refuse(conn, 413)
      end
    else
      conn
    end
  end

  # An upload's bytes (`Brando.MCP.Uploads`) are never JSON or a form: the
  # parsers must not read them, as they would up to their own limits. The
  # upload itself is checked against the image config's size limit as it
  # arrives.
  def call(%{method: "PUT", path_info: ["mcp" | rest]} = conn, _opts) do
    if upload_path?(rest) and BrandoAdmin.AdminHost.serves_admin?(conn) and Brando.MCP.Uploads.parsed_type?(conn),
      do: refuse(conn, 415),
      else: conn
  end

  def call(conn, _opts), do: conn

  defp upload_path?(rest), do: match?(["uploads", _, _], Enum.take(rest, -3))

  defp refuse(conn, status) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, "")
    |> halt()
  end
end
