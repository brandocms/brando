defmodule Brando.Plug.IndexNow do
  @moduledoc """
  Serves the site's IndexNow key file at `/<key>.txt` (`Brando.IndexNow`),
  while IndexNow is on. Add it to the endpoint, before the router:

      plug Brando.Plug.IndexNow
      plug MyAppWeb.Router

  Only a root path shaped like a key (32 hexadecimal characters and `.txt`)
  is looked at, so other requests cost nothing. The site and environment are
  resolved from the host, as `Brando.Plug.Tenant` does.
  """
  @behaviour Plug

  import Plug.Conn

  @key_file ~r/^([a-f0-9]{32})\.txt$/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: [file]} = conn, _opts) when method in ["GET", "HEAD"] do
    with [_, key] <- Regex.run(@key_file, file),
         %Plug.Conn{halted: false} = conn <- Brando.Plug.Tenant.call(conn, []),
         key when is_binary(key) <- Brando.IndexNow.key_file(key) do
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, key)
      |> halt()
    else
      %Plug.Conn{halted: true} = halted -> halted
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn
end
