defmodule Mix.Tasks.Brando.Migrate54ConfigTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @mix_exs """
  defmodule Lett.MixProject do
    use Mix.Project

    def project do
      [
        app: :lett,
        version: "2.4.2",
        elixir: "~> 1.18",
        deps: deps()
      ]
    end

    defp deps do
      [
        {:phoenix, "~> 1.8.15"},
        {:brando, path: "../brando"}
      ]
    end
  end
  """

  @test_config """
  use Mix.Config

  # Configure your database
  config :lett, Lett.Repo,
    username: "postgres",
    pool: Ecto.Adapters.SQL.Sandbox

  # Print only warnings and errors during test
  config :logger, level: :warn
  config :logger, :console, format: "[$level] $message\\n", level: :warn
  config :lett, :mailer, log: :warn
  """

  @mailer """
  defmodule Lett.Mailer do
    use Swoosh.Mailer, otp_app: :lett
  end
  """

  # koi's config/brando.exs before the upgrade
  @brando_config """
  import Config

  config :brando,
    otp_app: :lett,
    app_name: "Lett"

  config :brando, Brando.CDN,
    enabled: false,
    bucket: "lett"
  """

  @repo """
  defmodule Lett.Repo do
    use Ecto.Repo, otp_app: :lett, adapter: Ecto.Adapters.Postgres
  end
  """

  test "writes the Brando settings migrate55 and doctor ask for in one go" do
    files = %{
      "config/brando.exs" => @brando_config,
      "lib/lett/mailer.ex" => @mailer,
      "lib/lett/repo.ex" => @repo,
      "config/config.exs" => "import Config\n\nconfig :lett, ecto_repos: [Lett.Repo]\nimport_config \"brando.exs\"\n"
    }

    igniter = migrate(files)
    brando = source(igniter, "config/brando.exs")

    assert brando =~ "repo_module: Lett.Repo"
    assert brando =~ "mailer: Lett.Mailer"
    assert brando =~ ~s|config :brando, Brando.Mailer, from: {"Lett", "noreply@example.com"}|

    assert_has_notice(igniter, &(&1 =~ "replace the\nplaceholder's `noreply@example.com` before you first compile"))

    # migrate55 then leaves Brando's configuration as it is.
    rerun = igniter |> apply_igniter!() |> include_test_files() |> Mix.Tasks.Brando.Migrate55.igniter()
    assert_unchanged(rerun, ["config/brando.exs"])
  end

  test "writes no placeholder sender when a config file sets one, however nested" do
    runtime = """
    import Config

    if config_env() == :prod do
      config :brando, Brando.Mailer,
        from: {"Lett", System.get_env("MAIL_FROM", "post@studio.test")}
    end
    """

    files = %{
      "config/brando.exs" => @brando_config,
      "config/runtime.exs" => runtime,
      "lib/lett/mailer.ex" => @mailer,
      "config/config.exs" => "import Config\n\nimport_config \"brando.exs\"\n"
    }

    igniter = migrate(files)
    brando = source(igniter, "config/brando.exs")

    assert brando =~ "mailer: Lett.Mailer"
    refute brando =~ "example.com"
    refute Enum.any?(igniter.notices, &(&1 =~ "before you first compile"))
  end

  test "adds the code reloader listener and updates deprecated config" do
    igniter = migrate(%{"mix.exs" => @mix_exs, "config/test.exs" => @test_config, "lib/lett/mailer.ex" => @mailer})

    assert source(igniter, "mix.exs") =~ "      deps: deps(),\n      listeners: [Phoenix.CodeReloader]\n    ]\n"

    assert source(igniter, "config/test.exs") == """
           import Config

           # Configure your database
           config :lett, Lett.Repo,
             username: "postgres",
             pool: Ecto.Adapters.SQL.Sandbox

           # Print only warnings and errors during test
           config :logger, level: :warning
           config :logger, :console, format: "[$level] $message\\n", level: :warning
           config :lett, :mailer, log: :warn
           """

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, ["mix.exs", "config/test.exs"])
  end

  test "adds the listener to an existing list and leaves an application without Phoenix alone" do
    with_listeners =
      String.replace(@mix_exs, ~s(elixir: "~> 1.18",), ~s|elixir: "~> 1.18",\n      listeners: [MyListener],|)

    igniter = migrate(%{"mix.exs" => with_listeners})
    assert source(igniter, "mix.exs") =~ "listeners: [MyListener, Phoenix.CodeReloader],"

    without_phoenix = String.replace(@mix_exs, ~s|{:phoenix, "~> 1.8.15"},\n|, "")
    igniter = migrate(%{"mix.exs" => without_phoenix})
    refute source(igniter, "mix.exs") =~ "listeners"
  end

  defp migrate(files) do
    [app_name: :lett, files: files]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
