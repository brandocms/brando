defmodule <%= application_module %>.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :<%= application_name %>,
     version: @version,
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases(),
     deps: deps()]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {<%= application_module %>.Application, []},
     included_applications: [
       :recon,
     ],
     applications: [
       :brando,
       :brando_news,
       :brando_pages,
       :brando_villain,
       :cowboy,
       :hrafn,
       :gettext,
       :logger,
       :phoenix,
       :phoenix_ecto,
       :phoenix_html,
       :phoenix_pubsub,
       :plug_heartbeat,
       :postgrex,
       :runtime_tools,
       :timex
     ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
     # phoenix
     {:phoenix, path: "../..", override: true},
     {:phoenix_pubsub, "~> 1.0"},
     {:phoenix_ecto, "~> 3.1-rc.0"},
     {:phoenix_html, "~> 2.6"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},

     # general deps
     {:postgrex, ">= 0.0.0"},
     {:gettext, "~> 0.11"},
     {:cowboy, "~> 1.0"},
     {:timex, "~> 3.0"},

     # release management and production tools
     {:distillery, "~> 0.10"},
     {:recon, "~> 2.3"},
     {:hrafn, "~> 0.1"},
     {:plug_heartbeat, "~> 0.1"},

     # brando
     {:brando, github: "twined/brando", branch: "feature/phoenix1.3", override: true},
     {:brando_villain, "~> 0.1"},

     # optional brando modules
     {:brando_news, github: "twined/brando_news"},
     {:brando_pages, github: "twined/brando_pages"}]
  end

  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     "test": ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
