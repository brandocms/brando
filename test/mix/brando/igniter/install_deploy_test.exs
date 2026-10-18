defmodule Mix.Brando.Igniter.InstallDeployTest do
  # What brando.install adds for a Florist deploy: the Docker build files,
  # ReleaseTasks and a release that writes the tarball, ignore rules, and
  # media and log paths that resolve at runtime.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Install.Toolchain
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
             /release-archives/ /sql/ /priv/static/ /.envrc.prod /.envrc.staging) do
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

  test "the generated .gitignore covers what the Vite builds copy from public/ into priv/static" do
    gitignore = install(project()) |> IgniterCase.source(".gitignore")
    dir = Path.join(System.tmp_dir!(), "brando-gitignore-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, ".gitignore"), gitignore)
    {_, 0} = System.cmd("git", ["init", "--quiet", dir])

    # Each file the templates put in a public/ folder, and the logo phx.new's
    # moves to.
    copies =
      for {format, _source, target} <- Templates.manifest(),
          [_, rest] <- [Regex.run(~r{^assets/(?:backend|frontend)/public/(.+)$}, target)],
          do: if(format == :keep, do: Path.join(rest, ".keep"), else: rest)

    built = Enum.map(copies ++ ~w(images/logo.svg), &Path.join("priv/static", &1))
    assert "priv/static/favicon.ico" in built
    assert "priv/static/ico/favicon.ico" in built

    for path <- built, do: assert({_, 0} = check_ignore(dir, [path]), path)

    # An image a site adds to assets/frontend/public/images, where the
    # install keeps a .keep, is tracked there, and its Vite copy is ignored.
    assert {_, 0} = check_ignore(dir, ["priv/static/images/photo.jpg"])

    # mix brando.digest's digested copies and gzip files.
    for path <-
          ~w(priv/static/manifest-6043d8adc435f606826fef84b0cf6952.json priv/static/admin_manifest.json.gz
             priv/static/favicon-51ad2559584f338e97b3fa532d009549.ico priv/static/robots.txt) do
      assert {_, 0} = check_ignore(dir, [path]), path
    end

    for path <-
          ~w(assets/frontend/public/favicon.ico assets/frontend/public/images/logo.svg assets/frontend/public/images/photo.jpg
             assets/frontend/public/robots.txt priv/repo/seeds.exs) do
      assert {_, 1} = check_ignore(dir, [path]), path
    end
  end

  defp check_ignore(dir, args), do: System.cmd("git", ["-C", dir, "check-ignore", "--no-index" | args])

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

  test "a directory line that would cancel an exception inside it is named in a notice instead" do
    # Git cannot re-include a file inside an ignored directory.
    kept = "/priv/static/*\n!/priv/static/.well-known/\n.gitkeep\n!.gitkeep\n"
    igniter = install(project(%{".gitignore" => kept}))
    added = String.replace_prefix(IgniterCase.source(igniter, ".gitignore"), kept, "")

    refute added =~ "/priv/static/"
    # An exception that matches a name at any depth leaves the other directories as they were.
    assert added =~ "\n/media/\n"
    assert notice?(igniter, ".gitignore has exceptions")
    assert notice?(igniter, "  /priv/static/")

    refute install(project()) |> notice?(".gitignore has exceptions")
  end

  # A version manager's data folder (asdf's or mise's) with a folder for each
  # `{tool, name}` install, and the folder itself.
  defp data_dir(installs) do
    dir = Path.join(System.tmp_dir!(), "brando-toolchain-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    for {tool, name} <- installs, do: File.mkdir_p!(Path.join([dir, "installs", tool, name]))
    dir
  end

  defp installed(dir, tool, name), do: Path.join([dir, "installs", tool, name])

  # The install runs the Erlang and Elixir a version manager installed under
  # the names the pin gives, and no folder above the application pins a
  # toolchain.
  defp toolchain(igniter, overrides \\ fn _data -> %{} end) do
    data = data_dir([{"erlang", "28.5.0.8"}, {"elixir", "1.20.4-otp-28"}])

    defaults = %{
      running: %{
        "erlang" => installed(data, "erlang", "28.5.0.8"),
        "elixir" => installed(data, "elixir", "1.20.4-otp-28")
      },
      data_dirs: [data],
      parents: []
    }

    Igniter.assign(igniter, :brando_toolchain, Map.merge(defaults, overrides.(data)))
  end

  defp no_pin_notice?(igniter, reason),
    do: Enum.any?(igniter.notices, &(&1 =~ "No .tool-versions was written: #{reason}" and &1 =~ "erlang 28.5.0.8"))

  test "a new application gets a .tool-versions when it runs the pinned Erlang and Elixir, once" do
    igniter = project() |> toolchain() |> install()
    assert igniter.issues == []
    assert IgniterCase.source(igniter, ".tool-versions") == Templates.contents(:copy, "tool-versions")
    assert notice?(igniter, "Run `mise install` (or `asdf install`) for the Node.js and pnpm it names.")

    rerun = igniter |> IgniterCase.apply_and_reload() |> install()
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun, ".tool-versions")
    refute notice?(rerun, ".tool-versions")
  end

  test "a new application that pins its own toolchain gets a suggestion, not a .tool-versions" do
    for path <-
          ~w(.tool-versions .mise.toml mise.toml mise.local.toml .mise/config.toml .config/mise/config.toml .nvmrc .node-version) do
      igniter = project(%{path => "22\n"}) |> toolchain() |> install()
      assert igniter.issues == []
      Igniter.Test.assert_unchanged(igniter, path)
      if path != ".tool-versions", do: refute(Igniter.exists?(igniter, ".tool-versions"), path)
      assert no_pin_notice?(igniter, "the application pins its toolchain in #{path}"), path
    end
  end

  test "a new application below a folder that pins a toolchain gets a suggestion, not a .tool-versions" do
    parent = Path.join(System.tmp_dir!(), "brando-toolchain-#{System.unique_integer([:positive])}")
    File.mkdir_p!(parent)
    on_exit(fn -> File.rm_rf!(parent) end)
    File.write!(Path.join(parent, ".tool-versions"), "elixir 1.19.5-otp-28\n")

    igniter = project() |> toolchain(fn _data -> %{parents: [Path.join(parent, "empty"), parent]} end) |> install()
    assert igniter.issues == []
    refute Igniter.exists?(igniter, ".tool-versions")
    assert no_pin_notice?(igniter, "#{parent}/.tool-versions pins a toolchain for the folders below it")
  end

  test "a new install that does not run the version manager's pinned installs suggests the .tool-versions" do
    # Another version; the same Elixir under another name (asdf's 1.20.4,
    # built from source), whose shim would not find 1.20.4-otp-28; an Elixir
    # outside the version managers (Homebrew), with theirs installed too.
    for {tool, running} <- [
          {"erlang", &installed(&1, "erlang", "27.2")},
          {"elixir", &installed(&1, "elixir", "1.19.5-otp-28")},
          {"elixir", &installed(&1, "elixir", "1.20.4")},
          {"elixir", fn _ -> "/opt/homebrew/Cellar/elixir/1.20.4" end}
        ] do
      igniter =
        project()
        |> toolchain(fn data ->
          %{
            running:
              %{"erlang" => installed(data, "erlang", "28.5.0.8"), "elixir" => installed(data, "elixir", "1.20.4-otp-28")}
              |> Map.put(tool, running.(data))
          }
        end)
        |> install()

      assert igniter.issues == []
      refute Igniter.exists?(igniter, ".tool-versions"), running.("data")

      assert no_pin_notice?(igniter, "this install does not run the Erlang 28.5.0.8 and Elixir 1.20.4-otp-28"),
             running.("data")
    end
  end

  test "a new install run through a version manager's alias of the pinned install gets the .tool-versions" do
    igniter =
      project()
      |> toolchain(fn data ->
        File.ln_s!("./1.20.4-otp-28", installed(data, "elixir", "1.20"))
        %{running: %{"erlang" => installed(data, "erlang", "28.5.0.8"), "elixir" => installed(data, "elixir", "1.20")}}
      end)
      |> install()

    assert IgniterCase.source(igniter, ".tool-versions") == Templates.contents(:copy, "tool-versions")
  end

  test "the running Erlang and Elixir are pinned installs only where asdf or mise installed them under the pinned names" do
    pins = %{"erlang" => "28.5.0.8", "elixir" => "1.20.4-otp-28"}
    elixir = :code.lib_dir(:elixir) |> Path.join("../..") |> Path.expand()
    erlang = to_string(:code.root_dir())
    mise = data_dir([])
    asdf = data_dir([])
    env = Map.new(~w(MISE_DATA_DIR ASDF_DATA_DIR), &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(env, fn {key, value} -> if value, do: System.put_env(key, value), else: System.delete_env(key) end)
    end)

    System.put_env(%{"MISE_DATA_DIR" => mise, "ASDF_DATA_DIR" => asdf})

    link = fn dir, tool, name, target ->
      File.mkdir_p!(Path.join([dir, "installs", tool]))
      File.ln_s!(target, installed(dir, tool, name))
    end

    refute Toolchain.pinned_install?(pins)

    # The running Elixir, named as asdf names one it built from source.
    link.(mise, "erlang", "28.5.0.8", erlang)
    link.(mise, "elixir", "1.20.4", elixir)
    refute Toolchain.pinned_install?(pins)

    # The pinned names, but Elixir with another manager than Erlang.
    link.(asdf, "elixir", "1.20.4-otp-28", elixir)
    refute Toolchain.pinned_install?(pins)

    link.(asdf, "erlang", "28.5.0.8", erlang)
    assert Toolchain.pinned_install?(pins)
  end

  test "the folders searched for a pin stop at the home folder, a symlinked one included" do
    base = data_dir([]) |> Brando.Utils.real_path()
    home = Path.join(base, "home")
    File.mkdir_p!(Path.join(home, "dev/app"))
    File.write!(Path.join(home, ".tool-versions"), "elixir 1.19.5-otp-28\n")
    File.ln_s!(home, Path.join(base, "link"))

    # As File.cwd!/0 gives it: the real path.
    for given <- [home, Path.join(base, "link")] do
      assert Toolchain.parents(Path.join(home, "dev/app"), given) == [Path.join(home, "dev")], given
    end
  end

  test "a rerun on an application without a .tool-versions leaves it so, without a notice" do
    installed =
      project()
      |> toolchain(
        &%{running: %{"erlang" => installed(&1, "erlang", "27.2"), "elixir" => installed(&1, "elixir", "1.20.4-otp-28")}}
      )
      |> install()

    rerun = installed |> IgniterCase.apply_and_reload() |> toolchain() |> install()
    assert rerun.issues == []
    refute Igniter.exists?(rerun, ".tool-versions")
    refute notice?(rerun, ".tool-versions")
  end

  test "the .tool-versions template pins what the Dockerfile and asset templates build with" do
    pins =
      for line <- String.split(Templates.contents(:copy, "tool-versions"), "\n", trim: true), into: %{} do
        [tool, version] = String.split(line)
        {tool, version}
      end

    assert pins |> Map.keys() |> Enum.sort() == ~w(elixir erlang nodejs pnpm)

    dockerfile = Templates.contents(:copy, "Dockerfile")
    assert [_ | _] = pnpm = Regex.scan(~r/pnpm@(\S+)/, dockerfile, capture: :all_but_first)
    assert Enum.uniq(pnpm) == [[pins["pnpm"]]]

    for package <- ~w(assets/backend/package.json assets/frontend/package.json) do
      assert Jason.decode!(Templates.contents(:copy, package))["packageManager"] == "pnpm@#{pins["pnpm"]}", package
    end

    assert [_ | _] = node = Regex.scan(~r/^FROM\s+node:(\d+)/m, dockerfile, capture: :all_but_first)
    assert Enum.uniq(node) == [[pins["nodejs"] |> String.split(".") |> hd()]]

    # The Erlang and Elixir each twined/fehn tag the Dockerfile may build on
    # has (4.2 and 4.2-noble are Ubuntu 24.04, 4.2-jammy 22.04, 4.2-focal
    # 20.04); a new tag goes here when the pins move to it.
    fehn =
      ~w(4.2 4.2-noble 4.2-jammy)
      |> Map.new(&{&1, %{"erlang" => "28.5.0.8", "elixir" => "1.20.4-otp-28"}})
      |> Map.put("4.2-focal", %{"erlang" => "28.4.3", "elixir" => "1.19.5-otp-28"})

    assert [[tag]] = Regex.scan(~r/^FROM\s+(?:--\S+\s+)*twined\/fehn:(\S+)/m, dockerfile, capture: :all_but_first)

    assert Map.take(pins, ~w(erlang elixir)) == fehn[tag],
           "twined/fehn:#{tag} does not build with the pinned Erlang and Elixir"

    # Brando's own toolchain, which CI tests with.
    mise = File.read!(".mise.toml")

    for {tool, key} <- [{"erlang", "erlang"}, {"elixir", "elixir"}, {"nodejs", "node"}] do
      assert mise =~ ~s(#{key} = "#{pins[tool]}"), tool
    end
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

  @phx_static Map.new(
                ~w(favicon.ico logo.svg robots.txt),
                &{&1, File.read!(Path.expand("../../../fixtures/phx_new/#{&1}", __DIR__))}
              )

  defp phx_static(overrides \\ %{}) do
    Map.merge(
      %{
        "priv/static/favicon.ico" => @phx_static["favicon.ico"],
        "priv/static/images/logo.svg" => @phx_static["logo.svg"],
        "priv/static/robots.txt" => @phx_static["robots.txt"]
      },
      overrides
    )
  end

  test "phx.new's favicon and logo leave priv/static, which the release build does not copy, once" do
    igniter = install(project(phx_static()), ["--yes", "--no-public-site"])
    assert igniter.issues == []

    assert "priv/static/favicon.ico" in igniter.rms
    # Without the public site Plug.Static answers /robots.txt, from the frontend build's copy.
    assert igniter.moves == %{
             "priv/static/images/logo.svg" => "assets/frontend/public/images/logo.svg",
             "priv/static/robots.txt" => "assets/frontend/public/robots.txt"
           }

    refute notice?(igniter, "is not the file mix phx.new writes")

    applied = IgniterCase.apply_and_reload(igniter)
    refute Igniter.exists?(applied, "priv/static/favicon.ico")
    refute Igniter.exists?(applied, "priv/static/images/logo.svg")
    refute Igniter.exists?(applied, "priv/static/robots.txt")
    assert IgniterCase.source(applied, "assets/frontend/public/images/logo.svg") == @phx_static["logo.svg"]
    assert IgniterCase.source(applied, "assets/frontend/public/robots.txt") == @phx_static["robots.txt"]

    rerun = install(applied)
    assert rerun.issues == []
    assert rerun.rms == []
    assert rerun.moves == %{}

    Igniter.Test.assert_unchanged(rerun, [
      "assets/frontend/public/images/logo.svg",
      "assets/frontend/public/robots.txt"
    ])

    refute notice?(rerun, "is not the file mix phx.new writes")
  end

  test "with the public site robots.txt is left to the SEO settings, also on a rerun" do
    custom = "User-agent: *\nDisallow: /private/\n"
    igniter = install(project(phx_static(%{"priv/static/robots.txt" => custom})))
    assert igniter.issues == []
    refute Map.has_key?(igniter.moves, "priv/static/robots.txt")
    assert notice?(igniter, "BrandoWeb.SEOController answers")

    rerun = igniter |> IgniterCase.apply_and_reload() |> install()
    refute Map.has_key?(rerun.moves, "priv/static/robots.txt")
    Igniter.Test.assert_unchanged(rerun, "priv/static/robots.txt")
    refute notice?(rerun, "move it to assets/frontend/public/robots.txt")
  end

  test "changed priv/static files are kept with a notice, and the frontend build's copies are left alone" do
    changed =
      install(
        project(
          phx_static(%{
            "priv/static/favicon.ico" => "site favicon",
            "priv/static/images/logo.svg" => "<svg>site logo</svg>\n",
            "priv/static/robots.txt" => "User-agent: *\nDisallow: /private/\n"
          })
        ),
        ["--yes", "--no-public-site"]
      )

    assert changed.rms == []
    assert changed.moves == %{}

    Igniter.Test.assert_unchanged(changed, [
      "priv/static/favicon.ico",
      "priv/static/images/logo.svg",
      "priv/static/robots.txt"
    ])

    # Each named as ignored by the .gitignore lines for what the builds write.
    for {path, public} <- [
          {"priv/static/favicon.ico", "assets/frontend/public/favicon.ico"},
          {"priv/static/images/logo.svg", "assets/frontend/public/images/logo.svg"},
          {"priv/static/robots.txt", "assets/frontend/public/robots.txt"}
        ] do
      assert Enum.any?(
               changed.notices,
               &(&1 =~ "#{path} is not the file mix phx.new writes" and &1 =~ "Git ignores it unless it is committed" and
                   &1 =~ "To ship and track it, move it to #{public}")
             ),
             path
    end

    # What the frontend build copies from assets/frontend/public: Brando's favicon and the site's logo.
    built =
      install(
        project(%{
          "priv/static/favicon.ico" => Templates.contents(:copy, "assets/frontend/public/favicon.ico"),
          "priv/static/images/logo.svg" => "<svg>site logo</svg>\n",
          "assets/frontend/public/images/logo.svg" => "<svg>site logo</svg>\n"
        })
      )

    assert built.rms == []
    Igniter.Test.assert_unchanged(built, ["priv/static/favicon.ico", "priv/static/images/logo.svg"])
    refute notice?(built, "is not the file mix phx.new writes")

    # phx.new's logo goes when the site has its own, which the build copies over it.
    own = install(project(phx_static(%{"assets/frontend/public/images/logo.svg" => "<svg>site logo</svg>\n"})))
    assert "priv/static/images/logo.svg" in own.rms
    Igniter.Test.assert_unchanged(own, "assets/frontend/public/images/logo.svg")

    # A changed logo beside the site's own.
    both =
      install(
        project(%{
          "priv/static/images/logo.svg" => "<svg>old logo</svg>\n",
          "assets/frontend/public/images/logo.svg" => "<svg>site logo</svg>\n"
        })
      )

    assert both.rms == []
    assert notice?(both, "Compare it with assets/frontend/public/images/logo.svg")
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
