defmodule Mix.Brando.Igniter.InstallTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Tasks.Brando.Install

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => """
            import Config
            config :studio, StudioWeb.Endpoint, secret_key_base: "existing-secret", live_view: [signing_salt: "existing-lv-salt"]
            import_config "dev.exs"
            """,
            "config/dev.exs" => "import Config\n",
            "assets/css/app.css" => "/* Existing Phoenix assets */",
            "lib/studio_web/gettext.ex" => "defmodule StudioWeb.Gettext do\n use Gettext.Backend, otp_app: :studio\nend\n"
          },
          files
        )
    )
  end

  defp install(igniter, args \\ []), do: Igniter.compose_task(igniter, Install, args)

  test "plans core installation without replacing Phoenix files, secrets or dependencies" do
    igniter = project() |> install()
    assert igniter.issues == []
    assert igniter.warnings == []
    refute_received {:mix_shell, :prompt, _}

    for path <- ["assets/css/app.css", "test/existing_test.exs", "lib/studio_web/gettext.ex"] do
      Igniter.Test.assert_unchanged(igniter, path)
    end

    assert IgniterCase.source(igniter, "mix.exs") =~ ~s({:brando, path: "../framework"})
    assert IgniterCase.source(igniter, "config/config.exs") =~ "existing-secret"
    assert IgniterCase.source(igniter, "config/config.exs") =~ "existing-lv-salt"
    assert IgniterCase.source(igniter, "config/brando.exs") =~ "tenancy_mode: :none"
    assert IgniterCase.source(igniter, "lib/studio_web/endpoint.ex") =~ "preserve-this-salt"
    assert IgniterCase.source(igniter, "lib/studio_web.ex") =~ "helpers: true"

    router = IgniterCase.source(igniter, "lib/studio_web/router.ex")
    assert router =~ ~s("/health", HealthController, :show)
    assert router =~ "api_pipeline: :brando_api"
    assert router =~ "StudioAdmin.DashboardLive"

    application = IgniterCase.source(igniter, "lib/studio/application.ex")
    assert application =~ "Studio.Presence"
    assert application =~ "Brando.System.initialize()"
    assert application =~ "case Supervisor.start_link"
    assert application =~ "error ->"

    Igniter.Test.assert_creates(igniter, "lib/studio_admin/gettext.ex")
    Igniter.Test.assert_creates(igniter, "priv/repo/migrations/20260101000250_brando_170_add_authorization_groups.exs")
    assert IgniterCase.source(igniter, "assets/backend/package.json") =~ "file:.yalc/@brandocms/brandojs"
    assert Enum.all?(igniter.tasks, fn {task, _} -> task in ["brando.assets.copy", "deps.get"] end)
  end

  test "existing admin route ownership blocks before planning source changes" do
    for route <- [
          ~s(get "/admin", ExistingController, :index),
          ~s(scope "/admin" do\n get "/reports", ReportsController, :index\nend)
        ] do
      result =
        project(%{
          "lib/studio_web/router.ex" => """
          defmodule StudioWeb.Router do
            use StudioWeb, :router
            #{route}
          end
          """
        })
        |> install(["--yes"])

      assert Enum.any?(result.issues, &String.contains?(&1, "already owns /admin"))
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "existing Phoenix authentication tables require explicit integration" do
    for migration <- ["20200101000000_create_users.exs", "20200101000000_create_users_auth_tables.exs"] do
      result =
        project(%{
          "priv/repo/migrations/#{migration}" => """
          defmodule Studio.Repo.Migrations.ExistingUsers do
            use Ecto.Migration
            def change do
              create table(:users) do
                add :email, :string
              end
            end
          end
          """
        })
        |> install(["--yes"])

      assert Enum.any?(result.issues, &String.contains?(&1, "authentication schema"))
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "admin routes precede an existing public catch-all" do
    result =
      project(%{
        "lib/studio_web/router.ex" => """
        defmodule StudioWeb.Router do
          use StudioWeb, :router
          get "/*path", StudioWeb.ExistingController, :show
        end
        """
      })
      |> install()

    assert result.issues == []
    router = IgniterCase.source(result, "lib/studio_web/router.ex")
    assert [before_catchall, _] = Regex.split(~r/get\(?\s*"\/\*path"/, router)
    assert before_catchall =~ "admin_routes"
  end

  test "direct and composed installation produce equivalent source plans" do
    base = project()
    args = ["--tenancy-mode", "single", "--site-key", "studio", "--yes", "--dry-run"]
    direct = Igniter.Mix.Task.configure_and_run(base, Install, args)
    composed = install(base, args)
    assert direct.issues == []
    assert composed.issues == []

    assert Map.new(direct.rewrite.sources, fn {path, source} -> {path, Rewrite.Source.get(source, :content)} end) ==
             Map.new(composed.rewrite.sources, fn {path, source} -> {path, Rewrite.Source.get(source, :content)} end)
  end

  test "an applied install can be rerun with no changes or duplicate initialization" do
    igniter = project() |> install(["--tenancy-mode", "single", "--site-key", "studio"]) |> Igniter.Test.apply_igniter!()
    reloaded = Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
    rerun = install(reloaded)
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
    assert IgniterCase.source(rerun, "config/brando.exs") =~ "tenancy_mode: :single"
  end

  test "conflicting scaffold files block even automatic acceptance and keep the original" do
    original = "defmodule Studio.Presence do\n def custom, do: :preserved\nend\n"
    igniter = project(%{"lib/studio/presence.ex" => original}) |> install(["--yes"])
    assert Enum.any?(igniter.issues, &String.contains?(&1, "lib/studio/presence.ex already contains different content"))
    Igniter.Test.assert_unchanged(igniter, "lib/studio/presence.ex")
  end

  test "invalid options and unsupported application supervision are blocking issues" do
    assert project() |> install(["--tenancy-mode", "single"]) |> Map.fetch!(:issues) != []

    igniter =
      project(%{
        "lib/studio/application.ex" => """
        defmodule Studio.Application do
          use Application
          def start(_type, _args), do: CustomSupervisor.start_link()
        end
        """
      })
      |> install()

    assert Enum.any?(igniter.issues, &String.contains?(&1, "children = [...]"))
  end

  test "interactive choices are opt-in and supplied answers are not requested again" do
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "guided-studio"})
    igniter = project() |> install(["--interactive", "--tenancy-mode", "single"])
    assert igniter.issues == []
    assert_received {:mix_shell, :prompt, ["+ Site key [studio]"]}
    refute_received {:mix_shell, :prompt, _}
    assert IgniterCase.source(igniter, "config/brando.exs") =~ ~s(site_key: "guided-studio")
  end

  test "explicit tenancy changes update existing base config and remove a stale site key" do
    for config <- [
          ~s(config :brando, tenancy_mode: :single, site_key: "old-site"),
          ~s(config :brando, :tenancy_mode, :single\nconfig :brando, :site_key, "old-site")
        ] do
      result = project(%{"config/config.exs" => "import Config\n" <> config}) |> install(["--tenancy-mode", "none"])
      assert result.issues == []
      assert {:ok, _, %{mode: :none, site_key: nil}} = Mix.Brando.Igniter.Install.Configuration.existing_tenancy(result)
      refute IgniterCase.source(result, "config/config.exs") =~ "old-site"
      rerun = install(result)
      assert rerun.issues == []
    end
  end

  test "conflicting or dynamic tenancy configuration is rejected without choosing a value" do
    for config <- [
          ~s|config :brando, tenancy_mode: System.get_env("TENANCY")|,
          ~s(config :brando, tenancy_mode: :single\nconfig :brando, tenancy_mode: :multi)
        ] do
      result = project(%{"config/config.exs" => "import Config\n" <> config}) |> install()
      assert Enum.any?(result.issues, &String.contains?(&1, "unambiguously"))
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "historical migration timestamps and edits are preserved and new files follow them" do
    name = "brando_170_add_authorization_groups.exs"
    historical = "priv/repo/migrations/20300101000000_#{name}"

    original =
      "# Historical migration customization\ndefmodule Existing.HistoricalMigration do\n use Ecto.Migration\n def change, do: :ok\nend"

    result = project(%{historical => original}) |> install()
    assert result.issues == []
    Igniter.Test.assert_unchanged(result, historical)
    matching = result.rewrite.sources |> Map.keys() |> Enum.filter(&String.ends_with?(&1, name))
    assert matching == [historical]
    versions = result.rewrite.sources |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "priv/repo/migrations/"))
    assert Enum.all?(versions, &(Path.basename(&1) >= "20300101000000"))
  end
end
