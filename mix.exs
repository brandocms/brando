defmodule Brando.Mixfile do
  use Mix.Project

  @version "1.0.0-alpha.0"
  @description "A helping hand for Twined applications."

  def project do
    [app: :brando,
     version: @version,
     elixir: "~> 1.3",
     deps: deps(),
     dialyzer: [
       plt_add_apps: [
         :gettext,
         :comeonin,
         :guardian,
         :mogrify,
         :slugger,
         :phoenix,
         :phoenix_html,
         :phoenix_ecto
       ],
       flags: []
     ],
     compilers: [:gettext, :phoenix] ++ Mix.compilers,
     elixirc_paths: elixirc_paths(Mix.env),
     test_coverage: [tool: ExCoveralls],
     package: package(),
     description: @description,
     aliases: aliases(),

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
     :guardian,
     :mogrify,
     :poison,
     :scrivener,
     :scrivener_ecto,
     :slugger
    ]
  end

  defp deps do [
    {:comeonin, "~> 3.0"},
    {:earmark, "~> 1.0", override: true},
    {:gettext, "~> 0.11"},
    {:httpoison, "~> 0.9"},
    {:mogrify, "0.5.0"},

    {:phoenix, "~> 1.3.0-rc.0", override: true},
    {:phoenix_html, "~> 2.6"},
    {:phoenix_ecto, "~> 3.2"},
    {:postgrex, "~> 0.13", override: true},
    {:guardian, "~> 0.14"},

    {:slugger, "~> 0.1.0"},
    {:scrivener_ecto, "~> 1.1"},

    # Dev dependencies
    {:credo, ">= 0.0.0", only: :dev},
    {:dialyxir, "~> 0.3", only: :dev},

    # Test dependencies
    {:ex_machina, "~> 1.0", only: :test},
    {:excoveralls, "~> 0.6", only: :test},

    # Documentation dependencies
    {:ex_doc, "~> 0.11", only: :docs},
    {:inch_ex, "~> 0.5", only: :docs}]
  end

  defp package do
    [maintainers: ["Twined Networks"],
     licenses: [""],
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
