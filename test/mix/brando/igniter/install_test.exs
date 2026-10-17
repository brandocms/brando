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

    # The endpoint stops first, draining its sockets while presence still runs
    [before_endpoint, _] = String.split(application, "StudioWeb.Endpoint", parts: 2)
    assert before_endpoint =~ "Studio.Presence"
    assert before_endpoint =~ ~r/^\s*Brando,?$/m
    assert application =~ "Brando.System.initialize()"
    assert application =~ "case Supervisor.start_link"
    assert application =~ "error ->"

    Igniter.Test.assert_creates(igniter, "lib/studio_admin/gettext.ex")
    Igniter.Test.assert_creates(igniter, "priv/repo/migrations/20260101000250_brando_170_add_authorization_groups.exs")
    assert IgniterCase.source(igniter, "assets/backend/package.json") =~ "file:.yalc/@brandocms/brandojs"
    assert [{"deps.get", []} | _] = igniter.tasks

    assert Enum.all?(igniter.tasks, fn {task, _} ->
             task in ["brando.assets.copy", "brando.install.secrets", "deps.get"]
           end)
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
    for migration <- ["20200101000000_create_users.exs", "20200101000000_create_users_auth_tables.exs"],
        table <- [:users, :users_tokens],
        operation <- [:create, :create_if_not_exists] do
      result =
        project(%{
          "priv/repo/migrations/#{migration}" => """
          defmodule Studio.Repo.Migrations.ExistingUsers do
            use Ecto.Migration
            def change do
              #{operation} table(#{inspect(table)}) do
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
    igniter = project() |> install(["--interactive", "--tenancy-mode", "single", "--domain", "studio.example"])
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

  @phx_new_dev """
  import Config

  config :studio, StudioWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 4000],
    check_origin: false,
    code_reloader: true,
    secret_key_base: "dev-secret",
    watchers: []

  config :studio, StudioWeb.Endpoint, live_reload: [patterns: [~r"lib/studio_web/.*(ex|heex)$"]]
  """

  # The watchers as Phoenix reads them, with config/dev.exs under `root`
  defp dev_watchers(igniter, root) do
    root
    |> Path.join("config/dev.exs")
    |> Config.Reader.eval!(IgniterCase.source(igniter, "config/dev.exs"), env: :dev)
    |> get_in([:studio, StudioWeb.Endpoint, :watchers])
  end

  defp vite_watcher(root, dir) do
    shim = "data:text/javascript,process.stdin.on('end',()=>process.kill(process.pid,'SIGTERM')).resume()"
    ["--import", shim, "node_modules/vite/bin/vite.js", cd: Path.join(root, "assets/#{dir}")]
  end

  defp vite_notice?(igniter), do: Enum.any?(igniter.notices, &(&1 =~ "already has watchers"))

  test "phx.new's empty watchers start both Vite dev servers, once" do
    igniter = project(%{"config/dev.exs" => @phx_new_dev}) |> install()
    assert igniter.issues == []
    refute vite_notice?(igniter)

    assert dev_watchers(igniter, "/srv/studio") == [
             node: vite_watcher("/srv/studio", "backend"),
             node: vite_watcher("/srv/studio", "frontend")
           ]

    dev = IgniterCase.source(igniter, "config/dev.exs")
    assert dev =~ ~s(secret_key_base: "dev-secret")
    assert dev =~ "hmr: true"
    assert dev =~ "# Vite dev servers for the admin"
    assert length(String.split(dev, "node_modules/vite/bin/vite.js")) == 3

    applied = Igniter.Test.apply_igniter!(igniter)
    reloaded = Enum.reduce(Map.keys(applied.assigns.test_files), applied, &Igniter.include_existing_file(&2, &1))
    rerun = install(reloaded)
    assert rerun.issues == []
    refute vite_notice?(rerun)
    Igniter.Test.assert_unchanged(rerun, "config/dev.exs")
  end

  test "an endpoint without watchers gets the Vite watchers" do
    igniter = install(project())
    assert igniter.issues == []

    assert dev_watchers(igniter, "/srv/studio") == [
             node: vite_watcher("/srv/studio", "backend"),
             node: vite_watcher("/srv/studio", "frontend")
           ]
  end

  test "the application's own watchers are kept, with a notice naming the Vite watchers" do
    dev =
      String.replace(
        @phx_new_dev,
        "watchers: []",
        ~s|watchers: [esbuild: {Esbuild, :install_and_run, [:studio, ~w(--watch)]}]|
      )

    igniter = project(%{"config/dev.exs" => dev}) |> install()
    assert igniter.issues == []
    refute IgniterCase.source(igniter, "config/dev.exs") =~ "vite"
    assert [notice] = Enum.filter(igniter.notices, &(&1 =~ "already has watchers"))
    assert notice =~ ~s|cd: Path.expand("../assets/backend", __DIR__)|
    assert notice =~ ~s|cd: Path.expand("../assets/frontend", __DIR__)|
    assert notice =~ "node_modules/vite/bin/vite.js"
  end

  defp mix_exs(project, attributes \\ "") do
    """
    defmodule Studio.MixProject do
      use Mix.Project
      #{attributes}
      def project, do: [app: :studio, #{project}, deps: deps()]
      def application, do: [mod: {Studio.Application, []}]
      defp deps, do: [{:brando, path: "../framework"}]
    end
    """
  end

  @reads_version ~s[@version "VERSION" |> File.read!() |> String.trim()]

  test "phx.new's inline version moves to a VERSION file that mix.exs reads" do
    igniter = install(project())
    assert igniter.issues == []
    assert IgniterCase.source(igniter, "VERSION") == "0.1.0\n"

    mix = IgniterCase.source(igniter, "mix.exs")
    assert mix =~ @reads_version
    assert mix =~ "version: @version"
    refute mix =~ ~s(version: "0.1.0")
  end

  test "a literal @version moves to VERSION and keeps its attribute" do
    igniter = install(project(%{"mix.exs" => mix_exs("version: @version", ~s(@version "2.3.4"))}))
    assert igniter.issues == []
    assert IgniterCase.source(igniter, "VERSION") == "2.3.4\n"
    assert IgniterCase.source(igniter, "mix.exs") =~ @reads_version
    refute IgniterCase.source(igniter, "mix.exs") =~ ~s(@version "2.3.4")
  end

  test "an existing VERSION is kept: mix.exs reads it when they agree, a notice reports a disagreement" do
    agreeing = install(project(%{"VERSION" => "0.1.0\n"}))
    assert agreeing.issues == []
    Igniter.Test.assert_unchanged(agreeing, "VERSION")
    assert IgniterCase.source(agreeing, "mix.exs") =~ @reads_version

    disagreeing = install(project(%{"VERSION" => "1.0.0\n"}))
    assert disagreeing.issues == []
    Igniter.Test.assert_unchanged(disagreeing, "VERSION")
    refute IgniterCase.source(disagreeing, "mix.exs") =~ @reads_version
    assert Enum.any?(disagreeing.notices, &(&1 =~ "VERSION says 1.0.0 and mix.exs says 0.1.0"))
  end

  test "a mix.exs that reads VERSION, or computes its version otherwise, keeps its version" do
    reads = mix_exs("version: @version", @reads_version)
    result = install(project(%{"mix.exs" => reads, "VERSION" => "0.4.0\n"}))
    assert result.issues == []
    Igniter.Test.assert_unchanged(result, "VERSION")
    refute Enum.any?(result.notices, &(&1 =~ "VERSION"))
    assert length(String.split(IgniterCase.source(result, "mix.exs"), "@version \"VERSION\"")) == 2

    computed = install(project(%{"mix.exs" => mix_exs(~s|version: System.get_env("APP_VERSION", "0.1.0")|)}))
    assert computed.issues == []
    refute Igniter.exists?(computed, "VERSION")
    assert IgniterCase.source(computed, "mix.exs") =~ ~s|System.get_env("APP_VERSION", "0.1.0")|
    assert Enum.any?(computed.notices, &(&1 =~ "computes its version"))
  end

  # The stages of phx.gen.release --docker's Dockerfile (Phoenix 1.8) that copy files.
  @phx_dockerfile """
  ARG BUILDER_IMAGE="hexpm/elixir:1.18.4-erlang-28.0.2-debian-bookworm-20250811-slim"
  ARG RUNNER_IMAGE="debian:bookworm-20250811-slim"

  FROM ${BUILDER_IMAGE} AS builder

  WORKDIR /app

  RUN mix local.hex --force && mix local.rebar --force

  ENV MIX_ENV="prod"

  # install mix dependencies
  COPY mix.exs mix.lock ./
  RUN mix deps.get --only $MIX_ENV
  RUN mkdir config

  COPY config/config.exs config/${MIX_ENV}.exs config/
  RUN mix deps.compile

  COPY priv priv
  COPY lib lib
  COPY assets assets
  RUN mix assets.deploy
  RUN mix compile
  COPY config/runtime.exs config/
  COPY rel rel
  RUN mix release

  FROM ${RUNNER_IMAGE} AS final
  WORKDIR "/app"
  COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/studio ./
  CMD ["/app/bin/server"]
  """

  test "the Dockerfile copies VERSION after mix.exs, in each stage that copies mix.exs, once" do
    dockerfile = @phx_dockerfile <> "\nFROM builder AS other\nCOPY --chown=nobody mix.exs /srv/\nRUN mix deps.get\n"
    igniter = install(project(%{"Dockerfile" => dockerfile}))
    assert igniter.issues == []

    updated = IgniterCase.source(igniter, "Dockerfile")
    assert updated =~ "COPY mix.exs mix.lock ./\nCOPY VERSION ./\nRUN mix deps.get --only $MIX_ENV\n"
    assert updated =~ "COPY --chown=nobody mix.exs /srv/\nCOPY --chown=nobody VERSION /srv/\nRUN mix deps.get\n"
    assert updated |> String.split("COPY VERSION") |> length() == 2
    assert String.replace(updated, ~r/^COPY (--chown=nobody )?VERSION .*\n/m, "") == dockerfile
    refute Enum.any?(igniter.notices, &(&1 =~ "COPY VERSION"))

    for kept <- [updated, String.replace(@phx_dockerfile, "COPY mix.exs mix.lock ./", "COPY . .")] do
      rerun = install(project(%{"Dockerfile" => kept}))
      assert rerun.issues == []
      Igniter.Test.assert_unchanged(rerun, "Dockerfile")
    end
  end

  test "a context or VERSION copy after the first RUN does not count, and a file destination gets its directory" do
    late = "FROM elixir\nCOPY mix.exs mix.lock ./\nRUN mix deps.get\nCOPY . .\nRUN mix release\n"
    updated = late |> then(&install(project(%{"Dockerfile" => &1}))) |> IgniterCase.source("Dockerfile")
    assert updated =~ "COPY mix.exs mix.lock ./\nCOPY VERSION ./\nRUN mix deps.get\n"

    file_dest = "FROM elixir\nCOPY mix.exs /app/mix.exs\nRUN mix deps.get\n"
    updated = file_dest |> then(&install(project(%{"Dockerfile" => &1}))) |> IgniterCase.source("Dockerfile")
    assert updated =~ "COPY mix.exs /app/mix.exs\nCOPY VERSION /app/\nRUN mix deps.get\n"

    renamed = install(project(%{"Dockerfile" => "FROM elixir\nCOPY project.exs /app/mix.exs\nRUN mix deps.get\n"}))
    Igniter.Test.assert_unchanged(renamed, "Dockerfile")
  end

  test "a .dockerignore decides by its last pattern matching VERSION" do
    for {ignore, notice?} <- [{"**/VERSION\n", true}, {"!VERSION\n*\n", true}, {"*\n!VERSION\n", false}] do
      igniter = install(project(%{"Dockerfile" => @phx_dockerfile, ".dockerignore" => ignore}))
      assert Enum.any?(igniter.notices, &(&1 =~ ".dockerignore may exclude VERSION")) == notice?, inspect(ignore)
    end
  end

  test "a Dockerfile that does not copy mix.exs recognizably, or a .dockerignore excluding VERSION, gets a notice" do
    for dockerfile <- [
          ~s(FROM elixir\nCOPY ["mix.exs", "mix.lock", "./"]\n),
          ~s(FROM elixir AS one\nCOPY . .\nFROM elixir AS two\nCOPY ["mix.exs", "./"]\n),
          "FROM my-custom-image\n"
        ] do
      igniter = install(project(%{"Dockerfile" => dockerfile}))
      assert igniter.issues == []
      Igniter.Test.assert_unchanged(igniter, "Dockerfile")
      assert Enum.any?(igniter.notices, &(&1 =~ "does not copy mix.exs" and &1 =~ "COPY VERSION ./"))
    end

    ignored = install(project(%{"Dockerfile" => @phx_dockerfile, ".dockerignore" => "*\n!mix.exs\n"}))
    assert Enum.any?(ignored.notices, &(&1 =~ ".dockerignore may exclude VERSION"))

    kept = install(project(%{"Dockerfile" => @phx_dockerfile, ".dockerignore" => "*\n!mix.exs\n!VERSION\n"}))
    refute Enum.any?(kept.notices, &(&1 =~ ".dockerignore may exclude VERSION"))
  end

  test "the formatter imports Brando's, which keeps Blueprint DSL calls without parentheses" do
    for {formatter, expected} <- [
          {~s([import_deps: [:ecto, :phoenix], inputs: ["*.{ex,exs}"]]), [:brando, :ecto, :phoenix]},
          {~s([inputs: ["*.{ex,exs}"]]), [:brando]}
        ] do
      igniter = install(project(%{".formatter.exs" => formatter}))
      assert igniter.issues == []
      {options, _} = Code.eval_string(IgniterCase.source(igniter, ".formatter.exs"))
      assert options[:import_deps] == expected
      assert options[:inputs] == ["*.{ex,exs}"]
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
