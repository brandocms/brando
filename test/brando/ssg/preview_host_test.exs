defmodule Brando.SSG.PreviewHostTest do
  # The preview host pattern is application config and the tenant cache is
  # the node's: one test at a time
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Brando.Exception.ConfigError
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.PreviewHost
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @pattern "{site_key}.preview.test"

  setup do
    root = Path.join(System.tmp_dir!(), "brando-preview-host-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    put_test_env(:release_static_path, Path.join(root, "release"))
    put_test_env(Brando.SSG, preview_host: @pattern)
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    shop = create_site("shop", :static)
    # The public domain of a site deployed elsewhere points at its static host
    live = create_environment(shop, "production", "www.shop.test", true)
    staging = create_environment(shop, "staging", nil)
    beta = create_site("beta", :static)
    beta_live = create_environment(beta, "production", "www.beta.test", true)

    %{
      shop: Registry.get_site(shop.id),
      live: live,
      staging: staging,
      beta: Registry.get_site(beta.id),
      beta_live: beta_live,
      root: root
    }
  end

  defp create_site(key, delivery_mode, attrs \\ %{}) do
    {:ok, site} =
      Registry.create_site(
        Map.merge(
          %{
            name: String.capitalize(key),
            key: key,
            languages: ["en"],
            default_language: "en",
            status: :active,
            delivery_mode: delivery_mode
          },
          attrs
        )
      )

    site
  end

  defp create_environment(site, key, domain, live \\ false, redirect_hosts \\ []) do
    {:ok, environment} =
      Registry.create_environment(
        site,
        %{name: String.capitalize(key), key: key, domain: domain, live: live, redirect_hosts: redirect_hosts},
        actor: :system
      )

    environment
  end

  defp ready_build(site, environment, files \\ %{}) do
    build =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, build} = Builds.request_build(site, environment, [])
        build
      end)

    for {relative, content} <- Map.merge(%{"index.html" => "home #{build.version}"}, files) do
      path = Path.join(build.build_path, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    Builds.get_build(ready.id)
  end

  # Through an installation's endpoint: asset sets, static files, the tenant
  # plug and the router
  defp dispatch(host, path, headers \\ []) do
    headers
    |> Enum.reduce(Map.put(build_conn(), :host, host), fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> Phoenix.ConnTest.dispatch(Brando.Test.LocalDeliveryEndpoint, :get, path, nil)
  end

  defp preview_path(build, path \\ ""), do: "/__ssg_preview__/#{build.preview_token}/#{path}"

  defp no_index?(conn), do: Enum.any?(get_resp_header(conn, "x-robots-tag"), &(&1 =~ "noindex"))

  describe "the pattern" do
    test "is refused at boot in any form but {site_key} as the whole first label of a host name" do
      for pattern <- [
            "preview.test",
            "x{site_key}.preview.test",
            "{site_key}x.preview.test",
            "preview.{site_key}.test",
            "{site_key}.{site_key}.test",
            "{site_key}.preview.{site_key}.test",
            "{site_key}.test",
            "{site_key}",
            "https://{site_key}.preview.test",
            "{site_key}.preview.test:4000"
          ] do
        put_test_env(Brando.SSG, preview_host: pattern)
        assert [problem] = PreviewHost.problems(), pattern
        assert problem in [:placeholder, :base], pattern
        refute PreviewHost.enabled?(), pattern
        assert_raise ConfigError, fn -> Brando.Tenant.validate_config!() end
        assert %{status: :error} = Brando.Doctor.Checks.PreviewHosts.run(nil)
      end
    end

    test "is refused at boot, and reported, when it is no string" do
      for value <- [true, ~c"{site_key}.preview.test", :pattern] do
        put_test_env(Brando.SSG, preview_host: value)
        assert PreviewHost.problems() == [:not_a_string], inspect(value)
        refute PreviewHost.enabled?()
        error = assert_raise ConfigError, fn -> Brando.Tenant.validate_config!() end
        assert error.message =~ inspect(value)
        assert %{status: :error} = Brando.Doctor.Checks.PreviewHosts.run(nil)
      end

      put_test_env(Brando.SSG, preview_host: "  ")
      assert PreviewHost.problems() == []
      assert %{status: :skipped} = Brando.Doctor.Checks.PreviewHosts.run(nil)
    end

    test "is refused at boot when an installation host matches it" do
      put_test_env(:media_url, "https://media.example.test")
      put_test_env(Brando.SSG, preview_host: "{site_key}.example.test")

      assert PreviewHost.problems() == [{:installation_host, "media.example.test"}]
      error = assert_raise ConfigError, fn -> Brando.Tenant.validate_config!() end
      assert error.message =~ "media.example.test"
      assert %{status: :error, summary: summary} = Brando.Doctor.Checks.PreviewHosts.run(nil)
      assert summary =~ "media.example.test"

      # A host further down is not matched: the placeholder is one label
      put_test_env(:media_url, "https://cdn.media.example.test")
      assert PreviewHost.problems() == []
    end

    test "has no effect without tenancy_mode :multi, and boot does not fail", context do
      for mode <- [:single, :none] do
        put_test_env(:tenancy_mode, mode)
        put_test_env(Brando.SSG, preview_host: "no placeholder")
        assert PreviewHost.problems() == []
        assert :ok = PreviewHost.validate_config!()
        assert %{status: :skipped} = Brando.Doctor.Checks.PreviewHosts.run(nil)

        put_test_env(Brando.SSG, preview_host: @pattern)
        refute PreviewHost.enabled?()
        assert PreviewHost.host(context.shop) == nil
        assert PreviewHost.site("shop.preview.test") == nil
      end
    end

    test "a host matches whatever its letter case and a trailing dot", context do
      shop = context.shop
      assert PreviewHost.host(shop) == "shop.preview.test"

      for host <- ["shop.preview.test", "SHOP.Preview.TEST", "shop.preview.test.", " shop.preview.test "] do
        assert {:ok, %{id: id}} = PreviewHost.site(host), host
        assert id == shop.id
      end

      assert PreviewHost.site("a.shop.preview.test") == nil
      assert PreviewHost.site("preview.test") == nil
      assert PreviewHost.site("shop.preview.test.example") == nil
    end

    test "a site that is not an active static one has none", context do
      blog = create_site("blog", :dynamic)
      assert PreviewHost.host(blog) == nil
      assert PreviewHost.site("blog.preview.test") == :error
      assert PreviewHost.site("unknown.preview.test") == :error

      {:ok, suspended} = Registry.update_site(context.beta, %{status: :suspended})
      assert PreviewHost.host(suspended) == nil
      assert PreviewHost.site("beta.preview.test") == :error

      assert PreviewHost.hosts() == ["shop.preview.test"]
    end

    test "the listing leaves out a host bound as a domain or a redirect host, as host/1 does", context do
      put_test_env(Brando.SSG, [])
      blog = create_site("blog", :dynamic)
      create_environment(blog, "production", "Shop.Preview.Test", true, ["beta.preview.test"])
      gamma = create_site("gamma", :static)
      put_test_env(Brando.SSG, preview_host: @pattern)

      assert PreviewHost.hosts() == ["gamma.preview.test"]
      assert Enum.map([context.shop, context.beta, gamma], &PreviewHost.host/1) == [nil, nil, "gamma.preview.test"]
    end

    test "a host of 253 bytes is one, one of 254 is not, nor a key longer than a DNS label" do
      # 192 bytes, of labels no longer than 63
      base = Enum.join([String.duplicate("a", 63), String.duplicate("b", 63), String.duplicate("c", 62), "x"], ".")
      put_test_env(Brando.SSG, preview_host: "{site_key}." <> base)

      fits = create_site(String.duplicate("k", 60), :static)
      too_long = create_site(String.duplicate("l", 61), :static)
      long_key = create_site(String.duplicate("m", 64), :static)

      assert byte_size(PreviewHost.host(fits)) == 253
      assert PreviewHost.host(too_long) == nil
      assert PreviewHost.site(too_long.key <> "." <> base) == nil
      assert PreviewHost.host(long_key) == nil
      assert PreviewHost.host(fits) in PreviewHost.hosts()
      assert length(PreviewHost.hosts()) == 3

      unserved = Map.new(PreviewHost.unserved_sites(), fn {site, reason} -> {site.key, reason} end)
      assert unserved[too_long.key] == :host_too_long
      assert unserved[long_key.key] == :key_too_long
      assert %{status: :warning, items: items} = Brando.Doctor.Checks.PreviewHosts.run(nil)
      assert Enum.any?(items, &(&1 =~ too_long.key))
      assert Enum.any?(items, &(&1 =~ long_key.key))

      build = ready_build(too_long, create_environment(too_long, "production", nil, true))
      assert Builds.preview_url(build, too_long, URI.parse("https://admin.test")) == nil
    end
  end

  describe "on a preview host" do
    setup do
      Brando.Test.LocalDeliveryEndpoint.start()
      :ok
    end

    test "a build preview of its site answers, under its build's environment, with noindex", context do
      site_url =
        Brando.Tenant.with_prefix(
          Brando.Tenant.prefix(context.shop, context.live),
          &Brando.Utils.public_hostname/0
        )

      build =
        ready_build(context.shop, context.live, %{
          "index.html" => ~s(<a href="/about">About</a><a href="#{site_url}/contact">Contact</a>)
        })

      # The served hosts file is off: only the file is skipped
      refute Brando.Tenant.ServedHosts.enabled?()
      conn = dispatch("shop.preview.test", preview_path(build))
      prefix = "/__ssg_preview__/#{build.preview_token}"
      # Its links stay on the preview host, the site's public domain's too
      assert response(conn, 200) == ~s(<a href="#{prefix}/about">About</a><a href="#{prefix}/contact">Contact</a>)
      assert no_index?(conn)
      assert conn.assigns.current_environment.id == context.live.id

      # One host for every environment of the site
      staging = ready_build(context.shop, context.staging)
      conn = dispatch("SHOP.preview.test.", preview_path(staging))
      assert response(conn, 200) == "home #{staging.version}"
      assert conn.assigns.current_environment.id == context.staging.id
    end

    test "every other path answers 404, with noindex", context do
      build = ready_build(context.shop, context.live)

      for path <- ["/", "/about", "/__p__/some-key", "/robots.txt", "/sitemaps/sitemap.xml", "/__ssg_preview__"] do
        conn = dispatch("shop.preview.test", path)
        assert conn.status == 404, path
        assert no_index?(conn), path
      end

      # The build's own token, on another site's preview host
      conn = dispatch("beta.preview.test", preview_path(build))
      assert conn.status == 404
    end

    test "a public file answers as on any host, with noindex", context do
      File.mkdir_p!(Path.join(context.root, "release/css"))
      File.write!(Path.join(context.root, "release/css/app.css"), "body{}")

      conn = dispatch("shop.preview.test", "/css/app.css")
      assert response(conn, 200) == "body{}"
      assert no_index?(conn)
    end

    test "a site that is not an active static one, or no site, answers nothing", context do
      blog = create_site("blog", :dynamic)
      create_environment(blog, "production", "www.blog.test", true)
      build = ready_build(context.beta, context.beta_live)
      {:ok, _beta} = Registry.update_site(context.beta, %{status: :suspended})

      assert dispatch("beta.preview.test", preview_path(build)).status == 404
      assert dispatch("blog.preview.test", "/").status == 404
      assert dispatch("unknown.preview.test", "/").status == 404
    end

    test "a site switched to dynamic loses it at once", context do
      build = ready_build(context.shop, context.live)
      assert dispatch("shop.preview.test", preview_path(build)).status == 200

      {:ok, _shop} = Registry.update_site(context.shop, %{delivery_mode: :dynamic})
      assert dispatch("shop.preview.test", preview_path(build)).status == 404
    end

    test "a build whose environment was deleted answers 404", context do
      build = ready_build(context.shop, context.staging)
      assert {:ok, _deleted} = Registry.delete_environment(context.staging)

      assert dispatch("shop.preview.test", preview_path(build)).status == 404
    end

    test "the admin's routes and its LiveView socket refuse", context do
      assert dispatch("shop.preview.test", "/admin/projects").status == 404
      refute BrandoAdmin.AdminHost.check_origin(URI.parse("https://shop.preview.test"))

      user = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})

      conn =
        build_conn()
        |> Brando.Test.log_in_user(user)
        |> Plug.Conn.put_private(:live_view_connect_info, %{uri: URI.parse("https://shop.preview.test/live/websocket")})

      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, "/admin/sites")
      _ = context
    end

    test "a site served from its build here does not answer on it" do
      put_test_env(Brando.Sites.DeployConfig, [])
      local = create_site("local", :static, %{deploy_config: %{strategy: :local, retention_count: 1}})
      live = create_environment(local, "production", "www.local.test", true)
      build = ready_build(Registry.get_site(local.id), live)
      assert {:ok, _deployed} = Deploy.deploy(build)

      assert response(dispatch("www.local.test", "/"), 200) == "home #{build.version}"
      assert dispatch("local.preview.test", "/").status == 404
      assert response(dispatch("local.preview.test", preview_path(build)), 200) == "home #{build.version}"
    end

    test "lockdown lets the preview through: the token is the access", context do
      put_test_env(:lockdown, true)
      build = ready_build(context.shop, context.live)

      conn =
        build_conn(:get, preview_path(build))
        |> Map.put(:host, "shop.preview.test")
        |> init_test_session(%{})
        |> Brando.Plug.Tenant.call([])
        |> Brando.Plug.Lockdown.call([])

      refute conn.halted
      assert conn.assigns.current_site.id == context.shop.id
    end

    test "a token signs no build request: the preview host wins over a build's signed context", context do
      build = ready_build(context.shop, context.live)
      header = {Brando.SSG.Context.header(), Brando.SSG.Context.sign(context.shop, context.live, nil)}

      assert dispatch("shop.preview.test", "/", [header]).status == 404
      assert dispatch("shop.preview.test", preview_path(build), [header]).status == 200
    end
  end

  describe "hosts that collide with the pattern" do
    setup do
      Brando.Test.LocalDeliveryEndpoint.start()
      :ok
    end

    test "are refused for a new domain or redirect host", context do
      assert {:error, changeset} =
               Registry.update_environment(context.staging, %{domain: "shop.preview.test"}, actor: :system)

      assert [{message, _}] = Keyword.get_values(changeset.errors, :domain)
      assert message =~ @pattern

      assert {:error, changeset} =
               Registry.update_environment(context.live, %{redirect_hosts: ["Beta.preview.test"]}, actor: :system)

      assert changeset.errors[:redirect_hosts]

      put_test_env(Brando.SSG, [])
      assert {:ok, _} = Registry.update_environment(context.staging, %{domain: "shop.preview.test"}, actor: :system)
    end

    test "bound before the pattern was set stay in a redirect list that changes", context do
      put_test_env(Brando.SSG, [])
      {:ok, live} = Registry.update_environment(context.live, %{redirect_hosts: ["beta.preview.test"]}, actor: :system)
      put_test_env(Brando.SSG, preview_host: @pattern)

      assert {:ok, live} =
               Registry.update_environment(live, %{redirect_hosts: ["beta.preview.test", "shop.test"]}, actor: :system)

      assert live.redirect_hosts == ["beta.preview.test", "shop.test"]

      assert {:error, changeset} =
               Registry.update_environment(live, %{redirect_hosts: live.redirect_hosts ++ ["gamma.preview.test"]},
                 actor: :system
               )

      assert [{message, _}] = Keyword.get_values(changeset.errors, :redirect_hosts)
      assert message =~ "gamma.preview.test"
    end

    test "bound as the domain before the pattern was set can move to the redirect list", context do
      put_test_env(Brando.SSG, [])
      {:ok, staging} = Registry.update_environment(context.staging, %{domain: "beta.preview.test"}, actor: :system)
      put_test_env(Brando.SSG, preview_host: @pattern)

      assert {:ok, staging} =
               Registry.update_environment(staging, %{domain: "beta-staging.test", redirect_hosts: ["beta.preview.test"]},
                 actor: :system
               )

      assert staging.redirect_hosts == ["beta.preview.test"]
    end

    test "bound before the pattern was set keep answering, and the site they name gets no preview host", context do
      put_test_env(Brando.SSG, [])
      blog = create_site("blog", :dynamic)
      create_environment(blog, "production", "shop.preview.test", true, ["beta.preview.test"])
      shop_build = ready_build(context.shop, context.live)
      beta_build = ready_build(context.beta, context.beta_live)

      put_test_env(Brando.SSG, preview_host: @pattern)

      assert response(dispatch("shop.preview.test", "/about"), 200) == "dynamic /about in production"
      assert redirected = dispatch("beta.preview.test", "/about")
      assert redirected.status == 301
      assert get_resp_header(redirected, "location") == ["http://shop.preview.test/about"]

      assert PreviewHost.host(context.shop) == nil
      assert PreviewHost.host(context.beta) == nil
      assert PreviewHost.hosts() == []
      assert Builds.preview_url(shop_build, context.shop, URI.parse("https://admin.test")) == nil
      assert Builds.preview_url(beta_build, context.beta, URI.parse("https://admin.test")) == nil

      assert %{status: :warning, items: items} = Brando.Doctor.Checks.PreviewHosts.run(nil)
      assert Enum.any?(items, &(&1 =~ "shop" and &1 =~ "blog"))
    end
  end

  describe "preview_url/3" do
    setup context do
      %{build: ready_build(context.shop, context.staging), admin: URI.parse("https://admin.test:4443/admin/sites")}
    end

    test "with the pattern, is on the site's preview host, also when an environment has a domain", context do
      url = "https://shop.preview.test:4443/__ssg_preview__/#{context.build.preview_token}/"
      assert Builds.preview_url(context.build, context.shop, context.admin) == url

      {:ok, _staging} = Registry.update_environment(context.staging, %{domain: "staging.shop.test"}, actor: :system)
      build = Builds.get_build(context.build.id)
      assert Builds.preview_url(build, context.shop, context.admin) == url
    end

    test "with the pattern, is nil for a build whose environment was deleted", context do
      assert {:ok, _deleted} = Registry.delete_environment(context.staging)
      build = Builds.get_build(context.build.id)

      assert build.environment == nil
      assert Builds.preview_url(build, context.shop, context.admin) == nil
    end

    test "without the pattern, is on the build environment's domain, else the live one's", context do
      put_test_env(Brando.SSG, [])
      path = "/__ssg_preview__/#{context.build.preview_token}/"
      assert Builds.preview_url(context.build, context.shop, context.admin) == "https://www.shop.test:4443" <> path

      {:ok, _staging} = Registry.update_environment(context.staging, %{domain: "staging.shop.test"}, actor: :system)
      build = Builds.get_build(context.build.id)
      assert Builds.preview_url(build, context.shop, context.admin) == "https://staging.shop.test:4443" <> path

      # Never on a host bound to another site
      stale = %{build | environment: %{build.environment | domain: "www.beta.test"}}
      assert Builds.preview_url(stale, context.shop, context.admin) == "https://www.shop.test:4443" <> path

      {:ok, _live} = Registry.update_environment(context.live, %{domain: nil}, actor: :system)
      stale = %{build | environment: %{build.environment | domain: nil}}
      assert Builds.preview_url(stale, context.shop, context.admin) == nil
    end

    test "is the path with one site or none", context do
      for mode <- [:single, :none] do
        put_test_env(:tenancy_mode, mode)
        assert Builds.preview_url(context.build, context.shop, context.admin) == preview_path(context.build)
      end
    end
  end

  describe "the Doctor" do
    test "is fine with a preview host per static site" do
      assert %{status: :ok, items: ["beta.preview.test", "shop.preview.test"]} =
               Brando.Doctor.Checks.PreviewHosts.run(nil)
    end

    test "warns when a session cookie's domain covers the preview hosts" do
      assert %{status: :warning, items: [item]} =
               Brando.Doctor.Checks.PreviewHosts.evaluate([], [".preview.test", "elsewhere.test"], [])

      assert item =~ ".preview.test"
      assert %{status: :warning} = Brando.Doctor.Checks.PreviewHosts.evaluate([], ["Test"], [])
      assert %{status: :ok} = Brando.Doctor.Checks.PreviewHosts.evaluate([], ["shop.preview.test"], [])
    end

    test "names a preview host the served hosts file does not admit, with the wildcard record as the fix" do
      assert %{status: :warning, fix: fix, items: [item]} =
               Brando.Doctor.Checks.PreviewHosts.evaluate([], [], [{"shop.preview.test", :unresolved}])

      assert item =~ "shop.preview.test"
      assert fix =~ "*.preview.test"
    end

    test "is skipped without the setting" do
      put_test_env(Brando.SSG, [])
      assert %{status: :skipped} = Brando.Doctor.Checks.PreviewHosts.run(nil)
    end
  end
end
