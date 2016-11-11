defmodule Brando.Plug.AdminHostnameTest do
  use ExUnit.Case
  use Plug.Test
  import Brando.Plug.AdminHostname

  test "admin_hostname" do
    mock_conn = %Plug.Conn{host: "localhost"}
    assert admin_hostname(mock_conn, nil) == mock_conn

    mock_conn = %Plug.Conn{host: "admin.test.com"}
    assert admin_hostname(mock_conn, nil) == mock_conn

    conn =
      :get
      |> conn("/admin", [])
      |> Map.put(:host, "www.test.com")
      |> admin_hostname(nil)

    assert Phoenix.ConnTest.redirected_to(conn, 302) =~ "/"
  end
end
