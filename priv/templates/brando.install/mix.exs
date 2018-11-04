defmodule <%= application_module %>.Mixfile do
  use Mix.Project

  @version "1.0.0"

  def project do
    [app: :<%= application_name %>,
     version: @version,
     elixir: "~> 1.6",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     start_permanent: Mix.env == :prod,
     aliases: aliases(),
     deps: deps()]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {<%= application_module %>.Application, []},
      extra_applications: [:logger, :runtime_tools, :recon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
     # phoenix
     {:phoenix, "~> 1.4.0-rc", override: true},
     {:phoenix_pubsub, "~> 1.1"},
     {:phoenix_ecto, "~> 4.0"},
     {:phoenix_html, "~> 2.12"},
     {:phoenix_live_reload, "~> 1.2-rc", only: :dev},
     {:plug_cowboy, "~> 1.0"},
     {:ecto, "~> 3.0", override: true},
     {:ecto_sql, "~> 3.0-rc", override: true},

     # general deps
     {:postgrex, "~> 0.14.0"},
     {:gettext, "~> 0.11"},

     {:timex, "~> 3.0"},
     {:jason, "~> 1.0"},
     {:absinthe, "~> 1.4"},
     {:absinthe_plug, "~> 1.4"},
     {:absinthe_ecto, "~> 0.1"},

     # release management and production tools
     {:distillery, "~> 2.0"},
     {:recon, "~> 2.3"},
     {:hrafn, "~> 0.1"},
     {:plug_heartbeat, "~> 0.1"},

     # testing
     {:wallaby, "~> 0.19", only: :test},

     # brando
     # {:brando, github: "twined/brando", branch: "develop"}
     {:brando, path: "../../brando", override: true},
    ]
  end

  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     test: ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
