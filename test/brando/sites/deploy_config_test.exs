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

  # As a save checks it: the host is looked up too
  defp rsync(target, site_key \\ @site_key),
    do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: target}, site_key, lookup_host: true)

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

  test "a validation that is not a save looks nothing up" do
    test = self()

    put_test_env(DeployConfig,
      resolver: fn _host, _family ->
        send(test, :looked_up)
        Process.sleep(:infinity)
      end
    )

    changeset =
      DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: "deploy@loop.example.com:/srv"}, @site_key)

    assert changeset.valid?
    refute_received :looked_up
    # What needs no lookup is still refused
    refute DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: "deploy@localhost:/srv"}, @site_key).valid?
  end

  test "a deploy looks the host up afresh, and refuses one that cannot be looked up" do
    test = self()

    put_test_env(DeployConfig,
      resolver: fn host, family ->
        send(test, {:looked_up, family})
        if host == ~c"down.example.com", do: {:error, :timeout}, else: {:ok, [{93, 184, 216, 34}]}
      end
    )

    assert DeployConfig.valid_rsync_target?("deploy@up.example.com:/srv/www", @site_key)
    assert DeployConfig.valid_rsync_target?("deploy@up.example.com:/srv/www", @site_key)
    assert_received {:looked_up, :inet}
    assert_received {:looked_up, :inet}
    refute DeployConfig.valid_rsync_target?("deploy@down.example.com:/srv/www", @site_key)
  end

  describe "the default lookup, with the hosts file and name servers stubbed" do
    defp no_hosts(_host, _family), do: {:error, :nxdomain}

    defp dns_answer(answer) do
      stub = [hosts: &no_hosts/2, dns: fn _name, :in, _type, _opts, _timeout -> answer end]
      put_test_env(DeployConfig, resolver: &DeployConfig.lookup_family(&1, &2, stub))
    end

    defp a_records(name, addresses) do
      answers =
        for address <- addresses, do: :inet_dns.make_rr(domain: name, class: :in, type: :a, data: address, ttl: 300)

      {:ok, :inet_dns.make_msg(header: :inet_dns.make_header(qr: true), anlist: answers)}
    end

    test "a name the name servers say does not exist passes" do
      dns_answer({:error, {:nxdomain, :inet_dns.make_msg([])}})
      assert rsync("deploy@alias.example.com:/srv/www").valid?
      assert DeployConfig.valid_rsync_target?("deploy@alias.example.com:/srv/www", @site_key)
    end

    test "a name server that fails or refuses is a lookup that failed" do
      for code <- [:servfail, :refused] do
        dns_answer({:error, {code, :inet_dns.make_msg([])}})
        changeset = rsync("deploy@#{code}.example.com:/srv/www")
        assert {"has a host that could not be looked up. Try again in a moment", _} = changeset.errors[:target]

        assert DeployConfig.check_rsync_target("deploy@#{code}.example.com:/srv/www", @site_key) ==
                 {:error, :lookup_failed}
      end

      # No name server to ask, which `:inet_res` answers with a bare `:nxdomain`
      dns_answer({:error, :nxdomain})
      assert DeployConfig.check_rsync_target("deploy@none.example.com:/srv/www", @site_key) == {:error, :lookup_failed}
    end

    test "records pointing at this server are refused" do
      dns_answer(a_records(~c"self-dns.example.com", [own_address()]))
      assert {"must be on another server", _} = rsync("deploy@self-dns.example.com:/srv/www").errors[:target]
      assert DeployConfig.check_rsync_target("deploy@self-dns.example.com:/srv/www", @site_key) == {:error, :invalid}
    end

    test "a hosts file entry pointing at this server is refused, whatever DNS says" do
      hosts = fn
        ~c"self-hosts.example.com", :inet ->
          {:ok, {:hostent, ~c"self-hosts.example.com", [], :inet, 4, [own_address()]}}

        _host, _family ->
          {:error, :nxdomain}
      end

      nxdomain = fn _name, :in, _type, _opts, _timeout -> {:error, {:nxdomain, :inet_dns.make_msg([])}} end
      put_test_env(DeployConfig, resolver: &DeployConfig.lookup_family(&1, &2, hosts: hosts, dns: nxdomain))

      assert {"must be on another server", _} = rsync("deploy@self-hosts.example.com:/srv/www").errors[:target]
      refute DeployConfig.valid_rsync_target?("deploy@self-hosts.example.com:/srv/www", @site_key)
    end
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

  describe "a map binds each site's destinations to that site" do
    setup do
      put_test_env(:tenancy_mode, :multi)

      put_test_env(DeployConfig,
        resolver: &resolve/2,
        rsync_targets: %{
          "alpha" => ["deploy@alpha-www.example.com:/srv/www", "deploy@static.example.com:/srv/alpha/"],
          "beta" => ["deploy@beta-www.example.com:/srv/www"]
        },
        s3_targets: %{"alpha" => ["s3://alpha-www", "s3://shared-bucket/a/"], "beta" => ["s3://beta-www"]}
      )
    end

    test "for rsync" do
      assert rsync("deploy@alpha-www.example.com:/srv/www").valid?
      assert rsync("deploy@static.example.com:/srv/alpha/production").valid?
      assert DeployConfig.valid_rsync_target?("deploy@alpha-www.example.com:/srv/www", "alpha")
      assert rsync("deploy@beta-www.example.com:/srv/www", "beta").valid?

      refute rsync("deploy@beta-www.example.com:/srv/www").valid?
      refute rsync("deploy@static.example.com:/srv/alpha").valid?
      refute rsync("deploy@alpha-www.example.com:/srv/www", "beta").valid?
      refute rsync("deploy@static.example.com:/srv/alpha/production", "beta").valid?
      refute DeployConfig.valid_rsync_target?("deploy@beta-www.example.com:/srv/www", "alpha")
    end

    test "for S3" do
      assert s3("s3://alpha-www").valid?
      assert s3("s3://shared-bucket/a/production").valid?
      assert {:ok, "alpha-www", ""} = DeployConfig.s3_destination("s3://alpha-www", "alpha")
      assert {:ok, "beta-www", ""} = DeployConfig.s3_destination("s3://beta-www", "beta")

      refute s3("s3://beta-www").valid?
      refute s3("s3://alpha-www", "beta").valid?
      refute s3("s3://shared-bucket/a/production", "beta").valid?
      refute s3("s3://shared-bucket/a").valid?
      assert :error = DeployConfig.s3_destination("s3://beta-www", "alpha")
      assert :error = DeployConfig.s3_destination("s3://alpha-www", "beta")
    end

    test "a site the map does not name gets nothing" do
      for target <- ["deploy@alpha-www.example.com:/srv/www", "deploy@beta-www.example.com:/srv/www"] do
        refute rsync(target, "gamma").valid?
        refute rsync(target, nil).valid?
      end

      for target <- ["s3://alpha-www", "s3://beta-www"] do
        refute s3(target, "gamma").valid?
        refute s3(target, nil).valid?
        assert :error = DeployConfig.s3_destination(target, "gamma")
      end
    end

    test "with one site too" do
      put_test_env(:tenancy_mode, :single)

      assert s3("s3://alpha-www").valid?
      refute s3("s3://beta-www").valid?
      refute s3("s3://alpha-www", "gamma").valid?
    end

    test "a site whose value is not a list, or a key that is not a string, gets nothing" do
      put_test_env(DeployConfig,
        resolver: &resolve/2,
        s3_targets: %{"alpha" => "s3://alpha-www", beta: ["s3://beta-www"]}
      )

      refute s3("s3://alpha-www").valid?
      refute s3("s3://beta-www", "beta").valid?
    end

    test "an entry may still use the placeholder" do
      put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: %{"alpha" => ["s3://static-bucket/sites/{site_key}"]})

      assert s3("s3://static-bucket/sites/alpha").valid?
      refute s3("s3://static-bucket/sites/beta").valid?
    end

    test "map entries are not shared" do
      assert DeployConfig.shared_destinations() == []
      assert DeployConfig.overlapping_destinations() == []
      assert DeployConfig.unreadable_settings() == []
    end
  end

  test "map entries of two sites that reach one destination overlap" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: %{
        "alpha" => ["deploy@static.example.com:/srv/sites/"],
        "beta" => ["deploy@Static.example.com.:/srv/sites/beta", "deploy@static.example.com:/srv/sites-b"],
        "gamma" => ["deploy@[2001:db8::1]:/srv/www"],
        "delta" => ["deploy@[2001:db8:0::1]:/srv/www/"]
      },
      s3_targets: %{
        "alpha" => ["s3://bucket", "s3://other/a", "s3://other/{site_key}-x"],
        "beta" => ["s3://bucket/beta", "s3://other/ab", "s3://other/alpha-x/y"],
        "gamma" => ["s3://gamma-www"]
      }
    )

    assert DeployConfig.overlapping_destinations() == [
             {:rsync_targets, {"alpha", "deploy@static.example.com:/srv/sites/", :config},
              {"beta", "deploy@Static.example.com.:/srv/sites/beta", :config}},
             {:rsync_targets, {"delta", "deploy@[2001:db8:0::1]:/srv/www/", :config},
              {"gamma", "deploy@[2001:db8::1]:/srv/www", :config}},
             {:s3_targets, {"alpha", "s3://bucket", :config}, {"beta", "s3://bucket/beta", :config}},
             {:s3_targets, {"alpha", "s3://other/{site_key}-x", :config}, {"beta", "s3://other/alpha-x/y", :config}}
           ]
  end

  test "a setting no target can pass is unreadable" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: [acme: ["deploy@static.example.com:/srv/www"]],
      s3_targets: %{"acme" => "s3://acme-www"}
    )

    assert DeployConfig.unreadable_settings() == [:rsync_targets, :s3_targets]

    for value <- ["s3://acme-www", %{acme: ["s3://acme-www"]}, %{"acme" => [:atom]}, MapSet.new(["s3://acme-www"])] do
      put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: value)
      assert DeployConfig.unreadable_settings() == [:s3_targets], inspect(value)
    end
  end

  test "list entries without the placeholder are shared" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}", "deploy@static.example.com:/srv/all/", :ignored],
      s3_targets: ["s3://acme-www", "s3://{site_key}-www"]
    )

    assert DeployConfig.shared_destinations() == [
             {:rsync_targets, "deploy@static.example.com:/srv/all/"},
             {:s3_targets, "s3://acme-www"}
           ]

    put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: "s3://acme-www")
    assert DeployConfig.shared_destinations() == []
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

  # A superuser's entries on the site itself: they grant that site only,
  # beside config's, and are matched as written
  describe "a site's own allowed targets" do
    @alpha %{
      key: "alpha",
      allowed_rsync_targets: ["deploy@own.example.com:/srv/alpha", "deploy@tree.example.com:/srv/sites/"],
      allowed_s3_targets: ["s3://alpha-own", "s3://shared-own/sites/alpha", "s3://tree-own/"]
    }
    @beta %{key: "beta", allowed_rsync_targets: [], allowed_s3_targets: []}

    defp rsync_for(site, target),
      do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: target}, site, lookup_host: true)

    defp s3_for(site, target), do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :s3, target: target}, site)

    setup do
      put_test_env(:tenancy_mode, :multi)
      put_test_env(DeployConfig, resolver: &resolve/2)
    end

    test "with several sites and no config, are enough on their own" do
      assert rsync_for(@alpha, "deploy@own.example.com:/srv/alpha").valid?
      assert rsync_for(@alpha, "deploy@own.example.com:/srv/alpha/").valid?
      assert DeployConfig.valid_rsync_target?("deploy@own.example.com:/srv/alpha", @alpha)
      assert s3_for(@alpha, "s3://alpha-own").valid?
      assert {:ok, "shared-own", "sites/alpha"} = DeployConfig.s3_destination("s3://shared-own/sites/alpha", @alpha)

      refute rsync_for(@alpha, "deploy@own.example.com:/srv/alpha/sub").valid?
      refute rsync_for(@alpha, "other@own.example.com:/srv/alpha").valid?
      refute s3_for(@alpha, "s3://alpha-own/sub").valid?
    end

    test "do not allow another site" do
      refute rsync_for(@beta, "deploy@own.example.com:/srv/alpha").valid?
      refute DeployConfig.valid_rsync_target?("deploy@own.example.com:/srv/alpha", @beta)
      refute s3_for(@beta, "s3://alpha-own").valid?
      assert :error = DeployConfig.s3_destination("s3://alpha-own", @beta)

      # Nor the site's key alone, as config's checks are made
      refute DeployConfig.valid_rsync_target?("deploy@own.example.com:/srv/alpha", "alpha")
      assert :error = DeployConfig.s3_destination("s3://alpha-own", "alpha")
    end

    test "a parent ending in / allows what is under it, not the parent itself" do
      assert rsync_for(@alpha, "deploy@tree.example.com:/srv/sites/alpha").valid?
      assert s3_for(@alpha, "s3://tree-own/alpha").valid?

      refute rsync_for(@alpha, "deploy@tree.example.com:/srv/sites").valid?
      refute rsync_for(@alpha, "deploy@tree.example.com:/srv/sites/").valid?
      refute s3_for(@alpha, "s3://tree-own").valid?
      refute s3_for(@alpha, "s3://tree-own/").valid?
    end

    test "a target is still held to its form, and to another server" do
      site = %{@alpha | allowed_rsync_targets: ["deploy@loop.example.com:/srv/www", "deploy@own.example.com:/srv/"]}

      refute rsync_for(site, "deploy@loop.example.com:/srv/www").valid?
      refute rsync_for(site, "deploy@own.example.com:/srv/a/../b").valid?
      refute s3_for(site, "s3://tree-own/a/../b").valid?
    end

    test "an entry naming {site_key} is matched as written, and allows nothing" do
      site = %{@alpha | allowed_s3_targets: ["s3://static-bucket/sites/{site_key}"]}
      refute s3_for(site, "s3://static-bucket/sites/alpha").valid?
    end

    test "count beside a config list, a per-site map or an unreadable setting" do
      for config <- [
            [rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}"], s3_targets: ["s3://static/{site_key}"]],
            [
              rsync_targets: %{"alpha" => ["deploy@static.example.com:/srv/sites/alpha"]},
              s3_targets: %{"alpha" => ["s3://static/alpha"]}
            ],
            [rsync_targets: "deploy@static.example.com:/srv/sites/", s3_targets: %{alpha: ["s3://static/alpha"]}]
          ] do
        put_test_env(DeployConfig, [resolver: &resolve/2] ++ config)

        assert rsync_for(@alpha, "deploy@own.example.com:/srv/alpha").valid?, inspect(config)
        assert s3_for(@alpha, "s3://alpha-own").valid?, inspect(config)
        refute rsync_for(@beta, "deploy@own.example.com:/srv/alpha").valid?, inspect(config)
        refute s3_for(@beta, "s3://alpha-own").valid?, inspect(config)
        refute rsync_for(@alpha, "deploy@static.example.com:/srv/sites/beta").valid?, inspect(config)
      end

      # What config allows still passes
      put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: ["s3://static/{site_key}"])
      assert s3_for(@alpha, "s3://static/alpha").valid?
      assert s3_for(@beta, "s3://static/beta").valid?
    end

    test "a refused target says a superuser sets the allowed targets under Sites" do
      assert {message, _opts} = s3_for(@beta, "s3://alpha-own").errors[:target]
      assert message =~ "under Sites"

      put_test_env(:tenancy_mode, :single)
      put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: ["s3://static/{site_key}"])
      assert {"must be a destination this installation deploys to", _opts} = s3_for(@beta, "s3://other").errors[:target]
    end

    test "leave one site as it was: an unset config list allows any target of the right form" do
      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)

        assert rsync_for(@beta, "deploy@static.example.com:/srv/www").valid?
        assert s3_for(@beta, "s3://any-bucket").valid?
        refute rsync_for(@beta, "deploy@localhost:/srv/www").valid?
      end
    end
  end

  describe "an entry of a site's own allowed targets" do
    test "is a remote destination, or a parent ending in /" do
      for entry <- [
            "deploy@static.example.com:/srv/www",
            "deploy@static.example.com:/srv/sites/",
            "static.example.com:/srv/www",
            "deploy@[2001:db8::1]:/srv/www"
          ] do
        assert DeployConfig.allowed_entry_error(:rsync_targets, entry) == nil, entry
      end

      for entry <- ["s3://bucket", "s3://bucket/", "s3://bucket/sites/acme", "s3://bucket/sites/"] do
        assert DeployConfig.allowed_entry_error(:s3_targets, entry) == nil, entry
      end
    end

    test "is held to a target's form" do
      for entry <- [
            "/srv/www",
            "deploy@localhost:/srv/www",
            "deploy@127.0.0.1:/srv/www",
            "deploy@[::1]:/srv/www",
            "static.example.com::module",
            "rsync://static.example.com/srv",
            "deploy@static.example.com:/srv/../etc",
            "deploy@static.example.com:/srv/./www",
            "deploy@static.example.com:/",
            "-oProxyCommand=x@static.example.com:/srv",
            "deploy@static.example.com:relative",
            "s3://bucket/a"
          ] do
        assert is_binary(DeployConfig.allowed_entry_error(:rsync_targets, entry)), entry
      end

      for entry <- [
            "s3://",
            "s3://bucket/a/../b",
            "s3://bucket//b",
            "s3://bucket/a?b",
            "s3://bucket/a%2Fb",
            "s3://bucket/a b",
            "https://bucket/a",
            "deploy@static.example.com:/srv"
          ] do
        assert is_binary(DeployConfig.allowed_entry_error(:s3_targets, entry)), entry
      end

      assert DeployConfig.allowed_entry_error(:s3_targets, 1) == "must be text"
    end

    test "names no {site_key}: it already belongs to the site" do
      for {setting, entry} <- [
            rsync_targets: "deploy@static.example.com:/srv/sites/{site_key}",
            s3_targets: "s3://bucket/sites/{site_key}"
          ] do
        assert DeployConfig.allowed_entry_error(setting, entry) =~ "already belongs to this site"
      end
    end
  end

  test "two sites' own entries, or one beside another's map entry, overlap" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      s3_targets: %{"alpha" => ["s3://alpha-www"], "gamma" => ["s3://shared/gamma"]}
    )

    sites = [
      %{key: "alpha", allowed_rsync_targets: ["deploy@static.example.com:/srv/sites/"], allowed_s3_targets: []},
      %{
        key: "beta",
        allowed_rsync_targets: ["deploy@static.example.com:/srv/sites/beta"],
        allowed_s3_targets: ["s3://shared/"]
      },
      %{
        key: "gamma",
        allowed_rsync_targets: ["deploy@other.example.com:/srv/www"],
        allowed_s3_targets: ["s3://shared/gamma"]
      },
      %{key: nil, allowed_rsync_targets: ["deploy@static.example.com:/srv/sites/"]}
    ]

    # Each entry says where it is set: config, or the site's own list
    assert DeployConfig.overlapping_destinations(sites) == [
             {:rsync_targets, {"alpha", "deploy@static.example.com:/srv/sites/", :site},
              {"beta", "deploy@static.example.com:/srv/sites/beta", :site}},
             {:s3_targets, {"beta", "s3://shared/", :site}, {"gamma", "s3://shared/gamma", :config}},
             {:s3_targets, {"beta", "s3://shared/", :site}, {"gamma", "s3://shared/gamma", :site}}
           ]

    # One site's own entry beside its own map entry is no overlap
    assert DeployConfig.overlapping_destinations([Enum.at(sites, 2)]) == []
  end

  # A list entry with {site_key} gives each registered site its own
  # destination: another site's own entry may reach it
  test "a site's own entry that reaches what a config list gives another site overlaps" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}", "deploy@shared.example.com:/srv/all/"],
      s3_targets: ["s3://static-bucket/sites/{site_key}"]
    )

    acme = %{key: "acme", allowed_rsync_targets: [], allowed_s3_targets: []}

    beta = %{
      key: "beta",
      allowed_rsync_targets: ["deploy@static.example.com:/srv/sites/"],
      allowed_s3_targets: ["s3://static-bucket/sites/acme"]
    }

    assert DeployConfig.overlapping_destinations([acme, beta]) == [
             {:rsync_targets, {"acme", "deploy@static.example.com:/srv/sites/{site_key}", :config},
              {"beta", "deploy@static.example.com:/srv/sites/", :site}},
             {:s3_targets, {"acme", "s3://static-bucket/sites/{site_key}", :config},
              {"beta", "s3://static-bucket/sites/acme", :site}}
           ]

    # The list's own entries, one per site, stay apart
    assert DeployConfig.overlapping_destinations([acme, %{beta | allowed_rsync_targets: [], allowed_s3_targets: []}]) ==
             []
  end

  # Not a pair for each two sites: `account_bound_destinations/0` names the entry
  test "one list entry's destinations that differ only by the rsync user do not overlap" do
    put_test_env(DeployConfig, resolver: &resolve/2, rsync_targets: ["{site_key}@static.example.com:/www"])

    acme = %{key: "acme", allowed_rsync_targets: [], allowed_s3_targets: []}
    beta = %{key: "beta", allowed_rsync_targets: [], allowed_s3_targets: []}

    assert DeployConfig.overlapping_destinations([acme, beta]) == []

    # Another source that reaches the same place with another user still does
    beta = %{beta | allowed_rsync_targets: ["deploy@static.example.com:/www/"]}

    assert DeployConfig.overlapping_destinations([acme, beta]) == [
             {:rsync_targets, {"acme", "{site_key}@static.example.com:/www", :config},
              {"beta", "deploy@static.example.com:/www/", :site}}
           ]
  end

  # Unless each account is confined to its own directory, every site deploys
  # into the same one: the entry is named once, however many sites there are
  test "list entries that tell sites apart only by the rsync user are named once each" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: [
        "{site_key}@static.example.com:/www",
        "deploy@static.example.com:/srv/{site_key}",
        "{site_key}@www.example.com:/srv/{site_key}",
        "deploy@shared.example.com:/srv/"
      ],
      s3_targets: ["s3://{site_key}-www"]
    )

    assert DeployConfig.account_bound_destinations() == [{:rsync_targets, "{site_key}@static.example.com:/www"}]

    put_test_env(DeployConfig, rsync_targets: %{"acme" => ["{site_key}@static.example.com:/www"]})
    assert DeployConfig.account_bound_destinations() == []
  end

  test "two sites' entries from different sources that differ only by the user overlap" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: %{"acme" => ["acme@static.example.com:/www"], "beta" => ["beta@static.example.com:/www"]}
    )

    assert DeployConfig.overlapping_destinations() == [
             {:rsync_targets, {"acme", "acme@static.example.com:/www", :config},
              {"beta", "beta@static.example.com:/www", :config}}
           ]
  end

  test "many sites are compared by host and bucket, not in every pair" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}", "deploy@www.example.com:/www/{site_key}"],
      s3_targets: ["s3://static-bucket/sites/{site_key}", "s3://{site_key}-www"]
    )

    sites = for index <- 1..400, do: %{key: "site-#{index}", allowed_rsync_targets: [], allowed_s3_targets: []}
    sites = List.update_at(sites, 0, &%{&1 | allowed_s3_targets: ["s3://static-bucket/sites/"]})

    {microseconds, overlaps} = :timer.tc(fn -> DeployConfig.overlapping_destinations(sites) end)

    # The first site's parent holds each of the other 399's prefixes
    assert length(overlaps) == 399
    assert microseconds < 500_000
  end

  test "the entries config gives a site read as they apply to it" do
    put_test_env(DeployConfig,
      resolver: &resolve/2,
      rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}", "deploy@all.example.com:/srv/"],
      s3_targets: %{"alpha" => ["s3://alpha-www", "s3://shared/{site_key}"], "beta" => ["s3://beta-www"]}
    )

    assert DeployConfig.configured_entries(:rsync_targets, "alpha") == [
             "deploy@static.example.com:/srv/sites/alpha",
             "deploy@all.example.com:/srv/"
           ]

    assert DeployConfig.configured_entries(:s3_targets, "alpha") == ["s3://alpha-www", "s3://shared/alpha"]
    assert DeployConfig.configured_entries(:s3_targets, "gamma") == []

    put_test_env(DeployConfig, resolver: &resolve/2, s3_targets: "s3://alpha-www")
    assert DeployConfig.configured_entries(:s3_targets, "alpha") == []
    assert DeployConfig.configured_entries(:rsync_targets, "alpha") == []
  end

  test "a target is checked as a save checks it, without a lookup" do
    put_test_env(:tenancy_mode, :multi)

    put_test_env(DeployConfig,
      resolver: fn _host, _family -> flunk("looked up") end,
      s3_targets: ["s3://static/{site_key}"]
    )

    site = %{key: "alpha", allowed_rsync_targets: ["deploy@own.example.com:/srv/alpha"], allowed_s3_targets: []}

    assert DeployConfig.allowed_target?(:rsync, "deploy@own.example.com:/srv/alpha", site)
    assert DeployConfig.allowed_target?(:s3, "s3://static/alpha", site)
    refute DeployConfig.allowed_target?(:s3, "s3://static/beta", site)
    refute DeployConfig.allowed_target?(:rsync, "deploy@own.example.com:/srv/beta", site)
    refute DeployConfig.allowed_target?(:rsync, nil, site)
    refute DeployConfig.allowed_target?(:local, "x", site)
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
