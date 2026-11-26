defmodule Mix.Brando.Igniter.EncryptionSecretTest do
  # Brando.Crypto's secret, one per site: what brando.install writes for a new
  # site, what brando.install.secrets fills in, and what an upgrade writes for
  # a site that predates it.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Install.Docker
  alias Mix.Tasks.Brando.Install
  alias Mix.Tasks.Brando.Install.Secrets

  @moduletag :tmp_dir

  @marker "__BRANDO_ENCRYPTION_SECRET__"
  @secret_files ~w(.envrc.prod .envrc.staging config/dev.secret.exs)
  @config_files ~w(config/config.exs config/dev.exs config/prod.exs config/runtime.exs)
  @fetch ~s|config :brando, Brando.Crypto, secret: System.fetch_env!("BRANDO_ENCRYPTION_SECRET")|

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => "import Config\nimport_config \"\#{config_env()}.exs\"\n",
            "config/dev.exs" => "import Config\nconfig :studio, StudioWeb.Endpoint, check_origin: false\n",
            "config/prod.exs" => "import Config\nconfig :logger, level: :info\n",
            "config/runtime.exs" => """
            import Config

            if config_env() == :prod do
              config :studio, StudioWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")
            end
            """
          },
          files
        )
    )
  end

  defp install(igniter), do: Igniter.compose_task(igniter, Install, ["--yes"])

  defp upgrade(igniter),
    do:
      Igniter.compose_task(igniter, Mix.Tasks.Brando.Upgrade, ["0.54.0", Application.spec(:brando, :vsn) |> to_string()])

  defp notice?(igniter, text), do: Enum.any?(igniter.notices, &(&1 =~ text))

  defp secrets_task(igniter), do: for({"brando.install.secrets", paths} <- igniter.tasks, do: paths)

  # What the secrets task writes, in place of the markers.
  defp filled(igniter) do
    @secret_files
    |> Enum.filter(&Igniter.exists?(igniter, &1))
    |> Enum.reduce(igniter, &fill(&2, &1))
  end

  defp fill(igniter, path) do
    Igniter.update_file(igniter, path, fn source ->
      Rewrite.Source.update(source, :content, &String.replace(&1, ~r/__BRANDO_[A-Z_]+__/, "filled-in"))
    end)
  end

  # Other planners change these files too; this one adds nothing to them.
  defp refute_set_up(igniter) do
    refute IgniterCase.source(igniter, "config/runtime.exs") =~ "BRANDO_ENCRYPTION_SECRET"
    refute IgniterCase.source(igniter, "config/dev.exs") =~ "dev.secret.exs"
    refute Igniter.exists?(igniter, "config/dev.secret.exs")
  end

  defp in_docker_context?(igniter, path),
    do: not Docker.context_excludes?(IgniterCase.source(igniter, ".dockerignore"), path)

  defp write!(dir, files) do
    for {path, contents} <- files do
      File.mkdir_p!(Path.dirname(Path.join(dir, path)))
      File.write!(Path.join(dir, path), contents)
    end
  end

  # The configuration a config file evaluates to, with the environment
  # variable set to `value` (nil: unset).
  defp read_config(path, env, value) do
    previous = System.get_env("BRANDO_ENCRYPTION_SECRET")
    if value, do: System.put_env("BRANDO_ENCRYPTION_SECRET", value), else: System.delete_env("BRANDO_ENCRYPTION_SECRET")

    try do
      path |> Config.Reader.read!(env: env, target: :host) |> get_in([:brando, Brando.Crypto, :secret])
    after
      if previous,
        do: System.put_env("BRANDO_ENCRYPTION_SECRET", previous),
        else: System.delete_env("BRANDO_ENCRYPTION_SECRET")
    end
  end

  describe "a new install" do
    test "plans one marker in the environment files and config/dev.secret.exs, and reads it in prod and dev" do
      igniter = install(project())
      assert igniter.issues == []

      # The value is made after the plan is accepted: the diff holds the marker only.
      for path <- @secret_files do
        assert [_] = Regex.scan(~r/#{@marker}/, IgniterCase.source(igniter, path)), path
      end

      assert IgniterCase.source(igniter, ".envrc.prod") =~ ~s(export BRANDO_ENCRYPTION_SECRET="#{@marker}")
      assert IgniterCase.source(igniter, ".envrc.staging") =~ ~s(export BRANDO_ENCRYPTION_SECRET="#{@marker}")

      assert IgniterCase.source(igniter, "config/dev.secret.exs") =~
               ~s(config :brando, Brando.Crypto, secret: "#{@marker}")

      assert secrets_task(igniter) == [@secret_files]

      runtime = IgniterCase.source(igniter, "config/runtime.exs")
      [prod_block] = Regex.run(~r/^if config_env\(\) == :prod do\n.*?^end$/ms, runtime)
      assert prod_block =~ @fetch

      assert IgniterCase.source(igniter, "config/dev.exs") =~
               ~s|if File.exists?(Path.join(__DIR__, "dev.secret.exs")), do: import_config("dev.secret.exs")|

      assert IgniterCase.source(igniter, ".gitignore") =~ ~r{^/config/dev\.secret\.exs$}m
      refute notice?(igniter, "production's current")
    end

    test "dev.exs reads the secret from config/dev.secret.exs, and runs without it", %{tmp_dir: dir} do
      igniter = install(project())

      write!(dir, %{"config/dev.exs" => IgniterCase.source(igniter, "config/dev.exs")})
      assert read_config(Path.join(dir, "config/dev.exs"), :dev, nil) == nil

      dev_secret = IgniterCase.source(igniter, "config/dev.secret.exs") |> String.replace(@marker, "the site's value")
      write!(dir, %{"config/dev.secret.exs" => dev_secret})
      assert read_config(Path.join(dir, "config/dev.exs"), :dev, nil) == "the site's value"

      write!(dir, %{"config/runtime.exs" => IgniterCase.source(igniter, "config/runtime.exs")})
      assert read_config(Path.join(dir, "config/runtime.exs"), :prod, "from the server") == "from the server"
      assert read_config(Path.join(dir, "config/runtime.exs"), :dev, "from the server") == nil
    end

    test "Git and the Docker build leave config/dev.secret.exs out", %{tmp_dir: dir} do
      igniter = install(project())

      write!(dir, %{".gitignore" => IgniterCase.source(igniter, ".gitignore")})
      {_, 0} = System.cmd("git", ["init", "--quiet", dir])

      assert {_, 0} = System.cmd("git", ["-C", dir, "check-ignore", "--no-index", "config/dev.secret.exs"])
      assert {_, 1} = System.cmd("git", ["-C", dir, "check-ignore", "--no-index", "config/dev.exs"])

      # The Dockerfile copies config/ into the build: the rest of it goes in.
      assert IgniterCase.source(igniter, "Dockerfile") =~ "COPY config/ ./config"
      refute in_docker_context?(igniter, "config/dev.secret.exs")

      for path <- ~w(config/config.exs config/dev.exs config/prod.exs config/runtime.exs config/brando.exs) do
        assert in_docker_context?(igniter, path), path
      end
    end

    test "a rerun replaces nothing" do
      rerun = project() |> install() |> filled() |> IgniterCase.apply_and_reload() |> install()

      assert rerun.issues == []
      Igniter.Test.assert_unchanged(rerun, @config_files ++ @secret_files ++ ~w(.gitignore .dockerignore))
      assert secrets_task(rerun) == []
      refute notice?(rerun, "BRANDO_ENCRYPTION_SECRET")
    end

    test "a rerun after an interrupted secrets task fills in the files still holding the marker" do
      installed = project() |> install() |> IgniterCase.apply_and_reload()

      # The task stopped after .envrc.prod
      rerun = installed |> fill(".envrc.prod") |> IgniterCase.apply_and_reload() |> install()

      assert rerun.issues == []
      assert secrets_task(rerun) == [~w(.envrc.staging config/dev.secret.exs)]
      Igniter.Test.assert_unchanged(rerun, @config_files ++ @secret_files)
    end

    test "over a project whose .envrc.prod predates the variable, keeps it and writes what an upgrade does" do
      envrc = "export PHX_HOST=\"realsite.no\"\nexport SECRET_KEY_BASE=\"production's\"\n"
      igniter = install(project(%{".envrc.prod" => envrc}))

      assert igniter.issues == []
      Igniter.Test.assert_unchanged(igniter, ".envrc.prod")
      # The right value is production's secret_key_base, which the installer cannot know.
      refute Igniter.exists?(igniter, "config/dev.secret.exs")
      refute IgniterCase.source(igniter, ".envrc.staging") =~ "BRANDO_ENCRYPTION_SECRET"
      assert secrets_task(igniter) == [~w(.envrc.staging)]

      runtime = IgniterCase.source(igniter, "config/runtime.exs")
      refute runtime =~ "fetch_env!(\"BRANDO_ENCRYPTION_SECRET\")"
      assert runtime =~ ~s|System.get_env("BRANDO_ENCRYPTION_SECRET", "")|
      assert IgniterCase.source(igniter, "config/dev.exs") =~ ~s|import_config("dev.secret.exs")|
      assert notice?(igniter, "production's current")
      refute in_docker_context?(igniter, "config/dev.secret.exs")
    end

    test "a project that configures Brando.Crypto itself keeps its configuration" do
      own = "import Config\nconfig :brando, Brando.Crypto, secret: System.fetch_env!(\"MY_SECRET\")\n"
      igniter = install(project(%{"config/prod.exs" => own}))

      assert igniter.issues == []
      refute_set_up(igniter)
      assert IgniterCase.source(igniter, "config/prod.exs") =~ ~s|secret: System.fetch_env!("MY_SECRET")|
      refute IgniterCase.source(igniter, ".envrc.prod") =~ "BRANDO_ENCRYPTION_SECRET"
      assert secrets_task(igniter) == [~w(.envrc.prod .envrc.staging)]
    end

    test "a project whose own configuration reads BRANDO_ENCRYPTION_SECRET gets it in new environment files" do
      own = "import Config\nconfig :brando, Brando.Crypto, secret: System.get_env(\"BRANDO_ENCRYPTION_SECRET\")\n"
      igniter = install(project(%{"config/prod.exs" => own}))

      refute_set_up(igniter)
      assert IgniterCase.source(igniter, ".envrc.prod") =~ ~s(export BRANDO_ENCRYPTION_SECRET="#{@marker}")
    end
  end

  describe "brando.install.secrets" do
    defp marked_files(dir) do
      igniter = install(project())
      write!(dir, Map.new(@secret_files, &{&1, IgniterCase.source(igniter, &1)}))
    end

    defp encryption_secret(path) do
      regex =
        if path == "config/dev.secret.exs",
          do: ~r/secret: "([^"]+)"/,
          else: ~r/BRANDO_ENCRYPTION_SECRET="([^"]+)"/

      [_, value] = Regex.run(regex, File.read!(path))
      value
    end

    test "gives the three files one value, and each its own secret_key_base", %{tmp_dir: dir} do
      marked_files(dir)

      File.cd!(dir, fn ->
        Secrets.run(@secret_files)

        for path <- @secret_files do
          refute File.read!(path) =~ "__BRANDO_", path
          assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600, path
        end

        assert [value] = @secret_files |> Enum.map(&encryption_secret/1) |> Enum.uniq()
        assert byte_size(value) == 64

        [prod_key, staging_key] =
          for path <- ~w(.envrc.prod .envrc.staging),
              do: Regex.run(~r/SECRET_KEY_BASE="([^"]+)"/, File.read!(path)) |> List.last()

        assert prod_key != staging_key
        refute value in [prod_key, staging_key]
      end)
    end

    test "interrupted after any file, a retry gives the rest the same value", %{tmp_dir: dir} do
      for done <- 1..2 do
        marked_files(dir)

        File.cd!(dir, fn ->
          # The task filled the first `done` files, then stopped; the rerun
          # finds the others still marked.
          Secrets.run(Enum.take(@secret_files, done))
          Secrets.run(Enum.drop(@secret_files, done))

          assert [_value] = @secret_files |> Enum.map(&encryption_secret/1) |> Enum.uniq(), "after #{done}"
        end)
      end
    end

    test "a new environment file gets the value the others hold", %{tmp_dir: dir} do
      marked_files(dir)

      File.cd!(dir, fn ->
        Secrets.run(~w(config/dev.secret.exs))
        Secrets.run(~w(.envrc.staging .envrc.prod))

        assert [_value] = @secret_files |> Enum.map(&encryption_secret/1) |> Enum.uniq()
      end)
    end

    test "two files holding different values stop it, naming them", %{tmp_dir: dir} do
      marked_files(dir)

      File.cd!(dir, fn ->
        File.write!(".envrc.prod", ~s(export BRANDO_ENCRYPTION_SECRET="production's"\n))
        File.write!("config/dev.secret.exs", ~s(import Config\nconfig :brando, Brando.Crypto, secret: "another"\n))

        assert_raise Mix.Error, ~r/\.envrc\.prod, config\/dev\.secret\.exs hold different Brando\.Crypto secrets/, fn ->
          Secrets.run(~w(.envrc.staging))
        end

        assert File.read!(".envrc.staging") =~ @marker
      end)
    end
  end

  describe "an upgrade" do
    test "reads BRANDO_ENCRYPTION_SECRET in prod only when it is set, and imports config/dev.secret.exs", %{tmp_dir: dir} do
      result = upgrade(project(%{".dockerignore" => "_build\ndeps\n"}))
      assert result.issues == []

      runtime = IgniterCase.source(result, "config/runtime.exs")

      assert runtime =~
               ~r/^if config_env\(\) == :prod do\n  encryption_secret = System.get_env\("BRANDO_ENCRYPTION_SECRET", ""\)$/m

      refute runtime =~ "fetch_env!(\"BRANDO_ENCRYPTION_SECRET\")"

      write!(dir, %{"config/runtime.exs" => runtime})
      path = Path.join(dir, "config/runtime.exs")
      # A release deployed before the variable exists boots as before.
      assert read_config(path, :prod, nil) == nil
      assert read_config(path, :prod, "") == nil
      assert read_config(path, :prod, "production's secret_key_base") == "production's secret_key_base"

      assert IgniterCase.source(result, "config/dev.exs") =~ ~s|import_config("dev.secret.exs")|
      # Only production's secret_key_base is right, which the task cannot know.
      refute Igniter.exists?(result, "config/dev.secret.exs")
      assert secrets_task(result) == []

      assert IgniterCase.source(result, ".gitignore") =~ ~r{^/config/dev\.secret\.exs$}m
      assert IgniterCase.source(result, ".dockerignore") =~ ~r{^config/dev\.secret\.exs$}m
      refute in_docker_context?(result, "config/dev.secret.exs")
      assert in_docker_context?(result, "config/dev.exs")

      assert [steps] = Enum.filter(result.notices, &(&1 =~ "BRANDO_ENCRYPTION_SECRET"))
      [one, two, three] = for n <- 1..3, do: steps |> :binary.match("#{n}. ") |> elem(0)
      assert one < two and two < three
    end

    test "without a .dockerignore, writes none" do
      result = upgrade(project())
      refute Igniter.exists?(result, ".dockerignore")
    end

    test "run twice, changes nothing the second time" do
      rerun = project() |> upgrade() |> IgniterCase.apply_and_reload() |> upgrade()

      Igniter.Test.assert_unchanged(rerun, @config_files ++ ~w(.gitignore))
      refute notice?(rerun, "BRANDO_ENCRYPTION_SECRET")
    end

    test "a project that configures the secret, in any file and form, is not touched" do
      for {path, contents} <- [
            {"config/runtime.exs", "import Config\nconfig :brando, Brando.Crypto, secret: System.fetch_env!(\"X\")\n"},
            {"config/prod.exs", "import Config\nconfig :brando, Brando.Crypto, [secret: \"literal-secret\"]\n"},
            {"config/config.exs", "import Config\nalias Brando.Crypto\nconfig :brando, Crypto, secret: \"x\"\n"},
            {"config/secrets/prod.exs", "import Config\nconfig :brando, [{Brando.Crypto, secret: \"x\"}]\n"}
          ] do
        result = upgrade(project(%{path => contents}))

        refute_set_up(result)
        refute Igniter.exists?(result, ".gitignore") and IgniterCase.source(result, ".gitignore") =~ "dev.secret.exs"
        refute notice?(result, "BRANDO_ENCRYPTION_SECRET"), path
      end
    end

    test "mix brando.migrate55 writes the same" do
      result = project() |> Igniter.compose_task("brando.migrate55", [])

      assert IgniterCase.source(result, "config/runtime.exs") =~ ~s|System.get_env("BRANDO_ENCRYPTION_SECRET", "")|
      assert [_steps] = Enum.filter(result.notices, &(&1 =~ "BRANDO_ENCRYPTION_SECRET"))
    end
  end
end
