defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.24.0"
  @description "Boilerplate for Twined applications."

  def project do
    [app: :brando,
     version: @version,
     elixir: "~> 1.0",
     deps: deps,
     compilers: [:gettext, :phoenix] ++ Mix.compilers,
     elixirc_paths: elixirc_paths(Mix.env),
     test_coverage: [tool: ExCoveralls],
     package: package,
     description: @description,

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
  defp applications(_all) do
    [:gettext, :comeonin, :httpoison, :earmark, :mogrify,
     :poison, :scrivener, :slugger, :eightyfour]
  end

  defp deps do
    [{:comeonin, "~> 2.1"},
     {:earmark, "~> 0.2"},
     {:eightyfour, github: "twined/eightyfour"},
     {:gettext, "~> 0.10"},
     {:httpoison, "~> 0.8"},
     {:mogrify, github: "twined/mogrify"},
     {:phoenix, "~> 1.1"},
     {:phoenix_html, "~> 2.4"},
     {:poison, "~> 1.3"},
     {:postgrex, "~> 0.11"},
     {:scrivener, "~> 1.1"},
     {:slugger, "~> 0.1.0"},

     # Dev dependencies
     {:credo, "~> 0.2", only: :dev},
     {:dialyze, "~> 0.2", only: :dev},

     # Test dependencies
     {:phoenix_ecto, "~> 3.0.0-beta", only: :test},
     {:ex_machina, "~> 0.6.1", only: :test},
     {:excoveralls, "~> 0.5.1", only: :test},

     # Temporary until scrivener updates
     {:ecto, "~> 2.0-beta", override: true},

     # Documentation dependencies
     {:ex_doc, "~> 0.11", only: :docs},
     {:inch_ex, "~> 0.5", only: :docs}]
  end

  defp package do
    [maintainers: ["Twined Networks"],
     licenses: ["MIT"],
     files: ["config", "lib", "priv", "test", "web", "mix.exs", "README.md",
             "CHANGELOG.md", ".eslintrc", ".travis.yml", "brunch-config.js", "package.json"],
     links: %{github: "https://github.com/twined/brando"}]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]
end
