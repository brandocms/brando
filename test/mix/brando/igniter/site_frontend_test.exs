defmodule Mix.Brando.Igniter.SiteFrontendTest do
  # mix brando.gen.site --site: one site's frontend. Not async: Igniter's
  # test projects share Mix's state.
  use ExUnit.Case, async: false
  alias Brando.IgniterCase

  @phx_home File.read!(Path.expand("../../../fixtures/phx_new/home.html.heex", __DIR__))
  @controller "lib/studio_web/cms/page_controller.ex"
  @frontend "lib/studio_web/sites/acme_travel.ex"
  @layouts "lib/studio_web/sites/acme_travel/layouts.ex"
  @page_html "lib/studio_web/sites/acme_travel/page_html.ex"

  defp fresh do
    IgniterCase.phoenix_project(
      files: %{
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
        "lib/studio_web/controllers/page_controller.ex" => """
        defmodule StudioWeb.PageController do
          use StudioWeb, :controller

          def home(conn, _params) do
            render(conn, :home)
          end
        end
        """,
        "lib/studio_web/controllers/page_html/home.html.heex" => @phx_home
      }
    )
  end

  defp install(options), do: fresh() |> Igniter.compose_task(Mix.Tasks.Brando.Install, ["--yes" | options])
  defp installed(options), do: options |> install() |> tap(&([] = &1.issues)) |> IgniterCase.apply_and_reload()
  defp generate(igniter, options), do: Igniter.compose_task(igniter, Mix.Tasks.Brando.Gen.Site, options)

  defp config(igniter, file \\ "config/brando.exs"), do: IgniterCase.source(igniter, file)

  defp notice?(igniter, text), do: Enum.any?(igniter.notices, &(&1 =~ text))

  setup_all do
    %{
      multi: installed(["--tenancy-mode", "multi"]),
      single: installed(["--tenancy-mode", "single", "--site-key", "studio"]),
      none: installed([])
    }
  end

  test "a fresh site's page controller renders the site's frontend", %{none: none} do
    controller = IgniterCase.source(none, @controller)
    [plugs, _] = String.split(controller, "alias Brando.I18n", parts: 2)

    assert plugs
           |> String.trim()
           |> String.ends_with?(["plug Brando.Plug.SiteFrontend", "plug(Brando.Plug.SiteFrontend)"])

    assert length(Regex.scan(~r/\|> Brando\.Site\.Frontend\.put_page_assigns\(page\)\n\s+\|> render/, controller)) == 2
  end

  test "--site writes the frontend, its layouts and templates, and registers it", %{multi: multi} do
    result = generate(multi, ["--site", "acme-travel"])
    assert result.issues == []

    frontend = IgniterCase.source(result, @frontend)
    assert frontend =~ "defmodule StudioWeb.Sites.AcmeTravel do"
    assert frontend =~ "root_layout: {StudioWeb.Sites.AcmeTravel.Layouts, :root}"
    assert frontend =~ "page_html: StudioWeb.Sites.AcmeTravel.PageHTML"
    assert frontend =~ "#     def layout_assigns(language)"
    assert frontend =~ "#     def page_assigns(page, _assigns)"

    layouts = IgniterCase.source(result, @layouts)
    assert layouts =~ "defmodule StudioWeb.Sites.AcmeTravel.Layouts do"
    # The default site's layout, under the site's name.
    assert String.replace(layouts, "Sites.AcmeTravel.Layouts", "CMS.Layouts") ==
             IgniterCase.source(multi, "lib/studio_web/cms/layouts.ex")

    page_html = IgniterCase.source(result, @page_html)
    assert page_html =~ "defmodule StudioWeb.Sites.AcmeTravel.PageHTML do"
    assert page_html =~ "def index(assigns)"
    assert page_html =~ "def default(assigns)"

    assert config(result) =~ ~s(site_frontends: %{"acme-travel" => StudioWeb.Sites.AcmeTravel})
    refute config(result) =~ "default_site_frontend"
    refute config(result, "config/config.exs") =~ "site_frontends"
    Igniter.Test.assert_unchanged(result, @controller)

    assert notice?(result, "No site record, content or frontend assets were created")
    assert notice?(result, "takes effect\nwith the next release")
    assert notice?(result, "every other site now\nanswers 404")

    rerun = result |> IgniterCase.apply_and_reload() |> generate(["--site", "acme-travel"])
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
    refute notice?(rerun, "answers 404")

    second = result |> IgniterCase.apply_and_reload() |> generate(["--site", "globex"])
    assert second.issues == []

    assert config(second) =~
             ~r/site_frontends: %\{\s*"acme-travel" => StudioWeb.Sites.AcmeTravel,\s*"globex" => StudioWeb.Sites.Globex\s*\}/

    refute notice?(second, "answers 404")
  end

  test "--module names the site's module", %{multi: multi} do
    result = generate(multi, ["--site", "2025", "--module", "Anniversary"])
    assert result.issues == []
    assert IgniterCase.source(result, "lib/studio_web/sites/anniversary.ex") =~ "defmodule StudioWeb.Sites.Anniversary do"
    assert config(result) =~ ~s(%{"2025" => StudioWeb.Sites.Anniversary})
  end

  test "in :single, the registry has the entry and no 404 notice", %{single: single} do
    result = generate(single, ["--site", "studio"])
    assert result.issues == []
    assert config(result) =~ ~s(site_frontends: %{"studio" => StudioWeb.Sites.Studio})
    refute notice?(result, "answers 404")
  end

  test "the entry goes to config.exs when the application configures tenancy there", %{multi: multi} do
    brando = config(multi)
    assert brando =~ "tenancy_mode: :multi"

    moved =
      multi
      |> Igniter.update_file(
        "config/brando.exs",
        &Rewrite.Source.update(&1, :content, fn _ -> String.replace(brando, ~r/\s*tenancy_mode: :multi,/, "") end)
      )
      |> Igniter.update_file(
        "config/config.exs",
        &Rewrite.Source.update(&1, :content, fn config -> config <> "\nconfig :brando, tenancy_mode: :multi\n" end)
      )
      |> IgniterCase.apply_and_reload()

    result = generate(moved, ["--site", "acme-travel"])
    assert result.issues == []
    assert config(result, "config/config.exs") =~ ~s(site_frontends: %{"acme-travel" => StudioWeb.Sites.AcmeTravel})
    refute config(result) =~ "site_frontends"
  end

  test "an existing entry for the key is kept, with a notice", %{multi: multi} do
    own =
      multi
      |> Igniter.update_file(
        "config/brando.exs",
        &Rewrite.Source.update(&1, :content, fn config ->
          config <> ~s(\nconfig :brando, site_frontends: %{"acme-travel" => StudioWeb.Sites.Acme}\n)
        end)
      )
      |> IgniterCase.apply_and_reload()

    result = generate(own, ["--site", "acme-travel"])
    assert result.issues == []
    Igniter.Test.assert_unchanged(result, "config/brando.exs")
    assert notice?(result, ~s(already registers StudioWeb.Sites.Acme for "acme-travel"))
  end

  test "refuses, saying what to do", %{multi: multi, none: none} do
    no_site = installed(["--tenancy-mode", "multi", "--no-public-site"])

    for {project, options, message} <- [
          {none, ["--site", "acme"], "tenancy is off (tenancy_mode :none)"},
          {no_site, ["--site", "acme"], "Run mix brando.gen.site without --site first"},
          {multi, ["--site", "Acme"], ~s(--site "Acme" is not a site key)},
          {multi, ["--site", "acme_travel"], ~s(--site "acme_travel" is not a site key)},
          {multi, ["--site", "2025"], "Name the module with --module"},
          {multi, ["--site", "acme", "--module", "acme"], ~s(--module "acme" is not a module name)}
        ] do
      result = generate(project, options)
      assert [issue] = result.issues, inspect(options)
      assert issue =~ message
      Igniter.Test.assert_unchanged(result)
    end
  end

  @customized_steps [
    "is customized, so it was left as it is",
    "Add `plug Brando.Plug.SiteFrontend` to StudioWeb.CMS.PageController as its last plug",
    "call `Brando.Site.Frontend.put_page_assigns(conn, page)`",
    "`plug Brando.Plug.SiteFrontend, view: false`"
  ]

  defp with_controller(igniter, fun) do
    igniter
    |> Igniter.update_file(@controller, &Rewrite.Source.update(&1, :content, fun))
    |> IgniterCase.apply_and_reload()
  end

  defp previous(controller) do
    controller
    |> String.replace(~r/^\s*plug\(?Brando\.Plug\.SiteFrontend\)?\n/m, "\n")
    |> String.replace(~r/^\s*\|> Brando\.Site\.Frontend\.put_page_assigns\(page\)\n/m, "\n")
  end

  test "a changed page controller is left alone, and the notice names the steps", %{multi: multi} do
    changed =
      with_controller(multi, &(&1 |> previous() |> String.replace("put_section(\"index\")", "put_section(\"home\")")))

    result = generate(changed, ["--site", "acme-travel"])
    assert result.issues == []
    Igniter.Test.assert_unchanged(result, @controller)
    for step <- @customized_steps, do: assert(notice?(result, step), step)

    # One the application has given the plug and the page assigns needs nothing.
    own = with_controller(multi, &String.replace(&1, "put_section(\"index\")", "put_section(\"home\")"))
    result = generate(own, ["--site", "acme-travel"])
    Igniter.Test.assert_unchanged(result, @controller)
    refute notice?(result, "is customized")
  end

  test "a page controller generated before the site's frontend gets the plug and the page assigns", %{multi: multi} do
    current = IgniterCase.source(multi, @controller)
    earlier = with_controller(multi, &previous/1)
    refute IgniterCase.source(earlier, @controller) =~ "SiteFrontend"

    for options <- [["--site", "acme-travel"], []] do
      result = generate(earlier, options)
      assert result.issues == []
      assert code(IgniterCase.source(result, @controller)) == code(current)
    end
  end

  defp code(source), do: source |> Sourceror.parse_string!() |> Sourceror.strip_meta()

  test "a multi install and mix brando.setup.tenancy --mode multi end with the command" do
    assert install(["--tenancy-mode", "multi"]).notices
           |> Enum.any?(&String.ends_with?(&1, "mix brando.gen.site --site KEY\n"))

    refute install([]).notices |> Enum.any?(&(&1 =~ "--site KEY"))

    setup = IgniterCase.phoenix_project() |> Igniter.compose_task(Mix.Tasks.Brando.Setup.Tenancy, ["--mode", "multi"])
    assert Enum.any?(setup.notices, &String.ends_with?(&1, "mix brando.gen.site --site KEY\n"))
  end
end
