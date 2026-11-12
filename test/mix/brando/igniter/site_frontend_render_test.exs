defmodule Mix.Brando.Igniter.SiteFrontendRenderTest do
  # Compiles what brando.install and mix brando.gen.site --site plan for an
  # application with tenancy, and requests pages from it. Not async: it
  # defines modules and sets the tenancy configuration.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.IgniterCase
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  # The CMS site's modules, the error pages and the live preview, and each
  # site's frontend.
  @site_files [
    "cms/page_controller.ex",
    "cms/site_context.ex",
    "cms/layouts.ex",
    "cms/page_html.ex",
    "cms/lockdown_controller.ex",
    "cms/lockdown_html.ex",
    "live_preview.ex",
    "controllers/error_html.ex",
    "controllers/error_html/404.html.heex",
    "controllers/error_html/500.html.heex"
  ]

  @error_html """
  defmodule WEB.ErrorHTML do
    @moduledoc \"\"\"
    This module is invoked by your endpoint in case of errors on HTML requests.

    See config/config.exs.
    \"\"\"
    use WEB, :html

    def render(template, _assigns) do
      Phoenix.Controller.status_message_from_template(template)
    end
  end
  """

  defp plan(app, install_options, site_keys) do
    module = app |> to_string() |> Macro.camelize()
    web = "#{module}Web"

    installed =
      [
        app: app,
        module: module,
        files: %{"lib/#{Macro.underscore(web)}/controllers/error_html.ex" => String.replace(@error_html, "WEB", web)}
      ]
      |> IgniterCase.phoenix_project()
      |> Igniter.compose_task(Mix.Tasks.Brando.Install, install_options)

    [] = installed.issues

    Enum.reduce(site_keys, installed, fn key, igniter ->
      planned =
        igniter |> IgniterCase.apply_and_reload() |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Site, ["--site", key])

      [] = planned.issues
      planned
    end)
  end

  # Writes the planned files, each site's made recognizable as an application
  # would make it its own, and compiles them as the application does.
  defp compile!(planned, app, site_keys) do
    web_path = "lib/#{app}_web"

    sites =
      for key <- site_keys, name = Macro.underscore(Macro.camelize(String.replace(key, "-", "_"))) do
        [
          {"sites/#{name}.ex", & &1},
          {"sites/#{name}/layouts.ex",
           &String.replace(&1, ~s(<html class="no-js"), ~s(<html data-site="#{key}" class="no-js"))},
          {"sites/#{name}/page_html.ex",
           &String.replace(&1, ~s(<main id="content">), ~s(<main id="content" data-template="#{key}">))}
        ]
      end

    dir = Path.join(System.tmp_dir!(), "brando-site-frontend-render-#{System.unique_integer([:positive])}")

    files =
      for {path, edit} <- Enum.map(@site_files, &{&1, fn source -> source end}) ++ List.flatten(sites) do
        file = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, edit.(IgniterCase.source(planned, Path.join(web_path, path))))
        file
      end

    {:ok, modules, %{compile_warnings: compile_warnings, runtime_warnings: runtime_warnings}} =
      files
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Kernel.ParallelCompiler.compile(return_diagnostics: true)

    # The application compiles with --warnings-as-errors.
    [] = compile_warnings ++ runtime_warnings

    {dir, modules}
  end

  setup_all do
    compiled = [
      plan(:render_single, ["--tenancy-mode", "single", "--site-key", "render-single"], ["render-single"])
      |> compile!(:render_single, ["render-single"]),
      plan(:render_multi, ["--tenancy-mode", "multi"], ["acme-render", "globex-render"])
      |> compile!(:render_multi, ["acme-render", "globex-render"])
    ]

    on_exit(fn ->
      for {dir, modules} <- compiled do
        File.rm_rf!(dir)

        for module <- modules do
          :code.purge(module)
          :code.delete(module)
        end
      end
    end)

    :ok
  end

  # The tenant content a page request reads: its schema is not migrated here.
  @content_tables "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename ~ '^(pages|content_|sites_)'"

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, nil)
    put_test_env(:default_site_frontend, nil)
    put_test_env(:page_html_module, Module.concat(RenderMultiWeb, CMS.PageHTML))
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()
    Cachex.clear(:query)

    # The site caches the layouts read (palettes, SEO) are kept per prefix,
    # and these schemas go with the test's transaction.
    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      Cachex.clear(:query)
      Cachex.clear(:cache)
    end)

    user = Brando.Factory.insert(:random_user)

    for key <- ["acme-render", "globex-render"] do
      {:ok, site} =
        Registry.create_site(%{
          name: key,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, _} =
        Registry.create_environment(site, %{name: "Production", key: "production", live: true, domain: "www.#{key}.test"},
          actor: :system
        )

      prefix = "tenant_#{key}_production"
      BrandoIntegration.Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

      %{rows: tables} = BrandoIntegration.Repo.query!(@content_tables)

      for [table] <- tables,
          do: BrandoIntegration.Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)

      page =
        Brando.Factory.build(:page,
          uri: "index",
          template: "index.html",
          title: "#{key} home",
          rendered_blocks: "<p>#{key} page</p>",
          creator: nil,
          creator_id: user.id
        )

      Tenant.with_prefix(prefix, fn -> Brando.Repo.insert!(page) end)
    end

    :ok
  end

  # Compiled in setup_all, so not named literally: the compiler would warn.
  defp module(name), do: Module.concat(RenderMultiWeb, name)

  defp request(host) do
    controller = module(CMS.PageController)

    :get
    |> Plug.Test.conn("https://#{host}/")
    |> Map.put(:host, host)
    |> Plug.Conn.assign(:language, "en")
    |> Brando.Plug.Tenant.call([])
    |> Phoenix.Controller.put_format("html")
    |> controller.call(controller.init(:index))
  end

  defp site(conn), do: conn.resp_body |> Floki.parse_document!() |> Floki.attribute("html", "data-site")
  defp template(conn), do: conn.resp_body |> Floki.parse_document!() |> Floki.attribute("main", "data-template")

  test "with two sites registered, each renders in its own layout and template" do
    put_test_env(:site_frontends, %{
      "acme-render" => module(Sites.AcmeRender),
      "globex-render" => module(Sites.GlobexRender)
    })

    for key <- ["acme-render", "globex-render"] do
      conn = request("www.#{key}.test")
      assert conn.status == 200
      assert site(conn) == [key]
      assert template(conn) == [key]
      assert conn.resp_body =~ "<p>#{key} page</p>"
    end
  end

  test "with none registered, every site renders the CMS site's layout and template" do
    for key <- ["acme-render", "globex-render"] do
      conn = request("www.#{key}.test")
      assert conn.status == 200
      assert site(conn) == []
      assert template(conn) == []
      assert conn.resp_body =~ ~s(<html class="no-js" lang="en">)
      assert conn.resp_body =~ "<p>#{key} page</p>"
    end
  end

  test "the live preview renders a site's page in its layout and template, with its assigns" do
    put_test_env(:site_frontends, %{"acme-render" => module(Sites.AcmeRender)})
    Tenant.put_prefix("tenant_acme-render_production")

    [target] = Spark.Dsl.Extension.get_entities(module(LivePreview), [:live_preview])
    page = %Brando.Pages.Page{template: "index.html", uri: "index", language: :en}

    assert target.layout.(page) == {module(Sites.AcmeRender.Layouts), :root}
    assert target.template.(page) == {module(Sites.AcmeRender.PageHTML), "index.html"}
    assert target.site_assigns
  end

  test "an error page renders in the site's layout, and bare for a site without a frontend" do
    put_test_env(:site_frontends, %{"acme-render" => module(Sites.AcmeRender)})
    error_html = module(ErrorHTML)

    Tenant.put_prefix("tenant_acme-render_production")
    conn = Plug.Conn.assign(build_conn(), :partials, %{})
    html = Phoenix.Template.render_to_string(error_html, "404", "html", conn: conn)
    assert html =~ ~s(<html data-site="acme-render" class="no-js")
    assert html =~ "Page not found"

    Tenant.put_prefix("tenant_globex-render_production")
    html = Phoenix.Template.render_to_string(error_html, "404", "html", conn: conn)
    refute html =~ "data-site"
    refute html =~ ~s(id="top")
    assert html =~ "Page not found"
  end
end
