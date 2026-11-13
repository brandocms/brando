defmodule Brando.Assets.DevSiteTest do
  # A multi-site installation in development, with HMR on: two sites with an
  # active uploaded set each, `acme` the dev site and `beta` the other
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureIO
  import Phoenix.LiveViewTest, only: [render_component: 1, render_component: 2]

  alias Brando.Assets.DevSite
  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Assets.Vite.Manifest
  alias Brando.HTML
  alias Brando.SiteAssetsFixtures
  alias Brando.Tenant

  @host_app :brando_dev_site_test
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Development reads the release's build and the dev site's project from
    # the application's directory
    File.mkdir_p!(Path.join(tmp_dir, "assets/sites/acme/js"))
    File.write!(Path.join(tmp_dir, "assets/sites/acme/js/critical.js"), "")
    write_release(Path.join(tmp_dir, "priv/static"))

    cwd = File.cwd!()
    File.cd!(tmp_dir)

    put_test_env(:env, :dev)
    put_test_env(:ssg_run, false)
    put_test_env(:otp_app, @host_app)
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:media_path, Path.join(tmp_dir, "media"))
    put_test_env(:sites_path, Path.join(tmp_dir, "sites"))
    put_test_env(:site_assets_path, Path.join(tmp_dir, "site_assets"))
    put_test_env(:release_static_path, Path.join(tmp_dir, "priv/static"))
    Application.put_env(@host_app, :hmr, true)
    Application.put_env(@host_app, :dev_site, "acme")

    reset_caches()
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.cd!(cwd)
      Application.delete_env(@host_app, :hmr)
      Application.delete_env(@host_app, :dev_site)
      Tenant.put_prefix(nil)
      reset_caches()
      Brando.Tenant.Cache.clear()
    end)

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "beta", "beta.test")

    for site <- [acme, beta] do
      path = create_set(site, "#{site.key}-set")
      {:ok, set} = SiteAssets.register_set(site, path, %{})
      {:ok, _active} = SiteAssets.activate_set(set.id)
    end

    %{acme: acme, beta: beta}
  end

  describe "a request for the dev site" do
    setup do
      as_site("acme")
    end

    test "loads its scripts and styles from the Vite dev server" do
      for html <- [render_component(&HTML.include_assets/1), render_component(&HTML.include_assets/1, only_css: true)] do
        assert html =~ ~s(src="http://localhost:3000/@vite/client")
        assert html =~ ~s(src="http://localhost:3000/js/critical.js")
        refute html =~ "acme-set"
      end

      refute render_component(&HTML.include_assets/1, only_js: true) =~ "acme-set"
    end

    # Before `dev_site`, the active set won the manifest, the critical CSS,
    # the static files and the set a shared preview pins
    test "reads the release's Vite manifest, not its active set's" do
      assert Manifest.read(:app).entries.files == ["/assets/release.js"]
      assert SiteAssets.current_manifest() == nil
      assert SiteAssets.current_root() == nil
      assert SiteAssets.current_file("assets/acme-set.js") == nil
    end

    test "inlines the release's critical CSS, not its active set's" do
      css = render_component(&HTML.inject_critical_css/1)

      assert css =~ ".release-critical"
      refute css =~ ".acme-set-critical"
    end

    test "gets no static file from its active set" do
      refute Brando.Plug.SiteAssets.call(conn_for("assets/acme-set.js", "acme.test"), []).halted
    end

    test "pins the release's build to a shared preview, not its active set", %{acme: acme} do
      assert {:ok, set} = SiteAssets.with_preview_set(acme, & &1)
      assert Capture.captured?(set)
      refute set.active
    end

    test "names its own Vite project in the notice" do
      html = render_component(&HTML.include_assets/1)
      assert html =~ "<code>assets/sites/acme</code>"
    end

    test "falls back to the release's build when Vite did not start" do
      vite_failed()
      html = render_component(&HTML.include_assets/1)

      assert html =~ "/assets/release.js"
      refute html =~ "acme-set"
      refute html =~ "localhost:3000"
      assert html =~ "Vite for the site did not start"
    end
  end

  describe "a request for another site" do
    setup do
      as_site("beta")
    end

    test "renders from its active set, as in production" do
      html = render_component(&HTML.include_assets/1)

      assert html =~ "/assets/beta-set.js"
      assert html =~ "/assets/beta-set.css"
      refute html =~ "localhost:3000"
      refute html =~ "assets-notice"

      assert Manifest.read(:app).entries.files == ["/assets/beta-set.js"]
      assert render_component(&HTML.inject_critical_css/1) =~ ".beta-set-critical"
      assert Brando.Plug.SiteAssets.call(conn_for("assets/beta-set.js", "beta.test"), []).halted
    end

    test "renders from the release's build without an active set", %{beta: beta} do
      :ok = SiteAssets.deactivate(beta)
      html = render_component(&HTML.include_assets/1)

      assert html =~ "/assets/release.js"
      refute html =~ "localhost:3000"
    end

    test "pins its active set to a shared preview", %{beta: beta} do
      assert {:ok, set} = SiteAssets.with_preview_set(beta, & &1)
      assert set.active
      assert set.name == "beta-set"
    end

    test "gets no notice when Vite did not start" do
      vite_failed()
      html = render_component(&HTML.include_assets/1)

      assert html =~ "/assets/beta-set.js"
      refute html =~ "assets-notice"
    end
  end

  test "a page with no site context renders from the build" do
    Tenant.put_prefix(nil)
    refute render_component(&HTML.include_assets/1) =~ "localhost:3000"
  end

  describe "with dev_site unset" do
    setup do
      Application.delete_env(@host_app, :dev_site)
      :ok
    end

    test "every site loads from the dev server, and reads its active set as before" do
      for key <- ["acme", "beta"] do
        as_site(key)

        assert render_component(&HTML.include_assets/1) =~ "http://localhost:3000/js/index.js"
        assert Manifest.read(:app).entries.files == ["/assets/#{key}-set.js"]
        assert render_component(&HTML.inject_critical_css/1) =~ ".#{key}-set-critical"
        assert Brando.Plug.SiteAssets.call(conn_for("assets/#{key}-set.js", "#{key}.test"), []).halted
        # The project the notice names is the release's default frontend
        assert render_component(&HTML.include_assets/1) =~ "<code>assets/frontend</code>"
      end
    end

    test "the Vite fallback applies to every site" do
      vite_failed()

      for key <- ["acme", "beta"] do
        as_site(key)
        assert render_component(&HTML.include_assets/1) =~ "Vite for the site did not start"
      end
    end

    for mode <- [:none, :single] do
      test "#{mode} renders as before" do
        put_test_env(:tenancy_mode, unquote(mode))
        Tenant.put_prefix(nil)
        html = render_component(&HTML.include_assets/1)

        assert html =~ "http://localhost:3000/js/index.js"
        assert html =~ "<code>assets/frontend</code>"
      end
    end
  end

  describe "the setting is ignored" do
    for mode <- [:none, :single] do
      test "in #{mode}, with one warning at boot" do
        put_test_env(:tenancy_mode, unquote(mode))
        Tenant.put_prefix(nil)

        assert DevSite.key() == nil
        assert render_component(&HTML.include_assets/1) =~ "http://localhost:3000/js/index.js"

        warning = capture_io(:stderr, fn -> DevSite.warn_misconfigured() end)
        assert warning =~ ~s(dev_site: "acme" is ignored: it applies only with tenancy_mode: :multi)
      end
    end

    test "naming no site, with one warning at boot" do
      Application.put_env(@host_app, :dev_site, "gamma")

      assert DevSite.key() == nil
      warning = capture_io(:stderr, fn -> DevSite.warn_misconfigured() end)
      assert warning =~ ~s(dev_site: "gamma" is ignored: no site has that key)

      for key <- ["acme", "beta"] do
        as_site(key)
        assert render_component(&HTML.include_assets/1) =~ "http://localhost:3000/js/index.js"
      end
    end

    test "with HMR off: every site renders from its build" do
      Application.put_env(@host_app, :hmr, false)
      assert DevSite.key() == nil

      as_site("acme")
      assert render_component(&HTML.include_assets/1) =~ "/assets/acme-set.js"
    end

    for env <- [:prod, :e2e, :test] do
      test "in #{env}" do
        put_test_env(:env, unquote(env))

        assert DevSite.key() == nil
        assert capture_io(:stderr, fn -> DevSite.warn_misconfigured() end) == ""

        as_site("acme")
        assert Manifest.read(:app).entries.files == ["/assets/acme-set.js"]
        assert Brando.Plug.SiteAssets.call(conn_for("assets/acme-set.js", "acme.test"), []).halted
      end
    end

    test "in static builds" do
      put_test_env(:ssg_run, true)
      assert DevSite.key() == nil

      Application.put_env(@host_app, :dev_site, "gamma")
      assert capture_io(:stderr, fn -> DevSite.warn_misconfigured() end) == ""
      Application.put_env(@host_app, :dev_site, "acme")

      as_site("acme")
      assert render_component(&HTML.include_assets/1) =~ "/assets/acme-set.js"
    end
  end

  # guides/tenancy_and_environments.md, "Uploading a site's build by hand",
  # with a build in the shape `vite build` writes: manifest.json, assets/…
  # and the project's public/ files at the top level
  test "the documented steps give another site its build", %{beta: beta, tmp_dir: tmp_dir} do
    dist = Path.join(tmp_dir, "assets/sites/beta/dist")
    write_build(dist, "beta-new")
    File.write!(Path.join(dist, "favicon.ico"), "ico")

    dest = Path.join(SiteAssets.sets_root(beta), "20261113_abc123")
    File.cp_r!(dist, dest)
    assert {:ok, set} = SiteAssets.register_set("beta", dest, %{revision: "abc123"})
    assert {:ok, _active} = SiteAssets.activate_set(set.id)

    as_site("beta")
    assert render_component(&HTML.include_assets/1) =~ "/assets/beta-new.js"
    assert render_component(&HTML.inject_critical_css/1) =~ ".beta-new-critical"

    for path <- ["assets/beta-new.js", "assets/beta-new-critical.css", "favicon.ico"] do
      assert Brando.Plug.SiteAssets.call(conn_for(path, "beta.test"), []).status == 200, path
    end
  end

  test "a valid setting gives no warning" do
    assert DevSite.key() == "acme"
    assert capture_io(:stderr, fn -> DevSite.warn_misconfigured() end) == ""
  end

  defp as_site(key) do
    Tenant.put_prefix(Tenant.prefix(key, "production"))
    :ok
  end

  defp vite_failed do
    :persistent_term.put({Brando.Vite, :start_failure, :site}, %{dir: "assets/sites/acme", reason: {:exited, 1}})
  end

  # A build with a critical entry, as the installer's frontend has
  defp create_set(site, name) do
    path = Path.join(SiteAssets.sets_root(site), name)
    write_build(path, name)
    path
  end

  defp write_release(path), do: write_build(path, "release")

  defp write_build(path, name) do
    File.mkdir_p!(Path.join(path, "assets"))
    File.write!(Path.join([path, "assets", "#{name}.js"]), "js")
    File.write!(Path.join([path, "assets", "#{name}.css"]), "body{}")
    File.write!(Path.join([path, "assets", "#{name}-critical.js"]), "js")
    File.write!(Path.join([path, "assets", "#{name}-critical.css"]), ".#{name}-critical{}")

    manifest = %{
      "js/index.js" => %{"isEntry" => true, "file" => "assets/#{name}.js", "css" => ["assets/#{name}.css"]},
      "js/critical.js" => %{
        "isEntry" => true,
        "name" => "critical",
        "file" => "assets/#{name}-critical.js",
        "css" => ["assets/#{name}-critical.css"]
      }
    }

    File.write!(Path.join(path, "manifest.json"), Jason.encode!(manifest))
  end

  defp reset_caches do
    SiteAssets.invalidate_cache()
    :persistent_term.erase({Brando.Vite, :start_failure, :site})

    for prefix <- [nil, "tenant_acme_production", "tenant_beta_production"],
        name <- ["cache_manifest", "critical_css"] do
      :persistent_term.erase(Tenant.cache_key({:vite, name}, prefix))
    end
  end

  defp conn_for(relative_path, host) do
    :get
    |> Plug.Test.conn("https://#{host}/#{relative_path}")
    |> Map.put(:host, host)
  end
end
