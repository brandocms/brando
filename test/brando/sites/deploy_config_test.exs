defmodule Brando.Sites.DeployConfigTest do
  # An rsync deploy mirrors the build with --delete, as the server's user and
  # SSH identity, to the target anyone who may deploy can set. It takes only
  # a remote [user@]host:/absolute/path on another server, among the
  # destinations the operator lists if they do.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Sites.DeployConfig

  defp rsync(target), do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: target})

  # Names resolve here, not through DNS: two reach this server
  defp resolve(~c"loop.example.com", :inet), do: {:ok, [{127, 0, 1, 1}]}

  defp resolve(~c"self.example.com", :inet), do: {:ok, [own_address()]}

  defp resolve(_host, _family), do: {:error, :nxdomain}

  # One of this server's addresses that is not loopback (or loopback when
  # it has none, which the loopback rule refuses anyway)
  defp own_address do
    {:ok, interfaces} = :inet.getifaddrs()
    own = for {_name, opts} <- interfaces, {:addr, {_, _, _, _} = address} <- opts, do: address
    Enum.find(own, hd(own), &(elem(&1, 0) != 127))
  end

  setup do
    put_test_env(DeployConfig, resolver: &resolve/2)
  end

  test "this server's own address, however written, is no target" do
    {a, b, c, d} = own_address()
    refute rsync("deploy@#{a}.#{b}.#{c}.#{d}:/srv/other-site").valid?
    refute rsync("deploy@[::ffff:#{a}.#{b}.#{c}.#{d}]:/srv/other-site").valid?
  end

  test "a remote destination is a valid rsync target" do
    for target <- [
          "deploy@example.com:/srv/www",
          "example.com:/srv/www/",
          "web_1@static-01.example.com:/var/www/site.example.com/public",
          "deploy@10.0.0.5:/srv/www",
          "deploy@[2001:db8::1]:/srv/www",
          "deploy@localhost-cdn.example.com:/srv/www"
        ] do
      assert rsync(target).valid?, target
      assert DeployConfig.valid_rsync_target?(target)
    end
  end

  test "local paths, options and other rsync syntax are refused" do
    for target <- [
          # The audit's three: a local directory, an rsync option, an ssh option as the host
          "/tmp/local-dest",
          "--log-file=/tmp/marker.log",
          "u@-oProxyCommand=true:/srv/www",
          "-oProxyCommand=true:/srv/www",
          "-e@example.com:/srv/www",
          "relative/dir",
          "./here",
          "example.com:relative",
          "example.com::module",
          "rsync://example.com/module",
          "deploy@example.com:/srv/www; touch /tmp/x",
          "deploy@example.com:/srv/$(id)",
          "deploy@example.com:/srv/www\n",
          "deploy@example.com:/srv/w w",
          "user@name@example.com:/srv",
          # This server under other names, and paths leaving the one given
          "deploy@localhost:/srv/site-b",
          "deploy@app.localhost:/srv",
          "deploy@127.0.0.1:/srv",
          "deploy@127.1:/srv",
          "deploy@0:/srv",
          "deploy@2130706433:/srv",
          "deploy@0177.0.0.1:/srv",
          "deploy@[::1]:/srv",
          "deploy@[::ffff:127.0.0.1]:/srv",
          "deploy@example.com:/srv/www/../site-b",
          "deploy@example.com:/..",
          "deploy@example.com:/srv/www/.",
          "deploy@example.com:/srv//www",
          "deploy@example.com:/srv/www//",
          "deploy@example.com:/",
          "deploy@localhost.:/srv",
          "deploy@app.localhost.:/srv",
          "deploy@localhost4:/srv",
          "deploy@localhost.localdomain:/srv",
          "deploy@ip6-localhost:/srv",
          "deploy@0x0:/srv",
          "deploy@0x7f000001:/srv",
          "deploy@127.0.0.1.:/srv",
          # Names that resolve to this server
          "deploy@loop.example.com:/srv",
          "deploy@self.example.com:/srv"
        ] do
      refute rsync(target).valid?, inspect(target)
      refute DeployConfig.valid_rsync_target?(target)
    end
  end

  test "an operator's list limits where rsync deploys go" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/", "web@cdn.example.com:/srv/www", :ignored]
    )

    assert rsync("deploy@static.example.com:/srv/sites/acme").valid?
    assert rsync("deploy@Static.Example.com:/srv/sites/acme/").valid?
    assert rsync("web@cdn.example.com:/srv/www").valid?
    assert rsync("web@cdn.example.com:/srv/www/").valid?
    # The directory that holds the others, and ways of naming it
    refute rsync("deploy@static.example.com:/srv/sites/").valid?
    refute rsync("deploy@static.example.com:/srv/sites").valid?
    refute rsync("deploy@static.example.com:/srv/sites/.").valid?
    refute rsync("deploy@static.example.com:/srv/sites//").valid?
    refute rsync("root@static.example.com:/srv/sites/acme").valid?
    refute rsync("deploy@static.example.com:/home/deploy").valid?
    refute rsync("web@cdn.example.com:/srv/www-other").valid?
    refute rsync("web@cdn.example.com:/srv/www/sub").valid?
    refute rsync("deploy@other.example.com:/srv/sites/acme").valid?
  end

  test "a list that is not a list allows nothing" do
    put_test_env(DeployConfig, resolver: &resolve/2, rsync_targets: "deploy@static.example.com:/srv/sites/")
    refute rsync("deploy@static.example.com:/srv/sites/acme").valid?
  end
end
