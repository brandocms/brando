defmodule Brando.Plug.HealthTest do
  # The health check answers only the server itself. Behind a reverse proxy on
  # the same server every request arrives from 127.0.0.1, so the proxy's
  # X-Forwarded-For decides (audit report, section 6).
  use Brando.ConnCase, async: true

  defp health(remote_ip, headers \\ []) do
    conn = %{Plug.Test.conn(:get, "/health") | remote_ip: remote_ip}

    headers
    |> Enum.reduce(conn, fn {name, value}, conn -> Plug.Conn.put_req_header(conn, name, value) end)
    |> Brando.Plug.Health.call([])
  end

  test "answers a request from the server itself" do
    assert health({127, 0, 0, 1}).status in [200, 503]
    assert health({0, 0, 0, 0, 0, 0, 0, 1}).status in [200, 503]
  end

  test "refuses a visitor forwarded by a proxy on the server" do
    assert health({127, 0, 0, 1}, [{"x-forwarded-for", "203.0.113.5"}]).status == 403
  end

  test "refuses a remote client, whatever it forwards" do
    assert health({203, 0, 113, 5}).status == 403
    assert health({203, 0, 113, 5}, [{"x-forwarded-for", "127.0.0.1"}]).status == 403
  end
end
