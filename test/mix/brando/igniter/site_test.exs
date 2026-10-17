defmodule Mix.Brando.Igniter.SiteTest do
  use ExUnit.Case, async: false
  alias Brando.IgniterCase

  defp project(extra_routes \\ ~s(get "/", PageController, :home), files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        %{
          "lib/studio_web/router.ex" => """
          defmodule StudioWeb.Router do
            use StudioWeb, :router
            import Brando.Router
            pipeline :browser do
              plug :accepts, ["html"]
            end
            admin_routes "/admin" do
              live "/", StudioAdmin.DashboardLive
            end
            scope "/", StudioWeb do
              pipe_through :browser
              get "/health", HealthController, :show
              #{extra_routes}
            end
          end
          """,
          "lib/studio_web/controllers/page_controller.ex" => "# Existing Phoenix controller\n",
          "lib/studio_web/controllers/page_html/home.html.heex" => "Existing Phoenix homepage",
          "lib/studio_web/components/layouts/root.html.heex" => "Existing Phoenix layout"
        }
        |> Map.merge(files)
    )
  end

  defp generate(project, options \\ []), do: Igniter.compose_task(project, Mix.Tasks.Brando.Gen.Site, options)

  # A new phx.new application, before Brando: its homepage as phx.new wrote it.
  @phx_home File.read!(Path.expand("../../../fixtures/phx_new/home.html.heex", __DIR__))
  @phx_page_controller """
  defmodule StudioWeb.PageController do
    use StudioWeb, :controller

    def home(conn, _params) do
      render(conn, :home)
    end
  end
  """

  defp fresh(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "lib/studio_web/router.ex" => """
            defmodule StudioWeb.Router do
              use StudioWeb, :router
              pipeline :browser do
                plug :accepts, ["html"]
              end
              scope "/", StudioWeb do
                pipe_through :browser
                get "/", PageController, :home
              end
            end
            """,
            "lib/studio_web/controllers/page_controller.ex" => @phx_page_controller,
            "lib/studio_web/controllers/page_html/home.html.heex" => @phx_home
          },
          files
        )
    )
  end

  defp install(project, options \\ ["--yes"]), do: Igniter.compose_task(project, Mix.Tasks.Brando.Install, options)

  # A new application's router with `routes` in its browser scope, and
  # `pipeline` as its browser pipeline.
  defp fresh_router(routes, pipeline \\ :browser) do
    %{
      "lib/studio_web/router.ex" => """
      defmodule StudioWeb.Router do
        use StudioWeb, :router
        pipeline #{inspect(pipeline)} do
          plug :accepts, ["html"]
        end
        scope "/", StudioWeb do
          pipe_through #{inspect(pipeline)}
          #{routes}
        end
      end
      """
    }
  end

  describe "a new install" do
    test "adds the site, in place of phx.new's unchanged homepage" do
      result = install(fresh())
      assert result.issues == []
      assert Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex")

      router = IgniterCase.source(result, "lib/studio_web/router.ex")
      refute router =~ ~r/get\(?"\/", PageController, :home/
      assert router =~ ~r/get\(?"\/", StudioWeb.CMS.PageController, :index, as: :page/
      assert Enum.any?(result.notices, &(&1 =~ "CMS pages now answer /"))

      for path <- ["lib/studio_web/controllers/page_controller.ex", "lib/studio_web/controllers/page_html/home.html.heex"] do
        Igniter.Test.assert_unchanged(result, path)
      end
    end

    test "keeps a homepage the application has changed, without the site, with a notice" do
      for files <- [
            %{"lib/studio_web/controllers/page_html/home.html.heex" => @phx_home <> "<p>Our studio</p>\n"},
            %{
              "lib/studio_web/controllers/page_controller.ex" =>
                String.replace(@phx_page_controller, "render(conn, :home)", "render(conn, :home, news: [])")
            }
          ] do
        result = install(fresh(files))
        assert result.issues == []
        refute Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex")
        assert IgniterCase.source(result, "lib/studio_web/router.ex") =~ ~r/get\(?"\/", PageController, :home/

        assert Enum.any?(
                 result.notices,
                 &(&1 =~ "is not the one mix phx.new generates, so it was kept" and
                     &1 =~ "mix brando.gen.site --replace-phoenix-home")
               )
      end
    end

    test "leaves the site out with --no-public-site, and a rerun does not add it" do
      result = install(fresh(), ["--yes", "--no-public-site"])
      assert result.issues == []
      refute Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex")
      assert IgniterCase.source(result, "lib/studio_web/router.ex") =~ ~r/get\(?"\/", PageController, :home/

      rerun = result |> IgniterCase.apply_and_reload() |> install()
      assert rerun.issues == []
      refute Igniter.exists?(rerun, "lib/studio_web/cms/page_controller.ex")
      Igniter.Test.assert_unchanged(rerun, "lib/studio_web/router.ex")
    end

    test "leaves out a site it can't add, saying why and how to add it later, and installs the admin" do
      for {files, named, later} <- [
            {fresh_router(~s(live "/", HomeLive)), ~s(live "/", StudioWeb.HomeLive), "mix brando.gen.site\n"},
            {fresh_router(~s(get "/", PageController, :index)), ~s(get "/", StudioWeb.PageController, :index),
             "mix brando.gen.site\n"},
            {fresh_router(~s(get "/", PageController, :home\nget "/:slug", PostController, :show)),
             ~s(get "/:slug", StudioWeb.PostController, :show), "mix brando.gen.site --replace-phoenix-home\n"},
            {fresh_router(~s(get "/*path", SPAController, :show)), ~s(get "/*path", StudioWeb.SPAController, :show),
             "mix brando.gen.site\n"},
            {%{
               "lib/studio_web/router.ex" => """
               defmodule StudioWeb.Router do
                 use StudioWeb, :router
                 pipeline :browser do
                   plug :accepts, ["html"]
                 end
                 scope "/:locale", StudioWeb do
                   pipe_through :browser
                   get "/", PageController, :home
                 end
               end
               """
             }, ~s(get "/:locale", StudioWeb.PageController, :home), "mix brando.gen.site\n"}
          ] do
        result = install(fresh(files))
        assert result.issues == [], named
        router = IgniterCase.source(result, "lib/studio_web/router.ex")
        assert router =~ "admin_routes", named
        refute router =~ "brando_site", named
        refute Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex"), named

        assert Enum.any?(
                 result.notices,
                 &(&1 =~ "The CMS public site was not added: routes in the router already answer" and &1 =~ named and
                     String.ends_with?(&1, later))
               ),
               named
      end
    end

    test "leaves out the site when the router has no :browser pipeline for it" do
      api_only = %{
        "lib/studio_web/router.ex" => """
        defmodule StudioWeb.Router do
          use StudioWeb, :router
          pipeline :api do
            plug :accepts, ["json"]
          end
          scope "/api", StudioWeb do
            pipe_through :api
          end
        end
        """
      }

      for {files, later} <- [
            {api_only, "mix brando.gen.site\n"},
            {fresh_router(~s(get "/", PageController, :home), :public_browser),
             "mix brando.gen.site --replace-phoenix-home\n"}
          ] do
        result = install(fresh(files))
        assert result.issues == []
        router = IgniterCase.source(result, "lib/studio_web/router.ex")
        assert router =~ "admin_routes"
        refute router =~ "brando_site"
        refute router =~ ~r/pipe_through[ (]?:browser/
        refute Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex")

        assert Enum.any?(
                 result.notices,
                 &(&1 =~ "The CMS public site was not added: the router has no :browser pipeline" and
                     String.ends_with?(&1, later))
               )
      end

      generated = fresh(api_only) |> install(["--yes", "--no-public-site"]) |> IgniterCase.apply_and_reload()
      assert [issue] = generate(generated, ["--yes"]).issues
      assert issue =~ "The router has no :browser pipeline"
    end

    test "has no --public-site: the site is the default, and mix brando.gen.site adds it later" do
      result = install(fresh(), ["--yes", "--public-site"])
      assert Enum.any?(result.issues, &(&1 =~ "add it to an installed application with mix brando.gen.site"))
    end
  end

  test "homepage replacement is explicit and preserves Phoenix source files and nested routes" do
    result =
      project("""
      get "/", PageController, :home
      scope "/campaign" do
        get "/", PageController, :home
      end
      """)
      |> generate(["--replace-phoenix-home", "--yes"])

    assert result.issues == []

    for path <- [
          "lib/studio_web/controllers/page_controller.ex",
          "lib/studio_web/controllers/page_html/home.html.heex",
          "lib/studio_web/components/layouts/root.html.heex"
        ] do
      Igniter.Test.assert_unchanged(result, path)
    end

    source = IgniterCase.source(result, "lib/studio_web/router.ex")
    assert length(Regex.scan(~r/:home/, source)) == 1
    assert source =~ "CMS.SiteContext"
    assert source =~ "as: :page"
    assert IgniterCase.source(result, "config/brando.exs") =~ "page_html_module: StudioWeb.CMS.PageHTML"
    assert result.tasks == []
    rerun = result |> IgniterCase.apply_and_reload() |> generate()
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "a site generated before 0.55 still owns its routes through the controllers' old names" do
    generated = project() |> generate(["--replace-phoenix-home", "--yes"]) |> IgniterCase.apply_and_reload()
    path = "lib/studio_web/router.ex"
    router = IgniterCase.source(generated, path)
    assert router =~ "BrandoWeb.SEOController"
    legacy_router = String.replace(router, ~r/BrandoWeb\.(SEO|Sitemap|Preview)Controller/, "Brando.\\1Controller")

    legacy =
      generated
      |> Igniter.update_file(path, &Rewrite.Source.update(&1, :content, fn _ -> legacy_router end))
      |> IgniterCase.apply_and_reload()

    rerun = generate(legacy)
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "yes alone never claims an existing homepage and custom route ownership blocks" do
    for {route, options} <- [
          {~s(get "/", PageController, :home), ["--yes"]},
          {~s(get "/", LandingController, :index), ["--yes", "--replace-phoenix-home"]},
          {~s(get "/*path", SPAController, :show), ["--replace-phoenix-home"]},
          {~s(get "/robots.txt", RobotsController, :show), []},
          {~s(get "/:slug", ExistingController, :show), []},
          {~s(get "/:section/:slug", ExistingController, :show), []},
          {~s(resources "/:collection", ExistingController), []},
          {~s(forward "/", ExistingPlug), []}
        ] do
      result = project(route) |> generate(options)
      assert result.issues != []
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "parameterized routes outside CMS support paths keep their ownership" do
    result = project(~s(get "/blog/:slug", ExistingController, :show)) |> generate()
    assert result.issues == []
    assert IgniterCase.source(result, "lib/studio_web/router.ex") =~ ~s("/blog/:slug")
  end

  test "guidance records an explicit homepage answer and handles decline or closed input" do
    Mix.shell(Mix.Shell.Process)

    for {answer, accepted?} <- [{"yes", true}, {"no", false}, {:eof, false}] do
      send(self(), {:mix_shell_input, :prompt, answer})
      result = project() |> generate(["--interactive"])
      assert result.issues == [] == accepted?
      assert_received {:mix_shell, :prompt, _}
      unless accepted?, do: Igniter.Test.assert_unchanged(result)
    end
  end

  test "replacing the homepage retires the generated request test and preserves a customized one" do
    generated = """
    defmodule StudioWeb.PageControllerTest do
      use StudioWeb.ConnCase

      test "GET /", %{conn: conn} do
        conn = get(conn, ~p"/")
        assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
      end
    end
    """

    path = "test/studio_web/controllers/page_controller_test.exs"

    result =
      IgniterCase.phoenix_project(
        files: %{
          "lib/studio_web/router.ex" => """
          defmodule StudioWeb.Router do
            use StudioWeb, :router
            import Brando.Router
            pipeline :browser do
              plug :accepts, ["html"]
            end
            admin_routes "/admin" do
              live "/", StudioAdmin.DashboardLive
            end
            scope "/", StudioWeb do
              pipe_through :browser
              get "/", PageController, :home
            end
          end
          """,
          path => generated
        }
      )
      |> generate(["--replace-phoenix-home", "--yes"])

    assert result.issues == []
    assert path in result.rms
    assert Enum.any?(result.notices, &String.contains?(&1, "Removed #{path}"))

    customized =
      IgniterCase.phoenix_project(
        files: %{
          "lib/studio_web/router.ex" => """
          defmodule StudioWeb.Router do
            use StudioWeb, :router
            import Brando.Router
            pipeline :browser do
              plug :accepts, ["html"]
            end
            admin_routes "/admin" do
              live "/", StudioAdmin.DashboardLive
            end
            scope "/", StudioWeb do
              pipe_through :browser
              get "/", PageController, :home
            end
          end
          """,
          path => """
          defmodule StudioWeb.PageControllerTest do
            use StudioWeb.ConnCase

            test "GET /", %{conn: conn} do
              conn = get(conn, ~p"/")
              assert html_response(conn, 200) =~ "Our studio"
            end

            test "GET /health", %{conn: conn} do
              assert get(conn, "/health").status == 200
            end
          end
          """
        }
      )
      |> generate(["--replace-phoenix-home", "--yes"])

    assert customized.issues == []
    assert customized.rms == []
    assert Enum.any?(customized.notices, &String.contains?(&1, "was preserved"))
  end

  test "site generation composes with installation and custom owned files block replacement" do
    result = install(fresh(), [])
    assert result.issues == []
    assert Igniter.exists?(result, "lib/studio_web/cms/page_controller.ex")

    customized =
      project("")
      |> Igniter.create_new_file(
        "lib/studio_web/cms/page_html.ex",
        "defmodule StudioWeb.CMS.PageHTML do\n def custom, do: :ok\nend"
      )
      |> generate(["--yes"])

    assert Enum.any?(customized.issues, &String.contains?(&1, "already contains different content"))
  end

  @error_html "lib/studio_web/controllers/error_html.ex"
  @error_test "test/studio_web/controllers/error_html_test.exs"

  # phx.new 1.8's ErrorHTML and its test, comments included.
  @phoenix_error_html """
  defmodule StudioWeb.ErrorHTML do
    @moduledoc \"\"\"
    This module is invoked by your endpoint in case of errors on HTML requests.

    See config/config.exs.
    \"\"\"
    use StudioWeb, :html

    # If you want to customize your error pages,
    # uncomment the embed_templates/1 call below
    # and add pages to the error directory:
    #
    #   * lib/studio_web/controllers/error_html/404.html.heex
    #   * lib/studio_web/controllers/error_html/500.html.heex
    #
    # embed_templates "error_html/*"

    # The default is to render a plain text page based on
    # the template name. For example, "404.html" becomes
    # "Not Found".
    def render(template, _assigns) do
      Phoenix.Controller.status_message_from_template(template)
    end
  end
  """

  @phoenix_error_test """
  defmodule StudioWeb.ErrorHTMLTest do
    use StudioWeb.ConnCase, async: true

    # Bring render_to_string/4 for testing custom views
    import Phoenix.Template, only: [render_to_string: 4]

    test "renders 404.html" do
      assert render_to_string(StudioWeb.ErrorHTML, "404", "html", []) == "Not Found"
    end

    test "renders 500.html" do
      assert render_to_string(StudioWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
    end
  end
  """

  defp with_files(files), do: project(~s(get "/", PageController, :home), files)

  test "phx.new's ErrorHTML and its test give way to the site's error pages, once" do
    result =
      %{@error_html => @phoenix_error_html, @error_test => @phoenix_error_test}
      |> with_files()
      |> generate(["--replace-phoenix-home", "--yes"])

    assert result.issues == []
    error_html = IgniterCase.source(result, @error_html)
    assert error_html =~ ~s(embed_templates "error_html/*")
    assert error_html =~ "StudioWeb.CMS.Layouts.root()"
    assert IgniterCase.source(result, "lib/studio_web/controllers/error_html/404.html.heex") =~ "<.error_page"
    assert IgniterCase.source(result, "lib/studio_web/controllers/error_html/500.html.heex") =~ "<.error_page"
    assert IgniterCase.source(result, @error_test) =~ "StudioWeb.CMS.Layouts, :root"
    refute IgniterCase.source(result, @error_test) =~ ~s(== "Not Found")

    rerun = result |> IgniterCase.apply_and_reload() |> generate()
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "phx.new 1.7's ErrorHTML (no @moduledoc before 1.7.12) and test are recognized too" do
    phoenix_17_html = String.replace(@phoenix_error_html, ~r/  @moduledoc """.*?"""\n/s, "")

    phoenix_17_test =
      String.replace(
        @phoenix_error_test,
        "import Phoenix.Template, only: [render_to_string: 4]",
        "import Phoenix.Template"
      )

    refute phoenix_17_html =~ "@moduledoc"

    for html <- [@phoenix_error_html, phoenix_17_html] do
      result =
        %{@error_html => html, @error_test => phoenix_17_test}
        |> with_files()
        |> generate(["--replace-phoenix-home", "--yes"])

      assert result.issues == []
      assert IgniterCase.source(result, @error_html) =~ "StudioWeb.CMS.Layouts.root()"
      assert IgniterCase.source(result, @error_test) =~ "StudioWeb.CMS.Layouts, :root"
      refute Enum.any?(result.notices, &(&1 =~ "customized" or &1 =~ "was kept"))
    end
  end

  test "a customized ErrorHTML or error test is kept, with a notice" do
    customized = String.replace(@phoenix_error_html, "# embed_templates", "embed_templates")

    result = %{@error_html => customized} |> with_files() |> generate(["--replace-phoenix-home", "--yes"])

    assert result.issues == []
    Igniter.Test.assert_unchanged(result, @error_html)
    refute Igniter.exists?(result, "lib/studio_web/controllers/error_html/404.html.heex")
    assert Enum.any?(result.notices, &(&1 =~ "#{@error_html} is customized"))

    own_test = String.replace(@phoenix_error_test, ~s(== "Not Found"), ~s(=~ "Not Found"))

    kept_test =
      %{@error_html => @phoenix_error_html, @error_test => own_test}
      |> with_files()
      |> generate(["--replace-phoenix-home", "--yes"])

    assert kept_test.issues == []
    Igniter.Test.assert_unchanged(kept_test, @error_test)
    assert Enum.any?(kept_test.notices, &(&1 =~ "#{@error_test} was kept"))
  end

  test "the lockdown page is routed outside the site pipeline, which locks CMS pages" do
    result = project() |> generate(["--replace-phoenix-home", "--yes"])
    assert result.issues == []
    assert Igniter.exists?(result, "lib/studio_web/cms/lockdown_controller.ex")
    assert Igniter.exists?(result, "lib/studio_web/cms/lockdown_html.ex")

    router = IgniterCase.source(result, "lib/studio_web/router.ex")
    [pipeline, after_pipeline] = String.split(router, ~r/pipeline\(?\s*:brando_site/, parts: 2)
    refute pipeline =~ "Lockdown"
    [site_pipeline, _] = String.split(after_pipeline, "end", parts: 2)
    assert site_pipeline =~ ~r/plug\(?Brando\.Plug\.Lockdown\)?\s+plug\(?StudioWeb\.CMS\.SiteContext/
    [before_catchall, _] = String.split(router, ~s("/*path"), parts: 2)
    assert before_catchall =~ ~r/scope\(?\s*"\/coming-soon"/
    assert before_catchall =~ ~r/get\(?"\/", StudioWeb\.CMS\.LockdownController, :index, as: :lockdown/
    assert before_catchall =~ ~r/post\(?"\/", StudioWeb\.CMS\.LockdownController, :unlock, as: :lockdown/
  end

  test "a site generated without the lockdown page gets it on a rerun" do
    generated = project() |> generate(["--replace-phoenix-home", "--yes"]) |> IgniterCase.apply_and_reload()
    path = "lib/studio_web/router.ex"

    earlier =
      generated
      |> IgniterCase.source(path)
      |> String.replace(~r/\s*plug\(?Brando\.Plug\.Lockdown\)?/, "")
      |> String.replace(~r/scope\(?\s*"\/coming-soon".*?\n  end\n/s, "")

    refute earlier =~ "Lockdown"

    rerun =
      generated
      |> Igniter.update_file(path, &Rewrite.Source.update(&1, :content, fn _ -> earlier end))
      |> IgniterCase.apply_and_reload()
      |> generate()

    assert rerun.issues == []
    router = IgniterCase.source(rerun, path)
    assert router =~ ~r/plug\(?Brando\.Plug\.Lockdown\)?\s+plug\(?StudioWeb\.CMS\.SiteContext/
    [before_catchall, _] = String.split(router, ~s("/*path"), parts: 2)
    assert before_catchall =~ "StudioWeb.CMS.LockdownController, :unlock"

    again = rerun |> IgniterCase.apply_and_reload() |> generate()
    assert again.issues == []
    Igniter.Test.assert_unchanged(again)
  end

  test "an application's own /coming-soon routes keep the lockdown page" do
    result =
      project("""
      get "/", PageController, :home
      scope "/coming-soon" do
        get "/", LockdownController, :index
        post "/", LockdownController, :post_password
      end
      """)
      |> generate(["--replace-phoenix-home", "--yes"])

    assert result.issues == []
    refute Igniter.exists?(result, "lib/studio_web/cms/lockdown_controller.ex")
    refute IgniterCase.source(result, "lib/studio_web/router.ex") =~ "Brando.Plug.Lockdown"
    assert Enum.any?(result.notices, &(&1 =~ "StudioWeb.LockdownController already serve /coming-soon"))
  end

  @live_preview "lib/studio_web/live_preview.ex"

  test "installing with the public site previews CMS pages in the CMS layout and templates" do
    result = install(fresh(), [])
    assert result.issues == []

    preview = IgniterCase.source(result, @live_preview)
    assert preview =~ "preview_target Pages.Page do"
    assert preview =~ "layout {StudioWeb.CMS.Layouts, :root}"
    assert preview =~ "template fn page -> {StudioWeb.CMS.PageHTML, page.template} end"
    assert preview =~ "template_prop :page"
    assert preview =~ ~s|Pages.get_fragments(%{filter: %{parent_key: "partials", language: language}})|
  end

  test "the LivePreview brando.install wrote gets the page target, once; a missing one is created" do
    bare = Mix.Brando.Igniter.Site.LivePreview.bare(StudioWeb.LivePreview)
    result = project("", %{@live_preview => bare}) |> generate(["--yes"])
    assert IgniterCase.source(result, @live_preview) =~ "preview_target Pages.Page do"

    rerun = result |> IgniterCase.apply_and_reload() |> generate()
    Igniter.Test.assert_unchanged(rerun, @live_preview)

    # Formatted on creation: without Brando's formatter, as here, the DSL gets parentheses.
    created = project("") |> generate(["--yes"])
    assert code(IgniterCase.source(created, @live_preview)) == code(IgniterCase.source(result, @live_preview))
  end

  defp code(source), do: source |> Sourceror.parse_string!() |> Sourceror.strip_meta()

  test "a LivePreview that already previews pages is kept; a customized one gets a notice" do
    own_page = """
    defmodule StudioWeb.LivePreview do
      use Brando.LivePreview

      preview_target Brando.Pages.Page do
        layout {StudioWeb.Layouts, "app"}
        template {StudioWeb.PageHTML, "show"}
      end
    end
    """

    result = project("", %{@live_preview => own_page}) |> generate(["--yes"])
    Igniter.Test.assert_unchanged(result, @live_preview)
    refute Enum.any?(result.notices, &(&1 =~ "no preview target for Brando.Pages.Page"))

    own_project = String.replace(own_page, "Brando.Pages.Page", "Studio.Projects.Project")
    result = project("", %{@live_preview => own_project}) |> generate(["--yes"])
    Igniter.Test.assert_unchanged(result, @live_preview)

    assert Enum.any?(
             result.notices,
             &(&1 =~ "#{@live_preview} is customized and has no preview target for Brando.Pages.Page" and
                 &1 =~ "layout {StudioWeb.CMS.Layouts, :root}")
           )
  end

  @robots "priv/static/robots.txt"
  @phx_robots File.read!(Path.expand("../../../fixtures/phx_new/robots.txt", __DIR__))
  # phx.new's web module, as far as Plug.Static and the installer read it.
  @web_module """
  defmodule StudioWeb do
    def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
    def router, do: quote(do: use(Phoenix.Router, helpers: false))
    defmacro __using__(which), do: apply(__MODULE__, which, [])
  end
  """

  test "phx.new's robots.txt gives way to the SEO controller's, once" do
    result = project("", %{@robots => @phx_robots, "lib/studio_web.ex" => @web_module}) |> generate(["--yes"])
    assert result.issues == []
    assert @robots in result.rms
    assert IgniterCase.source(result, "lib/studio_web/router.ex") =~ ~s("/robots.txt", BrandoWeb.SEOController, :robots)
    assert IgniterCase.source(result, "lib/studio_web.ex") =~ "def static_paths, do: ~w(assets fonts images favicon.ico)"

    rerun = result |> IgniterCase.apply_and_reload() |> generate()
    assert rerun.issues == []
    assert rerun.rms == []
    Igniter.Test.assert_unchanged(rerun)

    # Through the installer too, with static paths written as a list.
    listed = String.replace(@web_module, "~w(assets fonts images favicon.ico robots.txt)", ~s(["assets", "robots.txt"]))

    installed =
      fresh(%{@robots => @phx_robots, "lib/studio_web.ex" => listed})
      |> install()

    assert installed.issues == []
    assert @robots in installed.rms
    assert IgniterCase.source(installed, "lib/studio_web.ex") =~ ~s(def static_paths, do: ["assets"])
  end

  test "a changed robots.txt is kept with a notice" do
    result =
      project("", %{@robots => "User-agent: *\nDisallow: /private/\n", "lib/studio_web.ex" => @web_module})
      |> generate(["--yes"])

    assert result.rms == []
    Igniter.Test.assert_unchanged(result, [@robots])
    assert IgniterCase.source(result, "lib/studio_web.ex") =~ "robots.txt"

    assert Enum.any?(
             result.notices,
             &(&1 =~ "#{@robots} is not the file mix phx.new writes" and
                 &1 =~ "remove robots.txt from static_paths/0 in StudioWeb")
           )
  end

  test "a robots.txt the frontend build copied from assets/frontend/public is left alone" do
    result =
      project("", %{
        @robots => @phx_robots,
        "assets/frontend/public/robots.txt" => @phx_robots,
        "lib/studio_web.ex" => @web_module
      })
      |> generate(["--yes"])

    assert result.rms == []
    Igniter.Test.assert_unchanged(result, [@robots, "lib/studio_web.ex"])
    refute Enum.any?(result.notices, &(&1 =~ "is not the file mix phx.new writes"))
  end

  test "only static paths returned as a literal list lose robots.txt" do
    computed = """
    defmodule StudioWeb do
      @static_paths ~w(assets robots.txt)
      def static_paths, do: @static_paths -- ~w(robots.txt)
      def router, do: quote(do: use(Phoenix.Router, helpers: false))
      defmacro __using__(which), do: apply(__MODULE__, which, [])
    end
    """

    result = project("", %{@robots => @phx_robots, "lib/studio_web.ex" => computed}) |> generate(["--yes"])
    assert @robots in result.rms
    assert IgniterCase.source(result, "lib/studio_web.ex") =~ "@static_paths -- ~w(robots.txt)"
  end
end
