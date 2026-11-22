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
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Preview
  alias Brando.Tenant

  @host_app :brando_dev_site_test

  # The endpoint's host, where the admin answers (`BrandoAdmin.AdminHost`);
  # `admin.test` resolves to no site but is not the admin's
  @admin_host "localhost"

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns) do
      ~H|<html>
  <head><Brando.HTML.inject_critical_css /><Brando.HTML.include_assets /></head>
  <body>{@inner_content}<Brando.HTML.include_legacy_assets /></body>
</html>|
    end
  end

  defmodule PageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H|<main>{@page.title}</main>|
  end

  defmodule AcmeFrontend do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: PageHTML
  end

  @moduletag :tmp_dir

  # Files of a site's `public/` that its build copies under stable names
  @public_files ["fonts/moderat/moderat-regular.woff2", "images/logo.svg", "favicon.ico"]

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

    # Every environment of the dev site loads from the Vite dev server
    test "reads nothing from an environment's own set", %{acme: acme} do
      {:ok, own} = SiteAssets.register_set(acme, create_set(acme, "acme-own"), %{})
      production = Tenant.Cache.get_env("acme", "production")
      assert {:ok, _production} = SiteAssets.activate_environment_set(own.id, production)

      assert SiteAssets.current_manifest() == nil
      assert SiteAssets.current_file("assets/acme-own.js") == nil
      refute Brando.Plug.SiteAssets.call(conn_for("assets/acme-own.js", "acme.test"), []).halted
      refute Brando.Plug.SiteAssets.call(conn_for("assets/acme-own.js", "admin.test"), []).halted

      # Nor does another environment's host
      {:ok, _staging} =
        Brando.Tenant.Registry.create_environment(
          acme,
          %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
          actor: :system
        )

      refute Brando.Plug.SiteAssets.call(conn_for("assets/acme-own.js", "staging.acme.test"), []).halted
    end

    test "gets no legacy bundles" do
      refute render_component(&HTML.include_legacy_assets/1) =~ "-legacy.js"
    end

    # Only a shared preview reads the set: a page from the dev server must
    # not start reading the uploaded build because it exists
    test "gets no public file from its active set while no shared preview pins it", %{acme: acme} do
      activate_public_set(acme)

      for path <- @public_files, host <- ["acme.test", "admin.test"] do
        refute Brando.Plug.SiteAssets.call(conn_for(path, host), []).halted, "#{path} on #{host}"
      end
    end

    # A file at a stable name (Vite's `public/` files, or build output named
    # without a hash) that the release also holds is the release's, which
    # the dev server's page gets
    test "gets a pinned set's files, but the release's at a name both hold", %{acme: acme, tmp_dir: tmp_dir} do
      set = activate_public_set(acme)
      pin(set)

      release = Path.join(tmp_dir, "priv/static")
      File.write!(Path.join(release, "favicon.ico"), "release icon")
      File.mkdir_p!(Path.join(release, "fonts"))
      File.write!(Path.join(release, "fonts/brand.woff2"), "release font")

      assert Brando.Plug.SiteAssets.call(conn_for("assets/acme-public.js", "acme.test"), []).halted
      assert served_body("fonts/moderat/moderat-regular.woff2", "acme.test") == "set font"

      for stable <- ["favicon.ico", "fonts/brand.woff2"] do
        refute Brando.Plug.SiteAssets.call(conn_for(stable, "acme.test"), []).halted, stable
      end
    end

    # Vite serves its project's `public/` on its own origin, but the page
    # names the files host-relative: the layout's favicon, and the fonts in
    # the CSS Vite injects into the page
    test "gets its project's public files on its hosts and the admin's, but no other site's host does" do
      write_public("fonts/a.woff2", "project font")
      write_public("images/b.svg", "project logo")

      for host <- ["acme.test", @admin_host] do
        conn = Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", host), [])
        assert conn.resp_body == "project font", host
        assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-cache"], host
        assert served_body("images/b.svg", host) == "project logo", host
      end

      for path <- ["fonts/a.woff2", "images/b.svg"] do
        refute Brando.Plug.SiteAssets.call(conn_for(path, "beta.test"), []).halted, path
      end

      # Nor once another site is the dev site
      Application.put_env(@host_app, :dev_site, "beta")
      refute Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", "acme.test"), []).halted
      refute Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", @admin_host), []).halted
    end

    test "gets the release's file and a pinned set's before its project's public file", %{
      acme: acme,
      tmp_dir: tmp_dir
    } do
      write_public("fonts/moderat/moderat-regular.woff2", "project font")
      write_public("favicon.ico", "project icon")
      File.write!(Path.join(tmp_dir, "priv/static/favicon.ico"), "release icon")

      for host <- ["acme.test", @admin_host] do
        assert served_body("fonts/moderat/moderat-regular.woff2", host) == "project font", host
        refute Brando.Plug.SiteAssets.call(conn_for("favicon.ico", host), []).halted, host
      end

      acme |> activate_public_set() |> pin()

      for host <- ["acme.test", @admin_host] do
        assert served_body("fonts/moderat/moderat-regular.woff2", host) == "set font", host
        refute Brando.Plug.SiteAssets.call(conn_for("favicon.ico", host), []).halted, host
      end
    end

    # Another site's live preview on the admin's host names its set's file,
    # as before the dev site's folder answered there
    test "gets no public file on the admin's host where another site holds other content", %{beta: beta} do
      write_public("images/logo.svg", "project logo")
      activate_public_set(beta)
      assert served_body("images/logo.svg", @admin_host) == "set logo"
      assert served_body("images/logo.svg", "acme.test") == "project logo"
    end

    # A suspended site has no preview to keep its set's file for
    test "gets its public file on the admin's host where only a suspended site's set holds the path", %{beta: beta} do
      write_public("images/logo.svg", "project logo")
      activate_public_set(beta)
      {:ok, _beta} = Brando.Tenant.Registry.update_site(beta, %{status: :suspended})

      assert served_body("images/logo.svg", @admin_host) == "project logo"
    end

    # A suspended site's host resolves to no site, as the admin's does
    test "gets no public file on a host that resolves to no site but the admin's", %{beta: beta} do
      write_public("fonts/a.woff2", "project font")
      {:ok, _beta} = Brando.Tenant.Registry.update_site(beta, %{status: :suspended})

      for host <- ["beta.test", "admin.test"] do
        refute Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", host), []).halted, host
      end

      assert served_body("fonts/a.woff2", @admin_host) == "project font"
    end

    # A set may hold the path: the lookup that failed cannot tell
    test "gets no public file on the admin's host while the sets' paths cannot be read" do
      write_public("fonts/a.woff2", "project font")
      assert served_body("fonts/a.woff2", @admin_host) == "project font"

      reset_caches()

      Ecto.Adapters.SQL.query!(
        BrandoIntegration.Repo,
        "ALTER TABLE public.site_asset_sets RENAME TO site_asset_sets_away"
      )

      refute Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", @admin_host), []).halted
    end

    # Nothing tells which environment's preview asked, as before the folder answered
    test "gets no public file where two pinned environment sets hold other content", %{acme: acme} do
      write_public("images/logo.svg", "project logo")

      for {key, content} <- [{"staging", "staging logo"}, {"qa", "qa logo"}] do
        path = create_public_set(acme, "acme-#{key}")
        File.write!(Path.join(path, "images/logo.svg"), content)
        {:ok, own} = SiteAssets.register_set(acme, path, %{})

        {:ok, environment} =
          Brando.Tenant.Registry.create_environment(
            acme,
            %{name: key, key: key, live: false, domain: "#{key}.acme.test"},
            actor: :system
          )

        assert {:ok, _environment} = SiteAssets.activate_environment_set(own.id, environment)
        pin(own)
      end

      refute Brando.Plug.SiteAssets.call(conn_for("images/logo.svg", "acme.test"), []).halted
      assert served_body("images/logo.svg", "qa.acme.test") == "qa logo"
    end

    test "gets nothing outside its project's public folder", %{tmp_dir: tmp_dir} do
      write_public("images/b.svg", "project logo")
      File.write!(Path.join(tmp_dir, "assets/sites/acme/secret.txt"), "secret")
      outside = Path.join(tmp_dir, "outside")
      File.mkdir_p!(outside)
      File.write!(Path.join(outside, "secret.txt"), "secret")

      public = Path.join(tmp_dir, "assets/sites/acme/public")
      File.ln_s!(outside, Path.join(public, "linked"))
      File.ln_s!(Path.join(outside, "secret.txt"), Path.join(public, "secret.txt"))
      File.ln_s!("images", Path.join(public, "pictures"))

      for path <- [
            "../secret.txt",
            "images/../../secret.txt",
            Path.join(outside, "secret.txt"),
            "linked/secret.txt",
            "secret.txt",
            "",
            "images"
          ] do
        assert SiteAssets.dev_site_public_file("acme", nil, path) == nil, path
      end

      for url_path <- [
            "..%2Fsecret.txt",
            "%2e%2e/secret.txt",
            "images%2F..%2F..%2Fsecret.txt",
            "images/..%5C..%5Csecret.txt",
            "linked/secret.txt",
            "secret.txt"
          ],
          host <- ["acme.test", @admin_host] do
        refute Brando.Plug.SiteAssets.call(conn_for(url_path, host), []).halted, "#{url_path} on #{host}"
      end

      # A symlink that stays inside the folder is followed
      assert served_body("pictures/b.svg", "acme.test") == "project logo"
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

  # A shared link outlives the developer's Vite server: it pins a build
  describe "a shared preview of the dev site" do
    setup do
      put_test_env(:site_frontends, %{"acme" => AcmeFrontend})
      as_site("acme")
    end

    test "pins its active set", %{acme: acme} do
      assert {:ok, set} = SiteAssets.with_preview_set(acme, & &1)
      assert set.active
      assert set.name == "acme-set"
    end

    test "pins the own set of the environment it is shared from", %{acme: acme} do
      {:ok, own} = SiteAssets.register_set(acme, create_set(acme, "acme-own"), %{})
      production = Tenant.Cache.get_env("acme", "production")
      assert {:ok, _production} = SiteAssets.activate_environment_set(own.id, production)

      assert {:ok, set} = SiteAssets.with_preview_set(acme, production, & &1)
      assert set.id == own.id
    end

    test "without a set or a Vite project of its own, pins a capture of the release's build", %{
      acme: acme,
      tmp_dir: tmp_dir
    } do
      :ok = SiteAssets.deactivate(acme)
      File.rm_rf!(Path.join(tmp_dir, "assets/sites/acme"))

      assert {:ok, set} = SiteAssets.with_preview_set(acme, & &1)
      assert Capture.captured?(set)
      refute set.active
    end

    # The admin turns this reason into what to do (pnpm build)
    test "without a set, a Vite project or a release build, is refused", %{acme: acme, tmp_dir: tmp_dir} do
      :ok = SiteAssets.deactivate(acme)
      File.rm_rf!(Path.join(tmp_dir, "assets/sites/acme"))
      File.rm_rf!(Path.join(tmp_dir, "priv/static"))

      assert {:error, :no_frontend_assets} = SiteAssets.with_preview_set(acme, & &1)
    end

    # Stray files or the admin's build in priv/static are no frontend build:
    # a page rendered from them has no script or style tags
    test "without a set or a Vite project, and a release with no Vite manifest, is refused", %{
      acme: acme,
      tmp_dir: tmp_dir
    } do
      :ok = SiteAssets.deactivate(acme)
      File.rm_rf!(Path.join(tmp_dir, "assets/sites/acme"))
      release = Path.join(tmp_dir, "priv/static")
      File.rm_rf!(release)
      File.mkdir_p!(Path.join(release, "admin"))
      File.write!(Path.join(release, "admin/app.css"), "body{}")

      assert {:error, :no_frontend_assets} = SiteAssets.with_preview_set(acme, & &1)
      assert {:error, :no_frontend_assets} = LivePreview.share(Page, page_changeset(), user())
      assert SiteAssets.list_sets(acme) |> Enum.filter(&Capture.captured?/1) == []
      refute acme |> SiteAssets.sets_root() |> Path.join("capture-*") |> Path.wildcard() |> Enum.any?()
    end

    # The release holds the default frontend, not the site's own project
    test "with a Vite project of its own and no set, is refused", %{acme: acme} do
      :ok = SiteAssets.deactivate(acme)

      assert {:error, :dev_site_without_set} = SiteAssets.with_preview_set(acme, & &1)
      assert {:error, :dev_site_without_set} = LivePreview.share(Page, page_changeset(), user())
      assert SiteAssets.list_sets(acme) |> Enum.filter(&Capture.captured?/1) == []
    end

    test "stores HTML that loads its active set, never the dev server" do
      html = shared_html()

      assert html =~ ~s(src="/assets/acme-set.js")
      assert html =~ ".acme-set-critical"
      assert html =~ "/assets/acme-set-legacy.js"
      refute html =~ "localhost:3000"
      refute html =~ "assets-notice"

      # The link opens on a host that belongs to no site, and on the site's own
      for host <- ["admin.test", "acme.test"] do
        assert Brando.Plug.SiteAssets.call(conn_for("assets/acme-set.js", host), []).halted, host
      end
    end

    # Vite copies `public/` (fonts, images, the favicon) to the build's top
    # level under stable names, outside the manifest, and the set's CSS and
    # layout ask for them
    test "gets its pinned active set's public files, but the release's at a name both hold", %{
      acme: acme,
      tmp_dir: tmp_dir
    } do
      activate_public_set(acme)
      File.write!(Path.join(tmp_dir, "priv/static/favicon.ico"), "release icon")
      shared_html()

      # The link opens on a host that belongs to no site, and on the site's own
      for host <- ["acme.test", "admin.test"] do
        assert served_body("fonts/moderat/moderat-regular.woff2", host) == "set font", host
        assert served_body("images/logo.svg", host) == "set logo", host
        refute Brando.Plug.SiteAssets.call(conn_for("favicon.ico", host), []).halted, host
      end
    end

    test "stops getting its set's public files once the preview expires", %{acme: acme} do
      set = activate_public_set(acme)
      preview = pin(set)
      assert served_body("fonts/moderat/moderat-regular.woff2", "acme.test") == "set font"

      preview
      |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second))
      |> Brando.Repo.update!(prefix: "public")

      SiteAssets.invalidate_pinned(acme)

      for host <- ["acme.test", "admin.test"] do
        refute Brando.Plug.SiteAssets.call(conn_for("fonts/moderat/moderat-regular.woff2", host), []).halted, host
      end

      # Nor once it is purged
      pin(set)
      assert served_body("fonts/moderat/moderat-regular.woff2", "admin.test") == "set font"
      Brando.Repo.delete_all(Preview, prefix: "public")
      SiteAssets.invalidate_pinned(acme)

      for host <- ["acme.test", "admin.test"] do
        refute Brando.Plug.SiteAssets.call(conn_for("fonts/moderat/moderat-regular.woff2", host), []).halted, host
      end
    end

    test "gets the public files of the environment's own set it pins", %{acme: acme} do
      {:ok, own} = SiteAssets.register_set(acme, create_public_set(acme, "acme-own"), %{})
      production = Tenant.Cache.get_env("acme", "production")
      assert {:ok, _production} = SiteAssets.activate_environment_set(own.id, production)
      refute Brando.Plug.SiteAssets.call(conn_for("images/logo.svg", "acme.test"), []).halted

      {:ok, _staging} =
        Brando.Tenant.Registry.create_environment(
          acme,
          %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
          actor: :system
        )

      refute Brando.Plug.SiteAssets.call(conn_for("images/logo.svg", "staging.acme.test"), []).halted

      pin(own)

      # Another environment's host, where a preview of this one is shown, too
      for host <- ["acme.test", "admin.test", "staging.acme.test"] do
        assert served_body("images/logo.svg", host) == "set logo", host
      end
    end

    test "stores HTML that loads the captured release's build, never the dev server", %{
      acme: acme,
      tmp_dir: tmp_dir
    } do
      :ok = SiteAssets.deactivate(acme)
      File.rm_rf!(Path.join(tmp_dir, "assets/sites/acme"))
      html = shared_html()

      assert html =~ ~s(src="/assets/release.js")
      assert html =~ ".release-critical"
      refute html =~ "localhost:3000"
    end

    test "leaves the live preview on the dev server" do
      html = LivePreview.render(Page, page(), nil, target: :site)

      assert html =~ ~s(src="http://localhost:3000/js/index.js")
      refute html =~ "acme-set"
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

    test "gets its active set's legacy bundles, as in production" do
      assert render_component(&HTML.include_legacy_assets/1) =~ "/assets/beta-set-legacy.js"
    end

    # The page names the same file, and the same hosts serve it: the site's
    # own, not the dev site's nor a host that belongs to no site
    test "names the same assets as in production, served on the same hosts" do
      outcome = fn env ->
        put_test_env(:env, env)
        reset_caches()
        html = render_component(&HTML.include_assets/1)
        [src] = Regex.run(~r{src="(/assets/[^"]+\.js)"}, html, capture: :all_but_first)

        served =
          for host <- ["admin.test", "acme.test", "beta.test"],
              do: {host, Brando.Plug.SiteAssets.call(conn_for(String.trim_leading(src, "/"), host), []).halted}

        {src, served}
      end

      assert outcome.(:dev) == outcome.(:prod)
    end

    test "renders from the release's build without an active set", %{beta: beta} do
      :ok = SiteAssets.deactivate(beta)
      html = render_component(&HTML.include_assets/1)

      assert html =~ "/assets/release.js"
      refute html =~ "localhost:3000"
    end

    # The usual HMR checkout has no build in priv/static
    test "without any build: a notice, and a later build is read at once", %{beta: beta, tmp_dir: tmp_dir} do
      :ok = SiteAssets.deactivate(beta)
      release = Path.join(tmp_dir, "priv/static")
      File.rm_rf!(release)

      for html <- [render_component(&HTML.include_assets/1), render_component(&HTML.include_assets/1, only_css: true)] do
        assert html =~ "Site assets not built for beta"
        assert html =~ ~s(dev_site: "acme")
        assert html =~ "<code>assets/sites/beta</code>"
        assert html =~ ~s[brandoAssetsMissing("brando-site-assets-notice")]
        refute html =~ "localhost:3000"
      end

      render_component(&HTML.inject_critical_css/1)
      write_release(release)

      html = render_component(&HTML.include_assets/1)
      assert html =~ "/assets/release.js"
      refute html =~ "assets-notice"
      assert render_component(&HTML.inject_critical_css/1) =~ ".release-critical"
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
        refute render_component(&HTML.include_legacy_assets/1) =~ "-legacy.js"
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

        write_public("fonts/a.woff2", "project font")

        for host <- ["acme.test", @admin_host] do
          refute Brando.Plug.SiteAssets.call(conn_for("fonts/a.woff2", host), []).halted, host
        end
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
  # run as written for a site that never had a set, with a build in the
  # shape `vite build` writes: manifest.json, assets/… and the project's
  # public/ files at the top level
  test "the documented steps give another site its build", %{tmp_dir: tmp_dir} do
    {:ok, gamma} = SiteAssetsFixtures.create_site("Gamma", "gamma", "gamma.test")
    :ok = Brando.Tenant.Storage.create(gamma)
    sets_root = SiteAssets.sets_root(gamma)
    refute File.exists?(sets_root)

    dist = Path.join(tmp_dir, "assets/sites/gamma/dist")
    write_build(dist, "gamma-new")
    File.write!(Path.join(dist, "favicon.ico"), "ico")

    dest = Path.join(sets_root, "20261113_abc123")
    assert {_, 0} = System.cmd("mkdir", ["-p", sets_root])
    assert {_, 0} = System.cmd("cp", ["-R", dist, dest])
    assert {:ok, set} = SiteAssets.register_set("gamma", dest, %{revision: "abc123"})
    assert {:ok, _active} = SiteAssets.activate_set(set.id)

    as_site("gamma")
    assert render_component(&HTML.include_assets/1) =~ "/assets/gamma-new.js"
    assert render_component(&HTML.inject_critical_css/1) =~ ".gamma-new-critical"

    for path <- ["assets/gamma-new.js", "assets/gamma-new-critical.css", "favicon.ico"] do
      assert Brando.Plug.SiteAssets.call(conn_for(path, "gamma.test"), []).status == 200, path
    end
  end

  test "a valid setting gives no warning" do
    assert DevSite.key() == "acme"
    assert capture_io(:stderr, fn -> DevSite.warn_misconfigured() end) == ""
  end

  defp page, do: %Page{title: "About", uri: "about", template: "default.html", language: :en, entry_blocks: []}

  defp page_changeset, do: page() |> Map.put(:key, "about") |> Ecto.Changeset.change()

  defp user, do: Brando.Factory.insert(:random_user, avatar: nil)

  # The stored HTML of a shared preview of the current site
  defp shared_html do
    assert {:ok, url, _days} = LivePreview.share(Page, page_changeset(), user(), %{}, :site)
    %URI{path: "/__p__/" <> key} = URI.parse(url)
    preview = Brando.Repo.get_by!(Preview, [preview_key: Preview.hash_key(key)], prefix: "public")
    Brando.Utils.binary_to_term(preview.html)
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

  # A build with the project's `public/` files beside it, as `vite build` writes them
  defp create_public_set(site, name) do
    path = create_set(site, name)

    for {file, content} <- [
          {"fonts/moderat/moderat-regular.woff2", "set font"},
          {"fonts/brand.woff2", "set brand font"},
          {"images/logo.svg", "set logo"},
          {"favicon.ico", "set icon"}
        ] do
      File.mkdir_p!(Path.dirname(Path.join(path, file)))
      File.write!(Path.join(path, file), content)
    end

    path
  end

  defp activate_public_set(site) do
    {:ok, set} = SiteAssets.register_set(site, create_public_set(site, "#{site.key}-public"), %{})
    {:ok, active} = SiteAssets.activate_set(set.id)
    active
  end

  # An unexpired shared preview that pins `set`
  defp pin(set) do
    preview =
      Brando.Repo.insert!(
        %Preview{
          creator_id: user().id,
          preview_key: Ecto.UUID.generate(),
          html: Brando.Utils.term_to_binary("<main>Pinned</main>"),
          expires_at: DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second),
          asset_set_id: set.id
        },
        prefix: "public"
      )

    SiteAssets.invalidate_pinned(set)
    preview
  end

  # A file in the dev site's Vite project's `public/` folder
  defp write_public(relative_path, content) do
    file = Path.join("assets/sites/acme/public", relative_path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  defp served_body(relative_path, host) do
    conn = Brando.Plug.SiteAssets.call(conn_for(relative_path, host), [])
    if conn.halted, do: conn.resp_body
  end

  defp write_release(path), do: write_build(path, "release")

  defp write_build(path, name) do
    File.mkdir_p!(Path.join(path, "assets"))
    File.write!(Path.join([path, "assets", "#{name}.js"]), "js")
    File.write!(Path.join([path, "assets", "#{name}.css"]), "body{}")
    File.write!(Path.join([path, "assets", "#{name}-critical.js"]), "js")
    File.write!(Path.join([path, "assets", "#{name}-critical.css"]), ".#{name}-critical{}")

    File.write!(Path.join([path, "assets", "#{name}-legacy.js"]), "js")

    manifest = %{
      "js/index.js" => %{"isEntry" => true, "file" => "assets/#{name}.js", "css" => ["assets/#{name}.css"]},
      "js/index-legacy.js" => %{"isEntry" => true, "file" => "assets/#{name}-legacy.js"},
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

    for prefix <- [nil, "tenant_acme_production", "tenant_beta_production", "tenant_gamma_production"],
        name <- ["cache_manifest", "critical_css", {"manifest_stamp", :app}] do
      :persistent_term.erase(Tenant.cache_key({:vite, name}, prefix))
    end
  end

  defp conn_for(relative_path, host) do
    :get
    |> Plug.Test.conn("https://#{host}/#{relative_path}")
    |> Map.put(:host, host)
  end
end
