defmodule Mix.Brando.Igniter.ProjectTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Project

  defmodule DiscoveryTask do
    use Igniter.Mix.Task

    def info(_argv, _source), do: %Igniter.Mix.Task.Info{schema: Project.options(), group: :brando}

    def igniter(igniter) do
      case Project.discover(igniter, igniter.args.options) do
        {:ok, igniter, project} -> Igniter.assign(igniter, :consumer, project)
        {:error, igniter} -> igniter
      end
    end
  end

  test "structured options work through both direct and composed Igniter entry points" do
    project = IgniterCase.phoenix_project()
    arguments = ["--repo", "Studio.Repo", "--admin-module", "Backoffice", "--yes", "--dry-run"]

    direct = Igniter.Mix.Task.configure_and_run(project, DiscoveryTask, arguments)
    composed = Igniter.compose_task(project, DiscoveryTask, arguments)

    assert direct.issues == []
    assert composed.issues == []
    assert direct.assigns.consumer == composed.assigns.consumer
    assert direct.assigns.consumer.admin_module == Backoffice
    assert_unchanged(direct)
    assert_unchanged(composed)
  end

  test "discovers the consumer from source without loading its modules or configuration" do
    igniter =
      IgniterCase.phoenix_project(
        app: :shop,
        module: "Acme.Shop",
        web: "Storefront",
        files: %{"config/config.exs" => "raise \"Configuration must not run during discovery\""}
      )

    assert {:ok, igniter, project} = Project.discover(igniter)

    assert project == %{
             otp_app: :shop,
             app_module: Acme.Shop,
             application_module: Acme.Shop.Application,
             web_module: Storefront,
             admin_module: Acme.ShopAdmin,
             repo: Acme.Shop.Repo,
             router: Storefront.Router,
             endpoint: Storefront.Endpoint
           }

    assert :code.is_loaded(Acme.Shop.Application) == false
    assert_unchanged(igniter)
    assert igniter.tasks == []
  end

  test "preserves custom dependency sources, assets, tests, and pending changes" do
    igniter = IgniterCase.phoenix_project()
    before = igniter.assigns.test_files
    igniter = Igniter.create_new_file(igniter, "lib/pending.ex", "defmodule Pending do\nend")

    assert {:ok, igniter, _project} = Project.discover(igniter)
    assert igniter.assigns.test_files == before
    assert_creates(igniter, "lib/pending.ex")
    assert_unchanged(igniter, ["mix.exs", "assets/backend/package.json", "test/existing_test.exs"])
  end

  test "requires explicit selection when there are multiple repos" do
    igniter =
      IgniterCase.phoenix_project(files: %{"lib/studio/analytics.ex" => repo("Studio.Analytics")})

    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "--repo Studio.Analytics or --repo Studio.Repo"))
    assert_unchanged(result)

    assert {:ok, result, %{repo: Studio.Analytics}} = Project.discover(igniter, repo: "Studio.Analytics")
    assert_unchanged(result)
  end

  test "selects a router and only endpoints that actually plug it" do
    igniter =
      IgniterCase.phoenix_project(
        files: %{
          "lib/api/router.ex" => "defmodule API.Router do\n use API, :router\nend",
          "lib/api/endpoint.ex" => """
          defmodule API.Endpoint do
            use Phoenix.Endpoint, otp_app: :studio
            plug API.Router
          end
          """
        }
      )

    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "--router API.Router or --router StudioWeb.Router"))

    assert {:ok, _result, %{router: API.Router, endpoint: API.Endpoint, web_module: API}} =
             Project.discover(igniter, router: "API.Router")

    assert {:error, result} = Project.discover(igniter, router: "API.Router", endpoint: "StudioWeb.Endpoint")
    assert_has_issue(result, &String.contains?(&1, "--endpoint StudioWeb.Endpoint is not an available endpoint"))
  end

  test "requires explicit selection when the chosen router has multiple endpoints" do
    igniter =
      IgniterCase.phoenix_project(
        files: %{
          "lib/studio_web/other_endpoint.ex" => """
          defmodule StudioWeb.OtherEndpoint do
            use Phoenix.Endpoint, otp_app: :studio
            plug StudioWeb.Router
          end
          """
        }
      )

    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "Multiple endpoint modules"))

    assert {:ok, _result, %{endpoint: StudioWeb.OtherEndpoint}} =
             Project.discover(igniter, endpoint: "StudioWeb.OtherEndpoint")
  end

  test "does not offer test-only repos as installer targets" do
    igniter = IgniterCase.phoenix_project(files: %{"test/support/repo.ex" => repo("TestOnly.Repo")})

    assert {:ok, _result, %{repo: Studio.Repo}} = Project.discover(igniter)
    assert {:error, result} = Project.discover(igniter, repo: "TestOnly.Repo")
    assert_has_issue(result, &String.contains?(&1, "not an available repo"))
  end

  test "accepts explicit namespace overrides and rejects invalid module names" do
    igniter = IgniterCase.phoenix_project()

    assert {:ok, _result, %{app_module: Domain, web_module: Web, admin_module: Backoffice}} =
             Project.discover(igniter, module: "Domain", web_module: "Web", admin_module: "Backoffice")

    for value <- ["../Other", "not_a_module", "Studio; File.rm_rf!(\".\")", ""] do
      assert {:error, result} = Project.discover(igniter, module: value)
      assert_has_issue(result, &String.contains?(&1, "--module must be an Elixir module name"))
      assert_unchanged(result)
    end
  end

  test "rejects umbrella roots before source edits" do
    igniter =
      test_project(
        files: %{
          "mix.exs" => """
          defmodule Studio.Umbrella.MixProject do
            use Mix.Project
            def project, do: [apps_path: "apps", version: "0.1.0"]
          end
          """
        }
      )

    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "not umbrella roots"))
    assert_unchanged(result)
  end

  test "reports missing repos and unsupported adapters" do
    without_repo = IgniterCase.phoenix_project(files: %{"lib/studio/repo.ex" => "# no repo"})
    assert {:error, result} = Project.discover(without_repo)
    assert_has_issue(result, &String.contains?(&1, "No repo could be found"))

    sqlite =
      IgniterCase.phoenix_project(
        files: %{
          "lib/studio/repo.ex" => String.replace(repo("Studio.Repo"), "Ecto.Adapters.Postgres", "Ecto.Adapters.SQLite3")
        }
      )

    assert {:error, result} = Project.discover(sqlite)
    assert_has_issue(result, &String.contains?(&1, "adapter: Ecto.Adapters.Postgres"))
    assert_unchanged(result)
  end

  test "does not evaluate dynamic application configuration" do
    igniter = IgniterCase.phoenix_project()
    mix = IgniterCase.source(igniter, "mix.exs")
    mix = String.replace(mix, "{Studio.Application, []}", "raise(\"do not evaluate me\")")
    igniter = IgniterCase.phoenix_project(files: %{"mix.exs" => mix})

    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "no code was evaluated"))
    assert_unchanged(result)
  end

  test "reports a missing router or an endpoint that does not plug the chosen router" do
    without_router = IgniterCase.phoenix_project(files: %{"lib/studio_web/router.ex" => "# no router"})
    assert {:error, result} = Project.discover(without_router)
    assert_has_issue(result, &String.contains?(&1, "No router could be found"))

    disconnected =
      IgniterCase.phoenix_project(
        files: %{
          "lib/studio_web/endpoint.ex" => """
          defmodule StudioWeb.Endpoint do
            use Phoenix.Endpoint, otp_app: :studio
            plug AnotherWeb.Router
          end
          """
        }
      )

    assert {:error, result} = Project.discover(disconnected)
    assert_has_issue(result, &String.contains?(&1, "selected router must be plugged into a Phoenix endpoint"))
    assert_unchanged(result)
  end

  test "turns an unreadable application identity into an issue without evaluating it" do
    original = IgniterCase.phoenix_project() |> IgniterCase.source("mix.exs")

    for value <- ["raise(\"do not evaluate me\")", "nil"] do
      mix = String.replace(original, "app: :studio", "app: #{value}")
      assert {:error, result} = Project.discover(IgniterCase.phoenix_project(files: %{"mix.exs" => mix}))
      assert Enum.any?(result.issues, &String.contains?(&1, "mix.exs"))
      assert_unchanged(result)
    end
  end

  test "requires the configured application callback to exist in source" do
    igniter = IgniterCase.phoenix_project(files: %{"lib/studio/application.ex" => "# application missing"})
    assert {:error, result} = Project.discover(igniter)
    assert_has_issue(result, &String.contains?(&1, "Studio.Application could not be found"))
    assert_unchanged(result)
  end

  defp repo(module) do
    """
    defmodule #{module} do
      use Ecto.Repo, otp_app: :studio, adapter: Ecto.Adapters.Postgres
    end
    """
  end
end
