defmodule <%= application_module %>.MixProject do
  use Mix.Project

  @version "1.0.0"
  @test_envs [:test, :e2e]

  def project do
    [
      app: :<%= application_name %>,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      test_paths: test_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      releases: [
        <%= application_name %>: [
          include_executables_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {<%= application_module %>.Application, []},
      extra_applications: [:logger, :runtime_tools, :recon, :sasl, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in @test_envs, do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specify test path per environment
  defp test_paths(:e2e), do: ["test/e2e"]
  defp test_paths(_), do: ["test/unit"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # phoenix
      {:phoenix, "~> 1.7.0", override: true},
      {:ecto, github: "elixir-ecto/ecto", override: true},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug_cowboy, "~> 2.1"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:ecto_sql, "~> 3.6"},
      {:telemetry, "~> 1.0", override: true},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      # {:exsync, "~> 0.2", only: :dev},

      # live view
      {:phoenix_live_view, "~> 0.18"},
      {:floki, ">= 0.27.0", only: :test},

      # general deps
      {:postgrex, "~> 0.15"},
      {:gettext, "~> 0.11"},
      {:swoosh, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:ex_machina, "~> 2.3"},
      {:remote_ip, "~> 1.0"},

      # release management and production tools
      {:recon, "~> 2.3"},
      {:plug_heartbeat, "~> 1.0"},

      # brando
      {:brando, github: "brandocms/brando"}
      # {:brando, path: "../../brando"}
    ]
  end

  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup", "run priv/repo/seeds.exs"],
      "test.all": ["test.unit", "test.e2e"],
      "test.unit": &run_unit_tests/1,
      "test.e2e": &run_e2e_tests/1,
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  def run_e2e_tests(args), do: test_with_env("e2e", args)
  def run_unit_tests(args), do: test_with_env("test", args)

  def test_with_env(env, args) do
    args = if IO.ANSI.enabled?(), do: ["--color" | args], else: ["--no-color" | args]
    IO.puts("==> Running tests with `MIX_ENV=#{env}`")

    {_, res} =
      System.cmd("mix", ["test" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end
end
