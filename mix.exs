defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.33.0-dev"
  @description "Boilerplate for Twined applications."

  def project do
    [app: :brando,
     version: @version,
     elixir: "~> 1.0",
     deps: deps,
     dialyzer: [
       plt_add_apps: [
         :gettext, :comeonin, :mogrify, :slugger, :phoenix, :ecto, :phoenix_html
       ],
       flags: []
     ],
     compilers: [:gettext, :phoenix] ++ Mix.compilers,
     elixirc_paths: elixirc_paths(Mix.env),
     test_coverage: [tool: ExCoveralls],
     package: package,
     description: @description,
     aliases: aliases,

     # Docs
     name: "Brando",
     docs: [source_ref: "v#{@version}",
            source_url: "https://github.com/twined/brando"]]
  end

  def application do
    [mod: {Brando, []},
     applications: applications(Mix.env)]
  end

  defp applications(:test), do: applications(:all) ++ [:ecto, :postgrex]
  defp applications(_all) do [
     :gettext,
     :comeonin,
     :httpoison,
     :earmark,
     :mogrify,
     :poison,
     :scrivener,
     :slugger
    ]
  end

  defp deps do [
    {:comeonin, "~> 2.5"},
    {:earmark, "~> 0.2"},
    {:gettext, "~> 0.11"},
    {:httpoison, "~> 0.8"},
    {:mogrify, github: "twined/mogrify"},
    {:phoenix, "~> 1.1"},
    {:phoenix_html, "~> 2.5"},
    {:poison, "~> 2.0"},
    {:postgrex, "~> 0.11"},
    {:scrivener, "~> 2.0"},
    {:slugger, "~> 0.1.0"},

    # Dev dependencies
    {:credo, ">= 0.0.0", only: :dev},
    {:dialyxir, "~> 0.3", only: :dev},

    # Test dependencies
    {:phoenix_ecto, "~> 3.0.0", only: :test},
    {:ex_machina, "~> 1.0", only: :test},
    {:excoveralls, "~> 0.5.1", only: :test},

    # Documentation dependencies
    {:ex_doc, "~> 0.11", only: :docs},
    {:inch_ex, "~> 0.5", only: :docs}]
  end

  defp package do
    [maintainers: ["Twined Networks"],
     licenses: ["MIT"],
     files: [
       "config",
       "lib",
       "priv",
       "test",
       "web",
       "mix.exs",
       "README.md",
       "CHANGELOG.md",
       "brunch-config.js",
       "package.json"
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Aliases are shortcut or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"]]
  end
end
