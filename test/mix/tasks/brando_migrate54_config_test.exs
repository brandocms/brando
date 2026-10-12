defmodule Mix.Tasks.Brando.Migrate54ConfigTest do
  use ExUnit.Case, async: true

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

  test "adds the code reloader listener and updates deprecated config" do
    igniter = migrate(%{"mix.exs" => @mix_exs, "config/test.exs" => @test_config})

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
