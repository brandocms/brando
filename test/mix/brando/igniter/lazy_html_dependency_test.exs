defmodule Mix.Brando.Igniter.LazyHTMLDependencyTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.LazyHTMLDependency

  defp project(deps) do
    IgniterCase.phoenix_project(
      files: %{
        "mix.exs" => """
        defmodule Studio.MixProject do
          use Mix.Project
          def project, do: [app: :studio, version: "0.1.0", deps: deps()]
          def application, do: [mod: {Studio.Application, []}]

          defp deps do
            [
              {:phoenix, "~> 1.8.1"},
        #{Enum.map_join(deps, "\n", &"      #{&1},")}
              {:brando, path: "../framework"}
            ]
          end
        end
        """
      }
    )
  end

  test "phx.new's test-only lazy_html becomes a runtime dependency, in its place" do
    result = [~s({:lazy_html, ">= 0.1.0", only: :test}), ~s({:jason, "~> 1.2"})] |> project() |> LazyHTMLDependency.plan()

    assert result.issues == []
    assert IgniterCase.source(result, "mix.exs") =~ ~s({:phoenix, "~> 1.8.1"},\n      {:lazy_html, ">= 0.1.0"},\n)
    refute IgniterCase.source(result, "mix.exs") =~ "only: :test"
    assert {"deps.get", []} in result.tasks

    # Other options stay, and so does a list of environments' worth of `only:`
    result =
      [~s({:lazy_html, "~> 0.1.14", only: [:dev, :test], override: true})] |> project() |> LazyHTMLDependency.plan()

    assert IgniterCase.source(result, "mix.exs") =~ ~s({:lazy_html, "~> 0.1.14", override: true},)
  end

  test "an application without lazy_html gets Brando's line" do
    result = [] |> project() |> LazyHTMLDependency.plan()

    assert result.issues == []
    assert IgniterCase.source(result, "mix.exs") =~ ~s({:lazy_html, "~> 0.1.13"})
    assert {"deps.get", []} in result.tasks
  end

  test "a runtime lazy_html, in any form, keeps its mix.exs" do
    for dep <- [~s({:lazy_html, ">= 0.1.0"}), ~s({:lazy_html, github: "dashbitco/lazy_html"})] do
      result = [dep] |> project() |> LazyHTMLDependency.plan()

      Igniter.Test.assert_unchanged(result, "mix.exs")
      assert result.tasks == []
    end
  end

  test "an only: it cannot read, or runtime: false, gets a notice" do
    for dep <- [
          ~s|{:lazy_html, ">= 0.1.0", only: ~w(test)a}|,
          ~s|{:lazy_html, ">= 0.1.0", only: test_envs()}|,
          ~s({:lazy_html, ">= 0.1.0", runtime: false})
        ] do
      result = [dep] |> project() |> LazyHTMLDependency.plan()

      Igniter.Test.assert_unchanged(result, "mix.exs")
      assert Enum.any?(result.notices, &(&1 =~ "left this line in mix.exs as it is")), dep
    end
  end

  test "a deps/0 Igniter cannot read gets a notice naming the line" do
    result =
      IgniterCase.phoenix_project(
        files: %{
          "mix.exs" => """
          defmodule Studio.MixProject do
            use Mix.Project
            def project, do: [app: :studio, version: "0.1.0", deps: deps()]
            defp deps, do: base() ++ [{:brando, path: "../framework"}] |> Enum.uniq()
            defp base, do: []
          end
          """
        }
      )
      |> LazyHTMLDependency.plan()

    Igniter.Test.assert_unchanged(result, "mix.exs")
    assert Enum.any?(result.notices, &(&1 =~ ~s(add {:lazy_html, "~> 0.1.13"})))
  end

  test "the installer makes it a runtime dependency" do
    result =
      [~s({:lazy_html, ">= 0.1.0", only: :test})]
      |> project()
      |> Igniter.compose_task(Mix.Tasks.Brando.Install, [])

    assert result.issues == []
    assert IgniterCase.source(result, "mix.exs") =~ ~s({:lazy_html, ">= 0.1.0"},)
  end
end
