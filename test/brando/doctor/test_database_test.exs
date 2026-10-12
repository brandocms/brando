defmodule Brando.Doctor.TestDatabaseTest do
  use ExUnit.Case, async: false

  alias Brando.Doctor.Checks.TestDatabase
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result

  @dev [hostname: "localhost", port: 5432, database: "lett_dev", username: "postgres"]

  # Lett's config: test.exs names lett_test, and runtime.exs reads the Repo
  # URL from BRANDO_DB_URL in every environment.
  @config """
  import Config
  config :lett, ecto_repos: [Lett.Repo]
  import_config "\#{config_env()}.exs"
  """

  @test """
  import Config
  config :lett, Lett.Repo, username: "postgres", database: "lett_test", hostname: "localhost"
  """

  @runtime """
  import Config

  config :lett, Lett.Repo,
    url: System.get_env("BRANDO_DOCTOR_TEST_DB_URL"),
    pool_size: 15
  """

  setup do
    System.put_env("BRANDO_DOCTOR_TEST_DB_URL", "ecto://postgres:postgres@localhost/lett_dev")
    on_exit(fn -> System.delete_env("BRANDO_DOCTOR_TEST_DB_URL") end)
  end

  defp project(files) do
    root = Path.join(System.tmp_dir!(), "brando_doctor_test_database_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    for {path, contents} <- files do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), contents)
    end

    root
  end

  defp lett(runtime \\ @runtime) do
    project(%{"config/config.exs" => @config, "config/test.exs" => @test, "config/runtime.exs" => runtime})
  end

  test "warns when the test config resolves to the development database" do
    assert {:ok, test_config} = TestDatabase.test_repo_config(lett(), :lett, Lett.Repo)

    assert %Result{status: :warning, summary: summary, fix: fix, items: [item]} =
             TestDatabase.evaluate(test_config, @dev)

    assert summary == "mix test would use the development database lett_dev"
    assert fix =~ "if config_env() != :test do"
    assert item == "test and development both connect to lett_dev on localhost:5432"
  end

  test "passes when runtime.exs reads the URL only outside tests" do
    guarded = """
    import Config

    if config_env() != :test do
      config :lett, Lett.Repo, url: System.get_env("BRANDO_DOCTOR_TEST_DB_URL")
    end
    """

    assert {:ok, test_config} = TestDatabase.test_repo_config(lett(guarded), :lett, Lett.Repo)

    assert %Result{status: :ok, summary: "lett_test, not the development database"} =
             TestDatabase.evaluate(test_config, @dev)
  end

  test "compares host and port as well as the name" do
    assert %Result{status: :ok} =
             TestDatabase.evaluate([url: "ecto://u:p@db.internal:5433/lett_dev"], @dev)

    assert %Result{status: :skipped} = TestDatabase.evaluate([], @dev)
  end

  test "skips config it cannot read for :test" do
    legacy = String.replace(@config, "config_env()", "Mix.env()")
    root = project(%{"config/config.exs" => legacy, "config/test.exs" => @test})
    assert {:error, reason} = TestDatabase.test_repo_config(root, :lett, Lett.Repo)
    assert reason =~ "Mix.env()"

    assert {:error, "no config/config.exs"} = TestDatabase.test_repo_config(project(%{}), :lett, Lett.Repo)

    broken = project(%{"config/config.exs" => "import Config\nraise \"boom\"\n"})
    assert {:error, "could not read the test config: " <> _} = TestDatabase.test_repo_config(broken, :lett, Lett.Repo)
  end

  test "runs in development only" do
    assert %Result{status: :skipped} = TestDatabase.run(Context.new(root: lett(), now: DateTime.utc_now()))
    assert TestDatabase.needs_source?()
  end
end
