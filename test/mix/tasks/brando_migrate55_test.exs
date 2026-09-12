defmodule Mix.Tasks.Brando.Migrate55Test do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54
  alias Mix.Tasks.Brando.Migrate55

  @blueprint_path "lib/legacy_app/projects/project.ex"
  @repo_path "lib/legacy_app/repo.ex"
  @brando_config_path "config/brando.exs"
  @config_path "config/config.exs"
  @package_json_path "assets/package.json"
  @deployment_config_path "deployment.cfg"
  @fabfile_path "fabfile.py"
  @florist_config_path "florist.config.exs"
  @gettext_script_path "scripts/sync_gettext.sh"
  @legacy_task_path "lib/mix/brando.upgrade.ex"
  @archive_path "priv/brando/legacy_tasks/brando.upgrade.ex.disabled"
  @legacy_templates "priv/templates/brando.migrate/legacy_upgrade_tasks"

  # A Blueprint as `mix brando.migrate54` on Brando 0.54 left it: 0.54 syntax
  # throughout, but a custom listing row that still relies on implicit imports.
  @blueprint_054 """
  defmodule LegacyApp.Projects.Project do
    use Brando.Blueprint,
      application: "LegacyApp",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    trait Brando.Trait.Blocks

    attribute :title, :string

    relations do
      relation :blocks, :has_many, module: :blocks
    end

    datasources do
      datasource :all do
        type :list
        list {__MODULE__, :list_all, [status: :published]}
      end
    end

    listings do
      listing do
        query %{order: "asc title"}
        filter label: "Title", key: "title"
        component &__MODULE__.listing_row/1
      end
    end

    forms do
      form do
        default_params %{status: :draft}

        fieldset do
          input :title, :text
        end
      end
    end

    def list_all(_module, _language, _vars), do: []

    def listing_row(assigns) do
      ~H\"""
      <.cover image={@entry.cover} />
      <.update_link entry={@entry}>{@entry.title}</.update_link>
      \"""
    end
  end
  """

  @blueprint_053 """
  defmodule LegacyApp.Projects.Project do
    use Brando.Blueprint,
      application: "LegacyApp",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    use Brando.Datasource

    trait Brando.Trait.Villain

    attribute :data, :villain

    datasources do
      list :all, {__MODULE__, :list_all, [status: :published]}
    end

    listings do
      listing do
        listing_query %{order: "asc title"}
        filters [[label: "Title", filter: "title"]]
        component &__MODULE__.listing_row/1
      end
    end

    forms do
      form default_params: %{status: :draft} do
        fieldset [size: :half] do
          input :title, :text
        end
      end
    end

    def list_all(_module, _language, _vars), do: []

    def listing_row(assigns) do
      ~H\"""
      <.update_link entry={@entry}>{@entry.title}</.update_link>
      \"""
    end
  end
  """

  @repo """
  defmodule LegacyApp.Repo do
    use Ecto.Repo,
      otp_app: :legacy_app,
      adapter: Ecto.Adapters.Postgres
  end
  """

  @brando_config """
  import Config

  config :brando,
    otp_app: :legacy_app,
    repo_module: LegacyApp.Repo
  """

  @config """
  import Config

  config :legacy_app, ecto_repos: [LegacyApp.Repo]
  """

  @package_json """
  {
    "dependencies": {
      "phoenix_live_view": "1.0.18",
      "unrelated": "1.0.0"
    }
  }
  """

  @deployment_config """
  [DEPLOYMENT]
  PROJECT_MODULE = LegacyApp
  PROJECT_NAME = legacy_app
  PROD_URL = https://example.com
  DB_PASS = legacy-secret
  DOCKER_HOST =
  SSH_USER = deploy
  SSH_PASS = legacy-ssh-secret
  SSH_HOST = example.com
  SSH_PORT = 2222
  """

  @fabfile """
  GLUE_SETTINGS = {
      'project_name': PROJECT_NAME,
      'project_group': 'web',
      'prod': {
          'project_base': '/sites/prod',
          'process_name': '%s_prod' % PROJECT_NAME,
          'db_name': '%s_prod' % PROJECT_NAME,
          'db_user': PROJECT_NAME,
      }
  }

  def prod():
      env.flavor = 'prod'
      env.mix_env = 'prod'
      env.dockerfile = 'Dockerfile'
  """

  test "upgrades an application that 0.54 left behind without blocking issues" do
    igniter = migrate(@blueprint_054)
    blueprint = source(igniter, @blueprint_path)

    assert igniter.issues == []

    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Core"
    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]"
    refute blueprint =~ "Listings.Components.Children"
    assert blueprint =~ ~r/type[ (]:list/
    assert blueprint =~ ~r/trait[ (]Brando\.Trait\.Blocks/

    assert source(igniter, @config_path) =~ "config :swoosh, api_client: Swoosh.ApiClient.Req"
    live_view_version = to_string(Application.spec(:phoenix_live_view, :vsn))

    assert source(igniter, @package_json_path) =~
             ~s("phoenix_live_view": "#{live_view_version}")

    assert source(igniter, @package_json_path) =~ ~s("unrelated": "1.0.0")

    assert_creates(igniter, @florist_config_path, fn config ->
      assert config =~ "project_name(\"legacy_app\")"
      refute config =~ "legacy-secret"
    end)

    script = source(igniter, @gettext_script_path)
    assert script =~ "set -euo pipefail"
    refute script =~ "Processing file:"

    assert_rms(igniter, @legacy_task_path)
    assert_creates(igniter, @archive_path, fn archive -> assert archive == legacy_task("0.54") end)
  end

  test "is idempotent" do
    first_pass = migrate(@blueprint_054)

    second_pass =
      first_pass
      |> apply_igniter!()
      |> include_test_files()
      |> Migrate55.igniter()

    assert second_pass.issues == []
    assert_unchanged(second_pass)
    assert_has_notice(second_pass, &String.contains?(&1, "No consumer-owned brando.upgrade task"))
  end

  test "continues from migrate54 on 0.53 source without blocking issues" do
    igniter =
      @blueprint_053
      |> migrate_files(%{@legacy_task_path => nil, @gettext_script_path => nil})
      |> Migrate54.igniter()
      |> apply_igniter!()
      |> include_test_files()
      |> Migrate55.igniter()

    assert igniter.issues == []
    blueprint = source(igniter, @blueprint_path)
    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Core"
    assert blueprint =~ "trait(Brando.Trait.Blocks)"
    assert_unchanged(igniter, @gettext_script_path)
    assert_has_notice(igniter, &String.contains?(&1, "No consumer-owned brando.upgrade task"))
  end

  test "recognizes every upgrade task Brando ever installed" do
    igniter = migrate(@blueprint_054, %{@legacy_task_path => legacy_task("0.55-dev")})

    assert igniter.issues == []
    assert_rms(igniter, @legacy_task_path)
  end

  test "blocks instead of discarding a customized upgrade task" do
    customized = String.replace(legacy_task("0.54"), "def run(_) do", "def run(_) do\n    IO.puts(\"custom\")")
    igniter = migrate(@blueprint_054, %{@legacy_task_path => customized})

    assert Enum.any?(igniter.issues, &String.contains?(&1, "customized or unrecognized"))
    assert igniter.rms == []
  end

  test "preserves an existing Florist configuration" do
    existing_config = "use Florist.DSL\nproject_name \"already_configured\"\n"
    igniter = migrate(@blueprint_054, %{@florist_config_path => existing_config})

    assert source(igniter, @florist_config_path) == existing_config
    assert_unchanged(igniter, @florist_config_path)
  end

  test "warns without creating a Florist configuration from an incomplete legacy pair" do
    igniter = migrate(@blueprint_054, %{@fabfile_path => nil})

    refute Map.has_key?(igniter.rewrite.sources, @florist_config_path)
    assert_has_warning(igniter, &String.contains?(&1, "both legacy `deployment.cfg` and `fabfile.py` are required"))
  end

  test "preserves an explicitly configured Swoosh client" do
    existing_config = """
    import Config

    config :legacy_app, ecto_repos: [LegacyApp.Repo]
    config :swoosh, api_client: false
    """

    config = @blueprint_054 |> migrate(%{@config_path => existing_config}) |> source(@config_path)

    assert config =~ "config :swoosh, api_client: false"
    refute config =~ "Swoosh.ApiClient.Req"
  end

  test "reports only the 0.55 manual workflow" do
    igniter = migrate(@blueprint_054)

    assert_has_notice(igniter, &String.contains?(&1, "Continue in this order"))
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.gen.migrations"))
    assert_has_notice(igniter, &String.contains?(&1, "Created `florist.config.exs`"))
    assert_has_notice(igniter, &String.contains?(&1, "Archived the recognized legacy task"))
    assert_has_warning(igniter, &String.contains?(&1, "Manual 0.55 decisions remain"))
    assert_has_warning(igniter, &String.contains?(&1, "persist_identifier"))
    assert_has_warning(igniter, &String.contains?(&1, "*_identifiers"))
    assert_has_warning(igniter, &String.contains?(&1, "phoenix_live_view"))
    assert_has_warning(igniter, &String.contains?(&1, "Form.Primitives"))
    assert_has_warning(igniter, &String.contains?(&1, "key_available?/2"))
    assert_has_warning(igniter, &String.contains?(&1, "config_target"))
    assert_has_warning(igniter, &String.contains?(&1, "oban_job_state"))
    assert_has_warning(igniter, &String.contains?(&1, "Database passwords are intentionally not written"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Manual 0.54 decisions"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Brando.Type.Video"))
    refute Enum.any?(igniter.tasks, &match?({"igniter.update_gettext", _}, &1))
  end

  defp migrate(blueprint, overrides \\ %{}) do
    blueprint |> migrate_files(overrides) |> Migrate55.igniter()
  end

  defp migrate_files(blueprint, overrides) do
    files =
      %{
        @blueprint_path => blueprint,
        @repo_path => @repo,
        @brando_config_path => @brando_config,
        @config_path => @config,
        @package_json_path => @package_json,
        @deployment_config_path => @deployment_config,
        @fabfile_path => @fabfile,
        @gettext_script_path => File.read!("test/fixtures/brando_054/sync_gettext.sh"),
        @legacy_task_path => legacy_task("0.54")
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_path, contents} -> is_nil(contents) end)
      |> Map.new()

    [app_name: :legacy_app, files: files]
    |> test_project()
    |> include_test_files()
  end

  defp legacy_task(version) do
    File.read!(Application.app_dir(:brando, [@legacy_templates, "brando.upgrade.#{version}.ex"]))
  end

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, fn path, igniter ->
      Igniter.include_existing_file(igniter, path)
    end)
  end

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end
end
