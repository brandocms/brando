defmodule Mix.Brando.Igniter.SourceUpgrade.TestEnvironmentTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Brando.Igniter.SourceUpgrade.TestEnvironment

  # Lett's config/runtime.exs: the Repo URL is read in every environment.
  @runtime """
  import Config

  config :lett, LettWeb.Endpoint,
    secret_key_base: System.get_env("BRANDO_SECRET_KEY_BASE"),
    url: [
      scheme: System.get_env("BRANDO_URL_SCHEME"),
      host: System.get_env("BRANDO_URL_HOST")
    ]

  config :lett, Lett.Repo,
    url: System.get_env("BRANDO_DB_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
  """

  # Lett's mix.exs, trimmed: test_paths by environment, `test/unit` missing.
  @mix_exs """
  defmodule Lett.MixProject do
    use Mix.Project

    def project do
      [
        app: :lett,
        version: "2.4.2",
        test_paths: test_paths(Mix.env()),
        deps: deps()
      ]
    end

    # Specify test path per environment
    defp test_paths(:e2e), do: ["test/e2e"]
    defp test_paths(_), do: ["test/unit"]

    defp deps, do: []
  end
  """

  defp scan(files) do
    files = Map.merge(%{"test/e2e/test_helper.exs" => "ExUnit.start()\n"}, files)
    [app_name: :lett, files: files] |> test_project() |> TestEnvironment.warn_test_hazards()
  end

  defp runtime_warnings(runtime) do
    %{"config/runtime.exs" => runtime} |> scan() |> Map.fetch!(:warnings) |> Enum.filter(&(&1 =~ "runtime.exs"))
  end

  test "warns that mix test uses the Repo URL runtime.exs reads in every environment" do
    assert [warning] = runtime_warnings(@runtime)
    assert warning =~ "config/runtime.exs:10: config :lett, Lett.Repo, (BRANDO_DB_URL)"
    assert warning =~ "a `test`" and warning =~ "alias that runs\n`ecto.create` and `ecto.migrate` migrates it"
    assert warning =~ "if config_env() != :test do"
  end

  test "finds the read through a variable, in an else branch, and in a case that reaches :test" do
    variable = """
    import Config
    database_url = System.fetch_env!("DATABASE_URL")
    config :lett, Lett.Repo, url: database_url
    """

    else_branch = """
    import Config

    if config_env() == :prod do
      config :lett, Lett.Repo, url: System.fetch_env!("DATABASE_URL")
    else
      config :lett, Lett.Repo, url: System.get_env("DEV_DATABASE_URL")
    end
    """

    case_clause = """
    import Config

    case config_env() do
      :prod -> config :lett, Lett.Repo, url: System.fetch_env!("DATABASE_URL")
      _ -> config :lett, Lett.Repo, url: System.get_env("DEV_DATABASE_URL")
    end
    """

    assert [warning] = runtime_warnings(variable)
    assert warning =~ "runtime.exs:3: config :lett, Lett.Repo, url: database_url (DATABASE_URL)"

    assert [warning] = runtime_warnings(else_branch)
    assert warning =~ "runtime.exs:6:"
    refute warning =~ "runtime.exs:4:"

    assert [warning] = runtime_warnings(case_clause)
    assert warning =~ "runtime.exs:5:"
  end

  test "accepts URLs read only outside tests" do
    for guard <- [
          "if config_env() == :prod do",
          "if config_env() != :test do",
          "if config_env() in [:prod, :staging] do",
          "unless config_env() == :test do",
          "if config_env() not in [:test] do"
        ] do
      runtime = """
      import Config

      #{guard}
        database_url = System.get_env("DATABASE_URL") || raise "DATABASE_URL is missing"
        config :lett, Lett.Repo, url: database_url
      end
      """

      assert runtime_warnings(runtime) == [], guard
    end

    assert runtime_warnings("import Config\nconfig :lett, Lett.Repo, pool_size: 10\n") == []
    assert runtime_warnings(~s|import Config\nconfig :lett, Lett.Cache, url: System.get_env("REDIS_URL")\n|) == []
  end

  test "reads `Config.config_env()` as `config_env()`" do
    # koi's config/runtime.exs: the e2e branch is not reached in :test, the
    # else branch is.
    runtime = """
    import Config

    if Config.config_env() == :e2e do
      config :koi, Koi.Repo,
        url: System.get_env("BRANDO_DB_TEST_URL"),
        pool: Ecto.Adapters.SQL.Sandbox
    else
      config :koi, Koi.Repo,
        url: System.get_env("BRANDO_DB_URL"),
        pool_size: 15
    end
    """

    assert [warning] = runtime_warnings(runtime)
    assert warning =~ "runtime.exs:8:"
    refute warning =~ "runtime.exs:4:"
    refute warning =~ "BRANDO_DB_TEST_URL"
  end

  test "the installer's runtime.exs reads the URL only outside tests" do
    template = File.read!(Application.app_dir(:brando, "priv/templates/brando.install/config/runtime.exs"))
    runtime = EEx.eval_string(template, application_name: "lett", application_module: "Lett")

    assert runtime_warnings(runtime) == []
  end

  test "warns about test_paths that name a missing directory" do
    igniter = scan(%{"mix.exs" => @mix_exs})

    assert [warning] = Enum.filter(igniter.warnings, &(&1 =~ "test_paths"))
    assert warning =~ "`test_paths` in mix.exs:15 names directories that do not exist: `test/unit`."
    assert warning =~ ~s|"test/unit/test_helper.exs" does not exist|
    refute warning =~ "test/e2e"
    assert_unchanged(igniter)
  end

  test "reads a literal test_paths list, and is quiet when the directories exist" do
    literal = String.replace(@mix_exs, "test_paths(Mix.env())", ~s(["test/unit"]))
    assert [warning] = %{"mix.exs" => literal} |> scan() |> Map.fetch!(:warnings)
    assert warning =~ "mix.exs:8 names"

    fixed = String.replace(@mix_exs, ~s(["test/unit"]), ~s(["test"]))
    assert scan(%{"mix.exs" => fixed, "test/test_helper.exs" => "ExUnit.start()\n"}).warnings == []
  end

  test "mix brando.migrate55 warns" do
    igniter =
      [app_name: :lett, files: %{"config/runtime.exs" => @runtime, "mix.exs" => @mix_exs}]
      |> test_project()
      |> Mix.Tasks.Brando.Migrate55.igniter()

    assert Enum.any?(igniter.warnings, &(&1 =~ "config/runtime.exs:10:"))
    assert Enum.any?(igniter.warnings, &(&1 =~ "`test_paths` in mix.exs:15"))
  end
end
