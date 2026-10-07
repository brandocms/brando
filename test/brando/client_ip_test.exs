defmodule Brando.ClientIPTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.ClientIP

  defp conn(peer, forwarded) do
    conn = %{Plug.Test.conn(:post, "/admin/login") | remote_ip: peer}
    %{conn | req_headers: conn.req_headers ++ Enum.map(List.wrap(forwarded), &{"x-forwarded-for", &1})}
  end

  test "without a proxy, the peer is the client, whatever the header says" do
    put_test_env(:trusted_proxies, ["10.0.0.0/8"])
    assert ClientIP.from_conn(conn({203, 0, 113, 9}, "198.51.100.1")) == {203, 0, 113, 9}
  end

  test "behind a trusted proxy, the right-most untrusted address is the client" do
    put_test_env(:trusted_proxies, ["10.0.0.0/8", "127.0.0.1"])

    assert ClientIP.from_conn(conn({10, 0, 0, 2}, "198.51.100.7")) == {198, 51, 100, 7}
    # A client cannot pick its address by sending the header itself: what it
    # sent is left of the address the proxy saw
    assert ClientIP.from_conn(conn({10, 0, 0, 2}, "1.2.3.4, 198.51.100.7")) == {198, 51, 100, 7}
    # Several trusted hops
    assert ClientIP.from_conn(conn({127, 0, 0, 1}, "198.51.100.7, 10.1.1.1")) == {198, 51, 100, 7}
    # Several headers count as one list
    assert ClientIP.from_conn(conn({10, 0, 0, 2}, ["198.51.100.7", "10.9.9.9"])) == {198, 51, 100, 7}
    # Nothing forwarded: the proxy itself
    assert ClientIP.from_conn(conn({10, 0, 0, 2}, [])) == {10, 0, 0, 2}
    # Garbage stops at the last trusted hop
    assert ClientIP.from_conn(conn({10, 0, 0, 2}, "nonsense")) == {10, 0, 0, 2}
  end

  test "an untrusted proxy's header is ignored" do
    put_test_env(:trusted_proxies, ["10.0.0.0/8"])
    assert ClientIP.from_conn(conn({192, 168, 1, 5}, "198.51.100.7")) == {192, 168, 1, 5}
  end

  test "loopback is trusted by default, and [] trusts nothing" do
    put_test_env(:trusted_proxies, nil)
    assert ClientIP.from_conn(conn({127, 0, 0, 1}, "198.51.100.7")) == {198, 51, 100, 7}

    put_test_env(:trusted_proxies, [])
    assert ClientIP.from_conn(conn({127, 0, 0, 1}, "198.51.100.7")) == {127, 0, 0, 1}
  end

  test "IPv6, and IPv4 carried in IPv6" do
    put_test_env(:trusted_proxies, ["fd00::/8"])
    assert ClientIP.from_conn(conn({0xFD00, 0, 0, 0, 0, 0, 0, 1}, "2001:db8::5")) == {0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}

    assert ClientIP.from_conn(conn({0xFD00, 0, 0, 0, 0, 0, 0, 1}, "[2001:db8::5]:443")) ==
             {0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}

    put_test_env(:trusted_proxies, ["127.0.0.1"])
    assert ClientIP.from_conn(conn({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}, "198.51.100.7")) == {198, 51, 100, 7}
  end

  test "a LiveView's connect info resolves the same way" do
    put_test_env(:trusted_proxies, ["10.0.0.0/8"])

    info = %{peer_data: %{address: {10, 0, 0, 2}}, x_headers: [{"x-forwarded-for", "198.51.100.7"}]}
    assert ClientIP.from_connect_info(info) == {198, 51, 100, 7}
    assert ClientIP.from_connect_info(%{}) == nil
  end

  test "CIDR ranges" do
    assert {:ok, {{10, 0, 0, 0}, 8}} = ClientIP.parse_range("10.0.0.0/8")
    assert {:ok, {{10, 1, 2, 3}, 32}} = ClientIP.parse_range("10.1.2.3")
    assert :error = ClientIP.parse_range("10.0.0.0/33")
    assert :error = ClientIP.parse_range("nonsense")
  end
end
