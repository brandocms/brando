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
  @vite_config_path "assets/frontend/vite.config.js"
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

  @vite_config """
  export default defineConfig({
    css: { devSourcemap: true },
    build: {
      sourcemap: true, // we want to debug our code in production
    },
  })
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

    vite_config = source(igniter, @vite_config_path)
    assert vite_config =~ "sourcemap: 'hidden', // we want"
    assert vite_config =~ "devSourcemap: true"

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

  test "starts the endpoint last, so it drains its sockets before presence stops" do
    application = """
    defmodule LegacyApp.Application do
      use Application

      def start(_type, _args) do
        children = [
          LegacyApp.Repo,
          # Start the endpoint
          LegacyAppWeb.Endpoint,
          {Phoenix.PubSub, name: LegacyApp.PubSub},
          LegacyApp.Presence,
          Brando
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """

    igniter = migrate(@blueprint_054, %{"lib/legacy_app/application.ex" => application})
    upgraded = source(igniter, "lib/legacy_app/application.ex")

    assert [_, after_brando] = String.split(upgraded, ~r/^\s*Brando,?$/m, parts: 2)
    assert after_brando =~ "# Start the endpoint\n"
    assert after_brando =~ "LegacyAppWeb.Endpoint"
    assert upgraded =~ ~r/LegacyApp\.Repo,\s+\{Phoenix\.PubSub/
  end

  test "the Florist conversion reads the legacy .envrc, nginx and supervisord files" do
    igniter =
      migrate(@blueprint_054, %{
        @deployment_config_path => String.replace(@deployment_config, "https://example.com", "http://somesite.com"),
        ".envrc.prod" => ~s(export BRANDO_URL_HOST="www.legacy-app.no"\nexport BRANDO_URL_PORT="443"\n),
        "etc/supervisord/prod.conf" => ~s([program:legacy_app_prod]\nenvironment=PORT="8123"\n)
      })

    assert_creates(igniter, @florist_config_path, fn config ->
      assert config =~ ~s(set(:domain, "www.legacy-app.no"\))
      assert config =~ "set(:blue_port, 8123)"
    end)

    assert_has_warning(igniter, &String.contains?(&1, "from .envrc.prod (BRANDO_URL_HOST)"))
    assert_has_warning(igniter, &String.contains?(&1, "runs under supervisord"))
  end

  test "adds the health plug Florist checks to the endpoint, before the router" do
    endpoint_path = "lib/legacy_app_web/endpoint.ex"

    endpoint = """
    defmodule LegacyAppWeb.Endpoint do
      use Phoenix.Endpoint, otp_app: :legacy_app

      plug Plug.Session, @session_options
      plug LegacyAppWeb.Router
    end
    """

    igniter = migrate(@blueprint_054, %{endpoint_path => endpoint})
    # The test project's formatter has no Phoenix locals_without_parens.
    assert source(igniter, endpoint_path) =~
             ~r/plug\(?Plug.Session, @session_options\)?\n\s*plug\(?Brando.Plug.Health\)?\n\s*plug\(?LegacyAppWeb.Router/

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, endpoint_path)

    # An endpoint that already has the plug is not rewritten (or reformatted).
    has_plug =
      "defmodule LegacyAppWeb.Endpoint do\n  use Phoenix.Endpoint, otp_app: :legacy_app\n  plug Brando.Plug.Health\n  plug LegacyAppWeb.Router\nend\n"

    assert_unchanged(migrate(@blueprint_054, %{endpoint_path => has_plug}), endpoint_path)

    # Only when the task creates the Florist configuration.
    existing = migrate(@blueprint_054, %{endpoint_path => endpoint, @florist_config_path => "use Florist.DSL\n"})
    assert_unchanged(existing, endpoint_path)
  end

  test "points Brando at the application's mailer" do
    mailer = "defmodule LegacyApp.Mailer do\n  use Swoosh.Mailer, otp_app: :legacy_app\nend\n"
    igniter = migrate(@blueprint_054, %{"lib/legacy_app/mailer.ex" => mailer})

    assert source(igniter, @brando_config_path) =~ "mailer: LegacyApp.Mailer"
    assert_has_warning(igniter, &String.contains?(&1, "config :brando, Brando.Mailer, from:"))
  end

  test "leaves the mailer alone when the application has none, or has chosen one" do
    assert_unchanged(migrate(@blueprint_054), @brando_config_path)

    chosen = @brando_config <> "\nconfig :brando, mailer: LegacyApp.Notifications.Mailer\n"
    mailer = "defmodule LegacyApp.Mailer do\n  use Swoosh.Mailer, otp_app: :legacy_app\nend\n"
    igniter = migrate(@blueprint_054, %{"lib/legacy_app/mailer.ex" => mailer, @brando_config_path => chosen})
    assert_unchanged(igniter, @brando_config_path)
  end

  describe "image text reads" do
    @hero_blueprint String.replace(@blueprint_054, "attribute :title, :string", """
                    attribute :title, :string

                      assets do
                        asset :hero, :image
                      end
                    """)

    test "lists code that reads an image's texts as strings, using the Blueprints' own asset names" do
      view = """
      defmodule LegacyAppWeb.ProjectHTML do
        use LegacyAppWeb, :html

        def show(assigns) do
          ~H\"\"\"
          <img alt={@project.cover.alt} />
          <p>{@project.hero.title}</p>
          <p>{@project.title}</p>
          <p>{Brando.Images.text(@project.cover, :credits, "no")}</p>
          \"\"\"
        end
      end
      """

      igniter = migrate(@hero_blueprint, %{"lib/legacy_app_web/project_html.ex" => view})

      assert_has_warning(igniter, fn warning ->
        String.contains?(warning, "language → text") and
          String.contains?(warning, "lib/legacy_app_web/project_html.ex:6: <img alt={@project.cover.alt} />") and
          String.contains?(warning, "lib/legacy_app_web/project_html.ex:7: <p>{@project.hero.title}</p>") and
          not String.contains?(warning, ":8:") and not String.contains?(warning, ":9:")
      end)

      # Report only: the file is untouched.
      assert source(igniter, "lib/legacy_app_web/project_html.ex") == view
    end

    test "stays quiet when nothing reads them" do
      igniter = migrate(@blueprint_054)
      refute Enum.any?(igniter.warnings, &String.contains?(&1, "language → text"))
    end
  end

  describe "Villain parsers" do
    @parser_path "lib/legacy_app/villain/parser.ex"

    defp migrate_parser(files) do
      migrate(@blueprint_054, files)
    end

    # Compiles the rewritten parser and returns its diagnostics.
    defp compile_diagnostics(source) do
      {_result, diagnostics} =
        Code.with_diagnostics(fn ->
          modules = Code.compile_string(source, @parser_path)
          for {module, _} <- modules, do: :code.delete(module) and :code.purge(module)
        end)

      diagnostics
    end

    test "a 0.54 parser override gets back what the old __using__ gave it, and compiles cleanly" do
      # smartwatt's parser before the upgrade: a slideshow override rendering
      # ~H with Brando.HTML's <.picture>.
      original = File.read!("test/fixtures/villain_parser/parser_054.ex.txt")

      # As it was, it no longer compiles: ~H and <.picture> came from __using__.
      assert_raise CompileError, fn -> Code.with_diagnostics(fn -> Code.compile_string(original) end) end

      igniter = migrate_parser(%{@parser_path => original})
      upgraded = source(igniter, @parser_path)

      assert upgraded =~ ~r/use Brando.Villain.Parser\n\s*use Phoenix.Component\n\s*import Brando.HTML\n/
      refute upgraded =~ "import Phoenix.HTML"
      assert compile_diagnostics(upgraded) == []

      assert_has_warning(igniter, &String.contains?(&1, "LegacyApp.Villain.Parser.slideshow/2 overrides no block"))

      rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
      assert_unchanged(rerun, @parser_path)
    end

    test "imports and aliases are added only when the parser uses them" do
      plain_path = "lib/legacy_app/villain/plain_parser.ex"

      igniter =
        migrate_parser(%{
          @parser_path => """
          defmodule LegacyApp.Villain.Parser do
            use Brando.Villain.Parser

            def text(%{text: text}, _opts), do: text |> Utils.slugify() |> raw()

            def html(%{text: text}, _opts), do: truncate(text, 20)

            def header(data, opts) when is_map(data), do: Brando.Villain.Parser.header(data, opts)

            def helper(a, b), do: private(a, b)
            defp private(a, b), do: {a, b}
          end
          """,
          plain_path => """
          defmodule LegacyApp.Villain.PlainParser do
            use Brando.Villain.Parser
            use Phoenix.Component
            alias LegacyApp.Utils

            def text(data, _opts) do
              assigns = %{data: data}
              ~H"<p>{Utils.title(@data.text)}</p>"
            end
          end
          """
        })

      upgraded = source(igniter, @parser_path)
      assert upgraded =~ "import Brando.HTML"
      assert upgraded =~ "import Phoenix.HTML"
      assert upgraded =~ "alias Brando.Utils"
      refute upgraded =~ "use Phoenix.Component"
      refute upgraded =~ "alias Brando.Content"
      assert compile_diagnostics(upgraded) == []

      # Already has Phoenix.Component, renders no Brando.HTML component, and
      # its Utils is its own alias.
      assert_unchanged(igniter, plain_path)

      assert_has_warning(igniter, &String.contains?(&1, "LegacyApp.Villain.Parser.helper/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, ".header/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, ".private/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, "PlainParser"))
    end
  end

  test "completes Plural-Forms headers Gettext 1.0 cannot parse" do
    po = fn plural_forms ->
      """
      msgid ""
      msgstr ""
      "Language: no\\n"
      "Plural-Forms: #{plural_forms}\\n"

      msgid "Hello"
      msgstr "Hei"
      """
    end

    paths = %{
      rule_missing: "priv/gettext/backend/no/LC_MESSAGES/default.po",
      semicolon_missing: "priv/gettext/en/LC_MESSAGES/default.po",
      complete: "priv/gettext/sv/LC_MESSAGES/default.po",
      unknown: "priv/gettext/xx/LC_MESSAGES/default.po"
    }

    igniter =
      migrate(@blueprint_054, %{
        paths.rule_missing => po.("nplurals=2;"),
        paths.semicolon_missing => po.("nplurals=2; plural=(n != 1)"),
        paths.complete => po.("nplurals=2; plural=(n != 1);"),
        paths.unknown => po.("nplurals=2;")
      })

    assert source(igniter, paths.rule_missing) == po.("nplurals=2; plural=(n != 1);")
    assert source(igniter, paths.semicolon_missing) == po.("nplurals=2; plural=(n != 1);")
    assert_unchanged(igniter, [paths.complete, paths.unknown])
    assert_has_warning(igniter, &String.contains?(&1, paths.unknown))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, [paths.rule_missing, paths.semicolon_missing])
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
        @vite_config_path => @vite_config,
        @deployment_config_path => @deployment_config,
        @fabfile_path => @fabfile,
        @gettext_script_path => legacy_gettext_script(),
        @legacy_task_path => legacy_task("0.54")
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_path, contents} -> is_nil(contents) end)
      |> Map.new()

    [app_name: :legacy_app, files: files]
    |> test_project()
    |> include_test_files()
  end

  defp legacy_gettext_script do
    File.read!(Application.app_dir(:brando, "priv/templates/brando.migrate/legacy_sync_gettext/sync_gettext.0.54.sh"))
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
