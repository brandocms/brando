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

    for role <- [:admin, :site], do: cache({Brando.Vite, :start_failure, role}, nil)

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
      assert html =~ "Admin assets failed to load from http://localhost:3334"
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

  describe "the notice when the site's dev server scripts fail to load in development" do
    test "waits for the dev server's scripts to fail, and names the server" do
      System.put_env("BRANDO_VITE_FRONTEND_PORT", "3001")

      for html <- [render_component(&HTML.include_assets/1), render_component(&HTML.include_assets/1, only_css: true)] do
        assert html =~ ~s(<template id="brando-site-assets-notice">)
        assert html =~ "Site assets failed to load from http://localhost:3001"
        assert html =~ "<code>assets/frontend</code>"
        # Both causes: no dev server, or one that fails to compile a module
        assert html =~ "is not running, or it could not compile a module"
        # Both setups: the Brando.Vite watchers, or a dev server run by hand
        assert html =~ "include <code>Brando.Vite</code>; otherwise run <code>pnpm dev</code>"
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

  describe "when this app's Brando.Vite watcher could not start Vite" do
    # In development the page reads the build's manifests afresh, from the
    # application's directory with HMR on
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Application.put_env(@host_app, :hmr, true)
      write_manifest(tmp_dir, "admin_manifest.json", "src/main.js", "admin")
      write_manifest(tmp_dir, "manifest.json", "js/index.js", "app")

      cwd = File.cwd!()
      File.cd!(tmp_dir)
      on_exit(fn -> File.cd!(cwd) end)

      :ok
    end

    test "the admin uses its build and says why, rather than load what holds the port" do
      vite_failed(:admin, {:port_in_use, "3333"})
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "/assets/admin.css"
      assert html =~ "/assets/admin.js"
      refute html =~ "localhost:3333"
      refute html =~ "@vite/client"

      assert html =~ ~s(<template id="brando-admin-assets-notice">)
      assert html =~ "Vite for the admin did not start: port 3333 is already in use"
      assert html =~ "<code>BRANDO_VITE_ADMIN_PORT</code>"
      refute html =~ "BRANDO_VITE_FRONTEND_PORT"
      assert html =~ "uses the last build in <code>priv/static</code>"
      assert html =~ ~s|brandoAssetsMissing("brando-admin-assets-notice");|

      # The site's Vite started, so the site still loads from it
      assert frontend_scripts() == @frontend_html
    end

    test "the site uses its build and says why, once, from the head's styles" do
      vite_failed(:site, {:port_in_use, "3000"})

      all = render_component(&HTML.include_assets/1)
      css = render_component(&HTML.include_assets/1, only_css: true)
      js = render_component(&HTML.include_assets/1, only_js: true)

      for html <- [all, css, js], do: refute(html =~ "localhost:3000")
      assert all =~ "/assets/app.css"
      assert all =~ "/assets/app.js"
      assert css =~ "/assets/app.css"
      refute css =~ "/assets/app.js"
      assert js =~ "/assets/app.js"

      for html <- [all, css] do
        assert html =~ ~s(<template id="brando-site-assets-notice">)
        assert html =~ "Vite for the site did not start: port 3000 is already in use"
        assert html =~ "<code>BRANDO_VITE_FRONTEND_PORT</code>"
        assert html =~ ~s|brandoAssetsMissing("brando-site-assets-notice");|
      end

      refute js =~ "brando-site-assets-notice"
      assert admin_scripts() == @admin_html
    end

    test "names the exit status, or what to do, for other failures" do
      vite_failed(:admin, {:exited, 3})
      html = render_component(&HTML.include_assets/1, admin: true)
      assert html =~ "Vite for the admin did not start"
      assert html =~ "It exited with status 3 before it was ready"

      vite_failed(:site, {:not_started, "node is not on the PATH. Install Node.js, then restart the server."})
      html = render_component(&HTML.include_assets/1)
      assert html =~ "Vite for the site did not start"
      assert html =~ "node is not on the PATH. Install Node.js"
    end

    test "says when Vite stopped with an error after it was ready" do
      vite_failed(:admin, {:stopped, 1})
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "Vite for the admin stopped"
      assert html =~ "It exited with status 1;"
      refute html =~ "did not start"
      assert html =~ "/assets/admin.js"
      refute html =~ "localhost:3333"
    end

    test "says there is no build to use when there is none" do
      vite_failed(:admin, {:port_in_use, "3333"})
      File.rm!("priv/static/admin_manifest.json")
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "There is no build to use instead: run <code>pnpm build</code>"
      refute html =~ "uses the last build"
      refute html =~ "Admin assets not built"
    end

    test "picks up a build made after the first render", %{tmp_dir: tmp_dir} do
      vite_failed(:admin, {:port_in_use, "3333"})
      vite_failed(:site, {:port_in_use, "3000"})
      cache(Brando.Tenant.cache_key({:vite, "critical_css"}), nil)
      File.rm!("priv/static/admin_manifest.json")
      File.rm!("priv/static/manifest.json")

      assert render_component(&HTML.include_assets/1, admin: true) =~ "There is no build to use instead"
      refute render_component(&HTML.include_assets/1) =~ "/assets/app.js"
      assert render_component(&HTML.inject_critical_css/1) =~ "no critical css"

      # pnpm build, with the page still open
      write_manifest(tmp_dir, "admin_manifest.json", "src/main.js", "admin-new")
      File.mkdir_p!("priv/static/assets")
      File.write!("priv/static/assets/critical.css", ".critical{color:red}")

      File.write!(
        "priv/static/manifest.json",
        Jason.encode!(%{
          "js/index.js" => %{"file" => "assets/app-new.js", "css" => ["assets/app-new.css"], "isEntry" => true},
          "js/critical.js" => %{"file" => "assets/critical.js", "css" => ["assets/critical.css"], "isEntry" => true}
        })
      )

      admin = render_component(&HTML.include_assets/1, admin: true)
      assert admin =~ "/assets/admin-new.js"
      assert admin =~ "uses the last build"
      refute admin =~ "There is no build"

      site = render_component(&HTML.include_assets/1)
      assert site =~ "/assets/app-new.js"
      assert site =~ "/assets/app-new.css"
      assert render_component(&HTML.inject_critical_css/1) =~ ".critical{color:red}"
    end

    test "the head decides once where the site's styles and scripts come from" do
      # The head reads the palettes, in a process of its own
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(BrandoIntegration.Repo)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      cache(Brando.Tenant.cache_key({:vite, "critical_css"}), "/* no critical css */")
      vite_failed(:site, {:port_in_use, "3000"})

      # A Vite that starts between two reads of the record would give the page
      # the build's styles and no scripts, so the head may read it only once
      mfa = {Brando.Vite, :start_failure, 1}
      :erlang.trace_pattern(mfa, true, [:local])
      on_exit(fn -> :erlang.trace_pattern(mfa, false, [:local]) end)
      test = self()

      renderer =
        spawn_link(fn ->
          receive do: (:render -> :ok)

          # Rendered as a controller renders a layout, without LiveView's diff
          html =
            %{__changed__: nil, conn: head_conn()}
            |> head_assigns()
            |> HTML.head()
            |> Phoenix.HTML.Safe.to_iodata()
            |> IO.iodata_to_binary()

          send(test, {:head, html})
        end)

      Ecto.Adapters.SQL.Sandbox.allow(BrandoIntegration.Repo, owner, renderer)
      :erlang.trace(renderer, true, [:call, {:tracer, self()}])
      send(renderer, :render)
      assert_receive {:head, html}, 5_000
      ref = :erlang.trace_delivered(renderer)
      assert_receive {:trace_delivered, ^renderer, ^ref}

      assert record_reads(:site) == 1
      assert html =~ "/assets/app.css"
      assert html =~ "/assets/app.js"
      refute html =~ "localhost:3000"
      assert html =~ "Vite for the site did not start"
    end

    test "the notice can be closed" do
      vite_failed(:admin, {:port_in_use, "3333"})
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ ~s(<button type="button" class="brando-assets-notice-close" aria-label="Close this notice")
      assert html =~ ~s|onclick="this.parentNode.remove()"|
    end

    test "hmr: false renders the build as before, without the notice" do
      Application.put_env(@host_app, :hmr, false)
      vite_failed(:admin, {:port_in_use, "3333"})
      vite_failed(:site, {:port_in_use, "3000"})

      refute render_component(&HTML.include_assets/1, admin: true) =~ "assets-notice"
      refute render_component(&HTML.include_assets/1) =~ "assets-notice"
    end

    test "outside development the build loads without the notice" do
      Application.put_env(:brando, :env, :staging)
      vite_failed(:admin, {:port_in_use, "3333"})
      html = render_component(&HTML.include_assets/1, admin: true)

      assert html =~ "/assets/admin.js"
      refute html =~ "localhost:3333"
      refute html =~ "assets-notice"
    end
  end

  defp vite_failed(role, reason) do
    dir = if role == :admin, do: "assets/backend", else: "assets/frontend"
    :persistent_term.put({Brando.Vite, :start_failure, role}, %{dir: dir, reason: reason})
  end

  defp head_conn, do: %Plug.Conn{assigns: %{language: "en"}, private: %{plug_session: %{}}}

  # HTML.head/1's defaults, which a call outside a template does not apply
  defp head_assigns(assigns) do
    slots =
      ~w(pragma title preconnect async_scripts import_styles scripts styles preload deferred_scripts prefetch inner_block)a

    slots
    |> Map.new(&{&1, []})
    |> Map.merge(%{charset: "utf-8", viewport: "width=device-width", fonts: [], ignored_chunks: []})
    |> Map.merge(assigns)
  end

  defp record_reads(role, count \\ 0) do
    receive do
      {:trace, _pid, :call, {Brando.Vite, :start_failure, [^role]}} -> record_reads(role, count + 1)
    after
      0 -> count
    end
  end

  # A Vite build's manifest, with one entry and its stylesheet
  defp write_manifest(dir, name, entry, file) do
    path = Path.join(dir, "priv/static/#{name}")
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(%{entry => %{"file" => "assets/#{file}.js", "css" => ["assets/#{file}.css"], "isEntry" => true}})
    )
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
