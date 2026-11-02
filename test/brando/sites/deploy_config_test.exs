defmodule Brando.Sites.DeployConfigTest do
  # An rsync deploy mirrors the build with --delete, as the server's user and
  # SSH identity, to the target anyone who may deploy can set. It takes only
  # a remote [user@]host:/absolute/path on another server, among the
  # destinations the operator lists for that site. An S3 deploy empties its
  # target the same way, under the application's one set of credentials.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Sites.DeployConfig

  @site_key "alpha"

  defp rsync(target, site_key \\ @site_key),
    do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: target}, site_key)

  defp s3(target, site_key \\ @site_key),
    do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :s3, target: target}, site_key)

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
      assert DeployConfig.valid_rsync_target?(target, @site_key)
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
      refute DeployConfig.valid_rsync_target?(target, @site_key)
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
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: "deploy@static.example.com:/srv/sites/",
      s3_targets: "s3://static-bucket/"
    )

    refute rsync("deploy@static.example.com:/srv/sites/acme").valid?
    refute s3("s3://static-bucket/acme").valid?
  end

  describe "{site_key} binds a listed destination to one site" do
    setup do
      put_test_env(DeployConfig,
        resolver: &resolve/2,
        rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}", "deploy@{site_key}.example.com:/srv/www/"],
        s3_targets: ["s3://static-bucket/sites/{site_key}", "s3://{site_key}-static", "s3://{site_key}-tree/"]
      )
    end

    test "for rsync" do
      assert rsync("deploy@static.example.com:/srv/sites/alpha").valid?
      assert rsync("deploy@static.example.com:/srv/sites/alpha/").valid?
      assert rsync("deploy@alpha.example.com:/srv/www/production").valid?
      assert DeployConfig.valid_rsync_target?("deploy@static.example.com:/srv/sites/alpha", "alpha")

      refute rsync("deploy@static.example.com:/srv/sites/beta").valid?
      refute rsync("deploy@static.example.com:/srv/sites/alpha-beta").valid?
      refute rsync("deploy@static.example.com:/srv/sites/alpha/sub").valid?
      refute rsync("deploy@beta.example.com:/srv/www/production").valid?
      refute rsync("deploy@static.example.com:/srv/sites/alpha", "beta").valid?
      refute DeployConfig.valid_rsync_target?("deploy@static.example.com:/srv/sites/beta", "alpha")
    end

    test "for S3" do
      assert s3("s3://static-bucket/sites/alpha").valid?
      assert s3("s3://static-bucket/sites/alpha/").valid?
      assert s3("s3://alpha-static").valid?
      assert s3("s3://alpha-static/").valid?
      assert s3("s3://alpha-tree/production").valid?

      assert {:ok, "static-bucket", "sites/alpha"} =
               DeployConfig.s3_destination("s3://static-bucket/sites/alpha/", "alpha")

      assert {:ok, "alpha-static", ""} = DeployConfig.s3_destination("s3://alpha-static", "alpha")

      refute s3("s3://static-bucket/sites/beta").valid?
      refute s3("s3://static-bucket/sites/alpha-beta").valid?
      refute s3("s3://static-bucket/sites/alpha/sub").valid?
      refute s3("s3://beta-static").valid?
      refute s3("s3://alpha-static/sub").valid?
      refute s3("s3://static-bucket/sites/alpha", "beta").valid?
      assert :error = DeployConfig.s3_destination("s3://static-bucket/sites/beta", "alpha")
      assert :error = DeployConfig.s3_destination(nil, "alpha")
    end

    test "a bucket with no prefix passes only an entry naming it exactly" do
      refute s3("s3://static-bucket").valid?
      refute s3("s3://static-bucket/").valid?
      refute s3("s3://alpha-tree").valid?
      refute s3("s3://alpha-tree/").valid?
    end

    test "a save without a site key matches no placeholder" do
      refute rsync("deploy@static.example.com:/srv/sites/{site_key}", nil).valid?
      refute s3("s3://static-bucket/sites/{site_key}", nil).valid?
      refute s3("s3://static-bucket/sites/alpha", nil).valid?
    end
  end

  test "an entry without the placeholder grants every site" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/"],
      s3_targets: ["s3://static-bucket/sites/", "s3://whole-bucket"]
    )

    for site_key <- ["alpha", "beta"] do
      assert rsync("deploy@static.example.com:/srv/sites/gamma", site_key).valid?
      assert s3("s3://static-bucket/sites/gamma", site_key).valid?
      assert s3("s3://whole-bucket", site_key).valid?
    end

    refute s3("s3://static-bucket/sites").valid?
    refute s3("s3://static-bucket/sites/").valid?
    refute s3("s3://static-bucket/sites-other/gamma").valid?
    refute s3("s3://static-bucket").valid?
  end

  test "an S3 target reaches S3 as written" do
    for target <- [
          "not-an-s3-target",
          "s3://",
          "s3:///prefix",
          "s3://-bucket/prefix",
          "s3://user@bucket/prefix",
          "s3://bucket:9000/prefix",
          "s3://bucket/a/../b",
          "s3://bucket/./b",
          "s3://bucket//b",
          "s3://bucket//",
          "s3://bucket/a//",
          "s3://bucket/a?b",
          "s3://bucket/a#b",
          "s3://bucket/a%2Fb",
          "s3://bucket/a b",
          "s3://bucket/{site_key}",
          "https://bucket/a"
        ] do
      refute s3(target).valid?, target
      assert :error = DeployConfig.s3_destination(target, @site_key)
    end
  end

  describe "with no list" do
    setup do
      put_test_env(DeployConfig, resolver: &resolve/2)
    end

    test "one site keeps any target of the right form" do
      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)

        assert rsync("deploy@static.example.com:/srv/www").valid?
        assert s3("s3://any-bucket/prefix").valid?
        assert s3("s3://any-bucket").valid?
        assert {:ok, "any-bucket", ""} = DeployConfig.s3_destination("s3://any-bucket", @site_key)
      end
    end

    test "several sites have no destination until the operator lists them" do
      put_test_env(:tenancy_mode, :multi)

      refute rsync("deploy@static.example.com:/srv/www").valid?
      refute DeployConfig.valid_rsync_target?("deploy@static.example.com:/srv/www", @site_key)
      refute s3("s3://any-bucket/prefix").valid?
      assert :error = DeployConfig.s3_destination("s3://any-bucket/prefix", @site_key)

      # Each strategy has its own list
      put_test_env(DeployConfig, resolver: &resolve/2, rsync_targets: ["deploy@static.example.com:/srv/www"])
      assert rsync("deploy@static.example.com:/srv/www").valid?
      refute s3("s3://any-bucket/prefix").valid?
    end

    test "a list set with one site binds too" do
      put_test_env(:tenancy_mode, :single)
      put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: ["s3://static-bucket/sites/{site_key}"])

      assert s3("s3://static-bucket/sites/alpha").valid?
      refute s3("s3://static-bucket").valid?
      refute s3("s3://other-bucket/sites/alpha").valid?
      # The other strategy's list stays unset
      assert rsync("deploy@static.example.com:/srv/www").valid?
    end
  end
end
