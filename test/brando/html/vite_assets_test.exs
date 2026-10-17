defmodule Brando.HTML.ViteAssetsTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Phoenix.LiveViewTest, only: [render_component: 1, render_component: 2]

  alias Brando.HTML

  @host_app :brando_html_vite_test
  @env_vars ~w(BRANDO_VITE_FRONTEND_HOST BRANDO_VITE_FRONTEND_PORT BRANDO_VITE_ADMIN_HOST BRANDO_VITE_ADMIN_PORT)

  # In development the dev servers' scripts show a notice when they fail to load
  @frontend_html """
  <!-- dev/test -->
  <script type="module" src="http://localhost:3000/@vite/client" onerror="brandoAssetsMissing(&#39;brando-site-assets-notice&#39;)">
  </script>
  <script type="module" src="http://localhost:3000/js/critical.js" onerror="brandoAssetsMissing(&#39;brando-site-assets-notice&#39;)">
  </script>
  <script type="module" src="http://localhost:3000/js/index.js" onerror="brandoAssetsMissing(&#39;brando-site-assets-notice&#39;)">
  </script>
  <!-- end dev/test -->
  """
  @admin_html """
  <!-- admin dev/test -->
  <script type="module" src="http://localhost:3333/@vite/client" onerror="brandoAssetsMissing(&#39;brando-admin-assets-notice&#39;)">
  </script>
  <script type="module" src="http://localhost:3333/src/main.js" onerror="brandoAssetsMissing(&#39;brando-admin-assets-notice&#39;)">
  </script>
  <!-- end admin dev/test -->
  """

  setup do
    put_test_env(:env, :dev)
    put_test_env(:ssg_run, false)
    put_test_env(:otp_app, @host_app)
    put_test_env(:tenancy_mode, :none)
    # The flag belongs to the host app, even if :brando has the opposite value.
    put_test_env(:hmr, false)

    previous_hmr = Application.fetch_env(@host_app, :hmr)
    Application.delete_env(@host_app, :hmr)
    previous_env = Map.new(@env_vars, &{&1, System.get_env(&1)})
    Enum.each(@env_vars, &System.delete_env/1)

    on_exit(fn ->
      case previous_hmr do
        {:ok, value} -> Application.put_env(@host_app, :hmr, value)
        :error -> Application.delete_env(@host_app, :hmr)
      end

      Enum.each(previous_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    cache({:brando, :site_assets, :active, :standalone}, :none)

    for {scope, name} <- [app: "cache_manifest", admin: "cache_admin_manifest"] do
      cache(Brando.Tenant.cache_key({:vite, name}), %{
        entries: %{css_files: ["/assets/#{scope}.css"], files: ["/assets/#{scope}.js"]},
        legacy: %{files: ["/assets/#{scope}-legacy.js"]}
      })
    end

    :ok
  end

  test "unconfigured HMR output is byte-identical" do
    assert frontend_scripts() == @frontend_html
    assert frontend_scripts(only_css: true) == @frontend_html
    assert admin_scripts() == @admin_html
  end

  describe "the notice when the admin's assets are missing in development" do
    test "waits for the dev server's scripts to fail, and names the server" do
      System.put_env("BRANDO_VITE_ADMIN_PORT", "3334")
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ ~s(<template id="brando-admin-assets-notice">)
      assert html =~ "Admin assets not reachable at http://localhost:3334"
      assert html =~ "config :brando_html_vite_test, hmr: false"
      refute html =~ ~s|brandoAssetsMissing("brando-admin-assets-notice");|
    end

    test "shows at once when there is no build" do
      Application.put_env(@host_app, :hmr, false)
      cache(Brando.Tenant.cache_key({:vite, "cache_admin_manifest"}), %Brando.Assets.Vite.Manifest{})
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "Admin assets not built"
      assert html =~ ~s|brandoAssetsMissing("brando-admin-assets-notice");|
    end

    test "is not there with a build" do
      Application.put_env(@host_app, :hmr, false)
      refute render_component(&HTML.include_assets/1, admin: true) =~ "brando-admin-assets-notice"
    end

    for env <- [:prod, :staging, :e2e, :test] do
      test "is never there in #{env}" do
        Application.put_env(:brando, :env, unquote(env))
        cache(Brando.Tenant.cache_key({:vite, "cache_admin_manifest"}), %Brando.Assets.Vite.Manifest{})
        html = render_component(&HTML.include_assets/1, admin: true)

        refute html =~ "brando-admin-assets-notice"
        refute html =~ "brandoAssetsMissing"
      end
    end
  end

  describe "the notice when the site's Vite dev server is unreachable in development" do
    test "waits for the dev server's scripts to fail, and names the server" do
      System.put_env("BRANDO_VITE_FRONTEND_PORT", "3001")

      for html <- [render_component(&HTML.include_assets/1), render_component(&HTML.include_assets/1, only_css: true)] do
        assert html =~ ~s(<template id="brando-site-assets-notice">)
        assert html =~ "Site assets not reachable at http://localhost:3001"
        assert html =~ "<code>assets/frontend</code>"
        assert html =~ "config :brando_html_vite_test, hmr: false"
        refute html =~ ~s|brandoAssetsMissing("brando-site-assets-notice");|
      end
    end

    for env <- [:staging, :e2e, :test] do
      test "is never there in #{env}" do
        Application.put_env(:brando, :env, unquote(env))
        html = render_component(&HTML.include_assets/1)

        assert html =~ "@vite/client"
        refute html =~ "brando-site-assets-notice"
        refute html =~ "brandoAssetsMissing"
      end
    end
  end

  # The dev server's scripts, without the notice before them
  defp admin_scripts do
    html = render_component(&HTML.include_assets/1, admin: true)
    [_notice, scripts] = String.split(html, ~s(<script type="module"), parts: 2)
    "<!-- admin dev/test -->\n" <> ~s(<script type="module") <> scripts
  end

  defp frontend_scripts(assigns \\ []) do
    html = render_component(&HTML.include_assets/1, assigns)
    [_notice, scripts] = String.split(html, ~s(<script type="module"), parts: 2)
    "<!-- dev/test -->\n" <> ~s(<script type="module") <> scripts
  end

  test "frontend overrides affect all frontend scripts without moving the admin server" do
    System.put_env("BRANDO_VITE_FRONTEND_HOST", "frontend.localhost")
    System.put_env("BRANDO_VITE_FRONTEND_PORT", "4300")
    expected = String.replace(@frontend_html, "localhost:3000", "frontend.localhost:4300")

    assert frontend_scripts() == expected
    assert frontend_scripts(only_css: true) == expected
    assert admin_scripts() == @admin_html
  end

  test "admin overrides do not move the frontend server" do
    System.put_env("BRANDO_VITE_ADMIN_HOST", "admin.localhost")
    System.put_env("BRANDO_VITE_ADMIN_PORT", "4333")

    assert admin_scripts() == String.replace(@admin_html, "localhost:3333", "admin.localhost:4333")

    assert frontend_scripts() == @frontend_html
  end

  test "ports can change independently of hosts and are read again on each render" do
    System.put_env("BRANDO_VITE_FRONTEND_PORT", "3001")
    System.put_env("BRANDO_VITE_ADMIN_PORT", "3334")

    assert frontend_scripts() == String.replace(@frontend_html, ":3000", ":3001")
    assert admin_scripts() == String.replace(@admin_html, ":3333", ":3334")

    System.put_env("BRANDO_VITE_FRONTEND_PORT", "3002")
    assert frontend_scripts() == String.replace(@frontend_html, ":3000", ":3002")
  end

  test "hosts can change independently of ports, including IPv6 addresses" do
    System.put_env("BRANDO_VITE_FRONTEND_HOST", "127.0.0.1")
    System.put_env("BRANDO_VITE_ADMIN_HOST", "::1")

    assert frontend_scripts() == String.replace(@frontend_html, "localhost", "127.0.0.1")

    assert admin_scripts() == String.replace(@admin_html, "localhost", "[::1]")
  end

  test "only_js and legacy helpers do not load a dev server a second time" do
    invalid_dev_ports()

    assert render_component(&HTML.include_assets/1, only_js: true) ==
             "<!-- prevent double loading of vite client, handled in only_css -->\n"

    assert render_component(&HTML.include_legacy_assets/1) == ""
  end

  test "the host app's hmr: false keeps all manifest branches independent of dev-server settings" do
    Application.put_env(:brando, :hmr, true)
    Application.put_env(@host_app, :hmr, false)
    expected = manifest_output()
    invalid_dev_ports()

    assert manifest_output() == expected
  end

  test "production keeps all asset variants on the manifest" do
    Application.put_env(:brando, :env, :prod)
    Application.put_env(@host_app, :hmr, true)
    expected = manifest_output()
    invalid_dev_ports()

    assert manifest_output() == expected
  end

  test "SSG keeps frontend variants on the manifest" do
    Application.put_env(:brando, :ssg_run, true)
    expected = frontend_manifest_output()
    invalid_dev_ports()

    assert frontend_manifest_output() == expected
  end

  for env <- [:e2e, :test] do
    test "admin still uses its manifest in #{env}" do
      Application.put_env(:brando, :env, unquote(env))
      invalid_dev_ports()
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "/assets/admin.css"
      assert html =~ "/assets/admin.js"
      refute html =~ "@vite/client"
    end
  end

  defp manifest_output do
    admin = render_component(&HTML.include_assets/1, admin: true)
    assert admin =~ "/assets/admin.css"
    assert admin =~ "/assets/admin.js"
    refute admin =~ "@vite/client"

    legacy = render_component(&HTML.include_legacy_assets/1)

    if Application.get_env(@host_app, :hmr) === false do
      assert legacy =~ "/assets/app-legacy.js"
    else
      assert legacy == ""
    end

    [admin, legacy | frontend_manifest_output()]
  end

  defp frontend_manifest_output do
    all = render_component(&HTML.include_assets/1)
    css = render_component(&HTML.include_assets/1, only_css: true)
    js = render_component(&HTML.include_assets/1, only_js: true)
    assert all =~ "/assets/app.css"
    assert all =~ "/assets/app.js"
    assert css =~ "/assets/app.css"
    refute css =~ "/assets/app.js"
    assert js =~ "/assets/app.js"
    refute js =~ "/assets/app.css"
    refute Enum.any?([all, css, js], &String.contains?(&1, "@vite/client"))
    [all, css, js]
  end

  defp invalid_dev_ports do
    System.put_env("BRANDO_VITE_FRONTEND_PORT", "unused")
    System.put_env("BRANDO_VITE_ADMIN_PORT", "unused")
  end

  defp cache(key, value) do
    previous = :persistent_term.get(key, :not_cached)
    :persistent_term.put(key, value)

    on_exit(fn ->
      case previous do
        :not_cached -> :persistent_term.erase(key)
        value -> :persistent_term.put(key, value)
      end
    end)
  end
end
