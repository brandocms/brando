defmodule <%= application_module %>.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :<%= application_name %>,
     version: @version,
     elixir: "~> 1.4",
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
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
     # phoenix
     {:phoenix, "~> 1.3.0-rc.0", override: true},
     {:phoenix_pubsub, "~> 1.0"},
     {:phoenix_ecto, "~> 3.2"},
     {:phoenix_html, "~> 2.6"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},

     # general deps
     {:postgrex, ">= 0.0.0"},
     {:gettext, "~> 0.11"},
     {:cowboy, "~> 1.0"},
     {:timex, "~> 3.0"},

     # release management and production tools
     {:distillery, "~> 1.0"},
     {:recon, "~> 2.3"},
     {:hrafn, "~> 0.1"},
     {:plug_heartbeat, "~> 0.1"},

     # brando
     {:brando, github: "twined/brando", branch: "develop", override: true},

     # optional brando modules
     {:brando_news, github: "twined/brando_news", branch: "develop"},
     {:brando_pages, github: "twined/brando_pages", branch: "develop"}]
  end

  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     "test": ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
