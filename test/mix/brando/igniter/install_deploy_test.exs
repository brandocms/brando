defmodule Mix.Brando.Igniter.InstallDeployTest do
  # What brando.install adds for a Florist deploy: the Docker build files,
  # ReleaseTasks and a release that writes the tarball, ignore rules, and
  # media and log paths that resolve at runtime.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Install.Templates
  alias Mix.Tasks.Brando.Install

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  @deploy_files ~w(Dockerfile .dockerignore .gitignore mix.exs config/prod.exs lib/studio/release_tasks.ex)

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => "import Config\nimport_config \"\#{config_env()}.exs\"\n",
            "config/dev.exs" => "import Config\n",
            "config/prod.exs" => "import Config\nconfig :logger, level: :info\n"
          },
          files
        )
    )
  end

  defp install(igniter, args \\ ["--yes"]), do: Igniter.compose_task(igniter, Install, args)

  defp notice?(igniter, text), do: Enum.any?(igniter.notices, &(&1 =~ text))

  test "a new application gets Brando's Docker build, release, ignore rules and release paths, once" do
    igniter = install(project())
    assert igniter.issues == []

    assert IgniterCase.source(igniter, "Dockerfile") == Templates.contents(:copy, "Dockerfile")
    dockerignore = IgniterCase.source(igniter, ".dockerignore")
    assert dockerignore == Templates.contents(:copy, "dockerignore")

    for line <- ~w(.envrc* _build deps assets/backend/node_modules assets/frontend/node_modules media sql) do
      assert dockerignore =~ ~r/^#{Regex.escape(line)}$/m, line
    end

    release_tasks = IgniterCase.source(igniter, "lib/studio/release_tasks.ex")
    assert release_tasks =~ "defmodule Studio.ReleaseTasks"
    assert release_tasks =~ "def migrate do"

    mix = IgniterCase.source(igniter, "mix.exs")
    assert mix =~ "releases: [studio: [include_executables_for: [:unix], steps: [:assemble, :tar]]]"

    gitignore = IgniterCase.source(igniter, ".gitignore")

    for line <-
          ~w(/assets/backend/node_modules/ /assets/frontend/node_modules/ /assets/backend/.yalc/ /media/ /log/
             /release-archives/ /sql/ /priv/static/assets/ /priv/static/admin_manifest.json /priv/static/manifest.json
             /.envrc.prod /.envrc.staging) do
      assert gitignore =~ ~r/^#{Regex.escape(line)}$/m, line
    end

    assert IgniterCase.source(igniter, "config/prod.exs") =~ ~s(config :brando, media_path: "./media", log_dir: "./log")
    # The base configuration keeps its absolute paths for development.
    assert IgniterCase.source(igniter, "config/brando.exs") =~ ~s|media_path: Path.expand("./media")|

    rerun = igniter |> IgniterCase.apply_and_reload() |> install()
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun, @deploy_files)
    refute notice?(rerun, "existing Dockerfile")
    refute notice?(rerun, ".dockerignore has exceptions")
  end

  @phx_dockerfile """
  ARG BUILDER_IMAGE="hexpm/elixir:1.18.4-erlang-28.0.2-debian-bookworm-20250811-slim"
  FROM ${BUILDER_IMAGE} AS builder
  WORKDIR /app
  COPY mix.exs mix.lock ./
  COPY VERSION ./
  RUN mix deps.get --only $MIX_ENV
  RUN mix release
  """

  test "an existing Dockerfile is kept, with a notice of what Brando's build needs that it lacks" do
    igniter = install(project(%{"Dockerfile" => @phx_dockerfile}))

    Igniter.Test.assert_unchanged(igniter, "Dockerfile")
    assert notice?(igniter, "The existing Dockerfile was kept")
    assert notice?(igniter, "/opt/app/_build/prod/studio-<version>.tar.gz")
    assert notice?(igniter, "an assets_backend stage")
    assert notice?(igniter, "an assets_frontend stage")
    assert notice?(igniter, "`mix brando.digest`")
    assert notice?(igniter, "the release built in /opt/app")

    brando = install(project(%{"Dockerfile" => Templates.contents(:copy, "Dockerfile")}))
    Igniter.Test.assert_unchanged(brando, "Dockerfile")
    refute notice?(brando, "The existing Dockerfile was kept")
  end

  test "an existing .dockerignore gets the exclusions it misses, unless it has exceptions" do
    igniter = install(project(%{".dockerignore" => "_build\ndeps\n.git\n"}))

    assert IgniterCase.source(igniter, ".dockerignore") ==
             "_build\ndeps\n.git\n\n# Kept out of the Docker build context by Brando\n" <>
               "assets/backend/node_modules\nassets/frontend/node_modules\nmedia\nrelease-archives\nsql\n.envrc*\n"

    # Patterns matching a parent directory, at any depth, or with wildcards cover the exclusions.
    covered = "/_build/\n./deps\n**/node_modules\nmedia/\nrelease-*\nsql\n.envrc*\n"
    igniter = install(project(%{".dockerignore" => covered}))
    Igniter.Test.assert_unchanged(igniter, ".dockerignore")

    # .envrc.* misses the .envrc direnv reads in development.
    igniter = install(project(%{".dockerignore" => String.replace(covered, ".envrc*", ".envrc.*")}))
    assert IgniterCase.source(igniter, ".dockerignore") =~ "by Brando\n.envrc*\n"

    # Exact names leave out the rest of the family, such as a .envrc.prod.bak with credentials.
    exact = String.replace(covered, ".envrc*", ".envrc\n.envrc.prod\n.envrc.staging")
    igniter = install(project(%{".dockerignore" => exact}))

    assert IgniterCase.source(igniter, ".dockerignore") ==
             exact <> "\n# Kept out of the Docker build context by Brando\n.envrc*\n"
  end

  test "exclusions are appended past exceptions that cannot re-include them" do
    # mix phx.gen.release --docker re-includes .git/HEAD and .git/refs.
    phoenix = File.read!(Application.app_dir(:phoenix, "priv/templates/phx.gen.release/dockerignore.eex"))
    assert phoenix =~ "\n!.git/HEAD\n"
    igniter = install(project(%{".dockerignore" => phoenix}))

    assert IgniterCase.source(igniter, ".dockerignore") ==
             String.trim_trailing(phoenix) <>
               "\n\n# Kept out of the Docker build context by Brando\n" <>
               "assets/backend/node_modules\nassets/frontend/node_modules\nmedia\nrelease-archives\nsql\n.envrc*\n"

    refute notice?(igniter, ".dockerignore has exceptions")

    # An exception after an exclusion re-includes the path, and lines that cannot touch it are appended.
    excepted = "_build\ndeps\n**/node_modules\nmedia\n!media/fonts\n"
    igniter = install(project(%{".dockerignore" => excepted}))

    assert IgniterCase.source(igniter, ".dockerignore") ==
             excepted <> "\n# Kept out of the Docker build context by Brando\nrelease-archives\nsql\n.envrc*\n"

    refute notice?(igniter, ".dockerignore has exceptions")

    # An appended line would override an exception re-including part of what it covers.
    examples = "_build\ndeps\n**/node_modules\nmedia\nrelease-archives\nsql\n!.envrc.example\n"
    igniter = install(project(%{".dockerignore" => examples}))
    Igniter.Test.assert_unchanged(igniter, ".dockerignore")
    assert notice?(igniter, ".dockerignore has exceptions")
    assert notice?(igniter, "  .envrc*")

    # A file that excludes everything and re-includes what the build copies: !assets re-includes
    # the node_modules inside it, which an appended line would exclude again.
    allowlist = "*\n!mix.exs\n!mix.lock\n!VERSION\n!config\n!lib\n!priv\n!rel\n!assets\n"
    igniter = install(project(%{".dockerignore" => allowlist}))
    Igniter.Test.assert_unchanged(igniter, ".dockerignore")
    assert notice?(igniter, ".dockerignore has exceptions")
    assert notice?(igniter, "  assets/backend/node_modules")
    refute notice?(igniter, "  _build")
  end

  test "an existing .gitignore gets only the Brando lines it does not cover" do
    phoenix = "/_build/\n/deps/\n*.ez\n"
    igniter = install(project(%{".gitignore" => phoenix}))
    gitignore = IgniterCase.source(igniter, ".gitignore")
    assert String.starts_with?(gitignore, phoenix)
    assert gitignore =~ "\n# Brando: asset dependencies and builds, uploads, logs, Florist's archives and dumps\n"

    # The rules Brando's old skeleton wrote: names at any depth and directory prefixes.
    skeleton = "node_modules\n/priv/static/\nmedia*\nsql\nassets/backend/.yalc\nassets/frontend/.yalc\n.envrc*\n"
    igniter = install(project(%{".gitignore" => skeleton}))
    added = String.replace_prefix(IgniterCase.source(igniter, ".gitignore"), skeleton, "")

    assert added ==
             "\n# Brando: asset dependencies and builds, uploads, logs, Florist's archives and dumps\n" <>
               "/assets/backend/yalc.lock\n/assets/frontend/yalc.lock\n/log/\n/release-archives/\n"

    # A name without a slash covers a directory too; a later negation re-includes.
    igniter = install(project(%{".gitignore" => skeleton <> "log\n!/media/\n"}))
    added = String.replace_prefix(IgniterCase.source(igniter, ".gitignore"), skeleton <> "log\n!/media/\n", "")
    assert added =~ "\n/media/\n"
    refute added =~ "/log/"
  end

  test "the release paths keep an application's own literal or runtime setting" do
    igniter =
      install(
        project(%{
          "config/config.exs" =>
            "import Config\nconfig :brando, media_path: \"/srv/media\"\nimport_config \"\#{config_env()}.exs\"\n",
          "config/runtime.exs" => "import Config\nconfig :brando, log_dir: System.get_env(\"LOG_DIR\", \"./log\")\n"
        })
      )

    prod = IgniterCase.source(igniter, "config/prod.exs")
    refute prod =~ "media_path"
    refute prod =~ "log_dir"

    kept = install(project(%{"config/prod.exs" => "import Config\nconfig :brando, media_path: \"/data/media\"\n"}))
    prod = IgniterCase.source(kept, "config/prod.exs")
    assert prod =~ ~s(media_path: "/data/media")
    assert prod =~ ~s(log_dir: "./log")
  end

  test "an existing ReleaseTasks and release definition are kept, with notices for what Florist needs" do
    igniter =
      project(%{"lib/studio/release_tasks.ex" => "defmodule Studio.ReleaseTasks do\n  def seed, do: :ok\nend\n"})
      |> Igniter.Project.MixProject.update(:project, [:releases], fn _ ->
        {:ok, {:code, [studio: [include_executables_for: [:unix]]]}}
      end)
      |> IgniterCase.apply_and_reload()
      |> install()

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, "lib/studio/release_tasks.ex")
    refute IgniterCase.source(igniter, "mix.exs") =~ ":tar"
    assert notice?(igniter, "Studio.ReleaseTasks has no migrate/0")
    assert notice?(igniter, ~s(bin/studio eval "Studio.ReleaseTasks.migrate"))
    assert notice?(igniter, "does not write a tarball")

    tarball =
      project()
      |> Igniter.Project.MixProject.update(:project, [:releases], fn _ ->
        {:ok, {:code, [studio: [steps: [:assemble, :tar]]]}}
      end)
      |> IgniterCase.apply_and_reload()
      |> install()

    refute notice?(tarball, "does not write a tarball")
  end

  test "releases without one named after the application get a notice instead of a second release" do
    igniter =
      project()
      |> Igniter.Project.MixProject.update(:project, [:releases], fn _ ->
        {:ok, {:code, [site: [include_executables_for: [:unix]]]}}
      end)
      |> IgniterCase.apply_and_reload()
      |> install()

    assert igniter.issues == []
    mix = IgniterCase.source(igniter, "mix.exs")
    assert mix =~ "releases: [site: [include_executables_for: [:unix]]]"
    refute mix =~ "studio: ["
    assert notice?(igniter, "mix.exs defines :site in releases: but no studio release")
    assert notice?(igniter, "steps: [:assemble, :tar]")
    assert notice?(igniter, "project_name")
    assert notice?(igniter, "default_release")
    refute notice?(igniter, "does not write a tarball")
  end
end
