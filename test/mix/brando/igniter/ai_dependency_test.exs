defmodule Mix.Brando.Igniter.AIDependencyTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.AIDependency

  @req_llm ~s({:req_llm, "~> 1.29"})

  defp project(files), do: IgniterCase.phoenix_project(files: files)

  defp config(body), do: "import Config\n" <> body

  defp installed_version, do: Application.spec(:brando, :vsn) |> to_string()

  # As mix igniter.upgrade brando runs it (see upgrade_test.exs).
  defp upgrade(igniter, from) do
    %{
      igniter
      | args: %Igniter.Mix.Task.Args{positional: %{packages: ["brando:#{from}:#{installed_version()}"]}, argv_flags: []}
    }
    |> Igniter.CopiedTasks.do_apply_upgrades()
  end

  test "an application that configures AI without req_llm gets it, with a notice naming the settings" do
    result =
      project(%{
        "config/config.exs" => config(~s(import_config "brando.exs"\n)),
        "config/brando.exs" =>
          config("""
          config :brando, Brando.AI, providers: [anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")]]
          config :brando, Brando.AI.Agent, model: "anthropic:claude-opus-5-5"
          """)
      })
      |> AIDependency.plan()

    assert result.issues == []
    assert IgniterCase.source(result, "mix.exs") =~ @req_llm
    assert {"deps.get", []} in result.tasks
    assert [notice] = Enum.filter(result.notices, &(&1 =~ "req_llm"))
    assert notice =~ "Added #{@req_llm} to mix.exs"
    assert notice =~ "Brando.AI providers, Brando.AI.Agent model"
  end

  test "each setting the doctor counts is AI, in any of the configs a release reads" do
    for {file, body} <- [
          {"config/config.exs", ~s(config :brando, Brando.AI, models: [default: "openai:gpt-4o"])},
          {"config/dev.exs", ~s(config :brando, Brando.AI, default_model: "openai:gpt-4o")},
          {"config/prod.exs", ~s(config :brando, Brando.AI, prompts: [alt: [model: "openai:gpt-4o"]])},
          {"config/runtime.exs", ~s(config :brando, Brando.AI, fields: [alt: [prompt: "Describe it"]])},
          {"config/runtime.exs", ~s|config :brando, Brando.AI, openai_api_key: System.get_env("OPENAI_API_KEY")|},
          {"config/runtime.exs", ~s|config :req_llm, anthropic_api_key: System.fetch_env!("ANTHROPIC_API_KEY")|},
          {"config/runtime.exs", ~s|config :req_llm, :anthropic_api_key, System.fetch_env!("ANTHROPIC_API_KEY")|}
        ] do
      result = project(%{file => config(body)}) |> AIDependency.plan()
      assert IgniterCase.source(result, "mix.exs") =~ @req_llm, "#{file}: #{body}"
    end
  end

  test "an application that has req_llm, in any form, keeps its mix.exs" do
    for dep <- [
          @req_llm,
          ~s({:req_llm, github: "agentjido/req_llm", branch: "main"}),
          ~s({:req_llm, "~> 1.30", override: true})
        ] do
      result =
        project(%{
          "mix.exs" => """
          defmodule Studio.MixProject do
            use Mix.Project
            def project, do: [app: :studio, version: "0.1.0", deps: deps()]
            defp deps, do: [{:brando, path: "../framework"}, #{dep}]
          end
          """,
          "config/config.exs" => config(~s(config :brando, Brando.AI, models: [default: "openai:gpt-4o"]))
        })
        |> AIDependency.plan()

      Igniter.Test.assert_unchanged(result, "mix.exs")
      assert result.tasks == []
      refute Enum.any?(result.notices, &(&1 =~ "req_llm"))
    end
  end

  test "an application without AI settings, or with AI off, keeps its mix.exs" do
    for files <- [
          %{},
          %{"config/config.exs" => config(~s(config :brando, media_path: "./media"))},
          # The cassette client of the test config is no AI of its own.
          %{"config/test.exs" => config("config :brando, Brando.AI, client: Brando.AI.Cassette")},
          %{"config/config.exs" => config("config :brando, Brando.AI, enabled: true, providers: [], models: nil")},
          %{
            "config/config.exs" =>
              config(~s(config :brando, Brando.AI, enabled: false, models: [default: "openai:gpt-4o"]))
          }
        ] do
      result = files |> project() |> AIDependency.plan()
      Igniter.Test.assert_unchanged(result, "mix.exs")
      assert result.tasks == []
      refute Enum.any?(result.notices, &(&1 =~ "req_llm")), inspect(files)
    end
  end

  describe "mix igniter.upgrade brando" do
    test "adds req_llm for an application that configures AI" do
      result =
        %{"config/config.exs" => config(~s(config :brando, Brando.AI, models: [default: "openai:gpt-4o"]))}
        |> project()
        |> upgrade("0.54.0")

      assert result.issues == []
      assert IgniterCase.source(result, "mix.exs") =~ @req_llm
      assert Enum.any?(result.notices, &(&1 =~ "Added #{@req_llm} to mix.exs"))
    end

    test "leaves mix.exs alone without AI settings" do
      result = %{} |> project() |> upgrade("0.54.0")

      assert result.issues == []
      refute IgniterCase.source(result, "mix.exs") =~ "req_llm"
      refute Enum.any?(result.notices, &(&1 =~ "req_llm"))
    end
  end
end
