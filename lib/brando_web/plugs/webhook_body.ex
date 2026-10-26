defmodule BrandoWeb.Plugs.WebhookBody do
  @moduledoc """
  Reads a webhook's raw body, up to a limit, before its signature is checked.

  The video webhook plugs sit before `Plug.Parsers`, so no parser limit
  applies, and anyone can post to them. A body over the limit is refused with
  413 and never buffered whole.
  """
  import Plug.Conn

  @max_body 1_048_576

  @doc """
  `{:ok, body, conn}`, or a halted conn answering 413 for a body over
  `max_body` bytes and 400 for one that could not be read.
  """
  @spec read(Plug.Conn.t(), pos_integer()) :: {:ok, binary, Plug.Conn.t()} | {:halted, Plug.Conn.t()}
  def read(conn, max_body \\ @max_body) do
    case read_body(conn, length: max_body, read_length: 64_000) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, conn} -> {:halted, respond(conn, 413, "Request body too large")}
      {:error, _reason} -> {:halted, respond(conn, 400, "Request body could not be read")}
    end
  end

  defp respond(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
