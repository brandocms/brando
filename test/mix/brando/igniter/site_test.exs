defmodule Mix.Brando.Igniter.SiteTest do
  use ExUnit.Case, async: false
  alias Brando.IgniterCase

  defp project(extra_routes \\ ~s(get "/", PageController, :home)) do
    IgniterCase.phoenix_project(
      files: %{
        "lib/studio_web/router.ex" => """
        defmodule StudioWeb.Router do
          use StudioWeb, :router
          import Brando.Router
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
    )
  end

  defp generate(project, options \\ []), do: Igniter.compose_task(project, Mix.Tasks.Brando.Gen.Site, options)

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

  test "yes alone never claims an existing homepage and custom route ownership blocks" do
    for {route, options} <- [
          {~s(get "/", PageController, :home), ["--yes"]},
          {~s(get "/", LandingController, :index), ["--yes", "--replace-phoenix-home"]},
          {~s(get "/*path", SPAController, :show), ["--replace-phoenix-home"]},
          {~s(get "/robots.txt", RobotsController, :show), []},
          {~s(forward "/", ExistingPlug), []}
        ] do
      result = project(route) |> generate(options)
      assert result.issues != []
      Igniter.Test.assert_unchanged(result)
    end
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

  test "site generation composes with installation and custom owned files block replacement" do
    result = project() |> Igniter.compose_task(Mix.Tasks.Brando.Install, ["--public-site", "--replace-phoenix-home"])
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
end
