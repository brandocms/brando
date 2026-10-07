defmodule Brando.Webhooks.URLGuardTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Webhooks.URLGuard

  defp ip(string) do
    {:ok, address} = :inet.parse_strict_address(String.to_charlist(string))
    address
  end

  describe "blocked?/1" do
    test "refuses every private, local and special IPv4 range" do
      for address <- ~w(
            0.0.0.0 0.1.2.3
            10.0.0.1 10.255.255.255
            100.64.0.1 100.127.255.254
            127.0.0.1 127.8.9.10
            169.254.169.254 169.254.0.1
            172.16.0.1 172.31.255.255
            192.0.0.8 192.0.2.10
            192.168.0.1 192.168.255.255
            198.18.0.1 198.19.255.255
            198.51.100.7 203.0.113.9
            224.0.0.1 239.255.255.250
            240.0.0.1 255.255.255.255
          ) do
        assert URLGuard.blocked?(ip(address)), "#{address} should be blocked"
      end
    end

    test "allows public IPv4 next to the blocked ranges" do
      for address <- ~w(1.1.1.1 8.8.8.8 93.184.216.34 100.63.255.255 100.128.0.1 172.15.255.255 172.32.0.1
                         169.253.1.1 192.167.1.1 198.17.1.1 198.20.0.1 223.255.255.254) do
        refute URLGuard.blocked?(ip(address)), "#{address} should be allowed"
      end
    end

    test "refuses loopback, link-local, unique local, multicast and the IPv6 forms of private IPv4" do
      for address <- ~w(
            :: ::1 ::2
            fe80::1 febf::1
            fec0::1
            fc00::1 fd12:3456:789a::1
            ff02::1 ff05::2
            ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254
            ::127.0.0.1
            64:ff9b::a9fe:a9fe
            2002:c0a8:0101::1
            2001:db8::1
            100::1
          ) do
        assert URLGuard.blocked?(ip(address)), "#{address} should be blocked"
      end
    end

    test "allows public IPv6" do
      for address <- ~w(2606:4700:4700::1111 2a00:1450:4010:c05::64 ::ffff:93.184.216.34 2002:5db8:d822::1) do
        refute URLGuard.blocked?(ip(address)), "#{address} should be allowed"
      end
    end
  end

  describe "resolve/2" do
    test "an https URL on a public host" do
      assert {:ok, target} = URLGuard.resolve("https://hooks.example.com/brando?x=1")
      assert target.scheme == :https
      assert target.host == "hooks.example.com"
      assert target.port == 443
      assert target.path == "/brando?x=1"
      assert target.address == {93, 184, 216, 34}
    end

    test "only http and https, and https outside development" do
      assert {:error, :https_required} = URLGuard.resolve("http://hooks.example.com/")
      assert {:error, :scheme_not_allowed} = URLGuard.resolve("ftp://hooks.example.com/")
      assert {:error, :invalid_url} = URLGuard.resolve("file:///etc/passwd")
      assert {:error, :scheme_not_allowed} = URLGuard.resolve("gopher://hooks.example.com/")
      assert {:error, :invalid_url} = URLGuard.resolve("hooks.example.com/brando")
      assert {:error, :invalid_url} = URLGuard.resolve("not a url")
    end

    test "no credentials in the URL" do
      assert {:error, :credentials_in_url} = URLGuard.resolve("https://user:pass@hooks.example.com/")
    end

    test "a host that resolves to a private address, or to one among public ones" do
      assert {:error, :private_address} = URLGuard.resolve("https://db.internal.test/")
      assert {:error, :private_address} = URLGuard.resolve("https://mixed.test/")
      assert {:error, :unresolvable} = URLGuard.resolve("https://nowhere.test/")
    end

    test "IP literals are checked without a lookup" do
      assert {:error, :private_address} = URLGuard.resolve("https://127.0.0.1/")
      assert {:error, :private_address} = URLGuard.resolve("https://169.254.169.254/latest/meta-data/")
      assert {:error, :private_address} = URLGuard.resolve("https://[::1]:8443/")
      assert {:error, :private_address} = URLGuard.resolve("https://[::ffff:10.0.0.1]/")
      assert {:error, :private_address} = URLGuard.resolve("https://0.0.0.0/")
      assert {:ok, %{address: {1, 1, 1, 1}}} = URLGuard.resolve("https://1.1.1.1/")
    end

    test "a host that resolves elsewhere since it was saved is refused when it is called (DNS rebinding)" do
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
      assert {:ok, _} = URLGuard.resolve("https://rebind.test/hook")

      Brando.WebhookTestResolver.rebind({127, 0, 0, 1})
      assert {:error, :private_address} = URLGuard.resolve("https://rebind.test/hook")

      Brando.WebhookTestResolver.rebind({169, 254, 169, 254})
      assert {:error, :private_address} = URLGuard.resolve("https://rebind.test/hook")
    after
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
    end

    test "a resolver can be passed in" do
      assert {:error, :private_address} =
               URLGuard.resolve("https://hooks.example.com/", resolver: fn _ -> {:ok, [{192, 168, 0, 2}]} end)
    end

    test "the localhost override allows http and loopback, and nothing else private" do
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})

      assert {:ok, %{scheme: :http, address: {127, 0, 0, 1}}} = URLGuard.resolve("http://127.0.0.1:4000/hook")
      assert {:ok, %{address: {0, 0, 0, 0, 0, 0, 0, 1}}} = URLGuard.resolve("http://[::1]:4000/hook")
      assert {:error, :private_address} = URLGuard.resolve("http://db.internal.test/")
      assert {:error, :private_address} = URLGuard.resolve("http://169.254.169.254/")
    end
  end
end
