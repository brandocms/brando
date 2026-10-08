defmodule E2eProjectWeb.RawBodyReader do
  @moduledoc false
  # Keeps the raw request body of the E2E webhook receiver
  # (`/e2e/webhook-receiver`), so the tests can check the signature over the
  # exact bytes, as a real receiver must. Other requests are read as usual.

  def read_body(%Plug.Conn{request_path: "/e2e/webhook-receiver/" <> _} = conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      {:ok, body, Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
