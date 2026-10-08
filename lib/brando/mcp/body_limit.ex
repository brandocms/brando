defmodule Brando.MCP.BodyLimit do
  @moduledoc """
  An optional plug for the application's endpoint that refuses a POST to
  `/mcp` with a `Transfer-Encoding` (400), without a `Content-Length` (411),
  or with one over the MCP endpoint's `max_request_bytes` (512 KB by
  default, 413), before `Plug.Parsers` reads it.

  Put it just before `Plug.Parsers`:

      plug Brando.MCP.BodyLimit

      plug Plug.Parsers,
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

  Without it the MCP endpoint applies the same limit itself, from the same
  header, but only after the parser has read up to its own `:length`. It
  answers the same way whether the endpoint is on or off, so it tells
  nobody which.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: "POST", path_info: ["mcp" | _]} = conn, _opts) do
    case Brando.MCP.HTTP.length_check(conn, Brando.MCP.config(:max_request_bytes, 512_000)) do
      :ok -> conn
      {:error, :transfer_encoding} -> refuse(conn, 400)
      {:error, :length_required} -> refuse(conn, 411)
      {:error, :too_large} -> refuse(conn, 413)
    end
  end

  def call(conn, _opts), do: conn

  defp refuse(conn, status) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, "")
    |> halt()
  end
end
