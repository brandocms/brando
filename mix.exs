defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.13.0-dev"
  @description "Boilerplate for Twined applications."

  def project do
    [
      app: :brando,
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
             source_url: "https://github.com/twined/brando"]
    ]
  end

  def application do
    [applications: applications(Mix.env)]
  end

  defp applications(:test), do: applications(:all) ++ [:blacksmith, :ecto]
  defp applications(_all), do: [
    :gettext, :comeonin, :httpoison, :earmark, :mogrify, :poison, :scrivener,
    :slugger, :eightyfour
  ]

  defp deps do
    [
      {:comeonin, "~> 1.5"},
      {:earmark, "~> 0.1"},
      {:eightyfour, github: "twined/eightyfour"},
      {:gettext, "~> 0.7.0"},
      {:httpoison, "~> 0.8"},
      {:mogrify, github: "twined/mogrify"},
      {:phoenix, "~> 1.1"},
      {:phoenix_html, "~> 2.3"},
      {:poison, "~> 1.3"},
      {:postgrex, "~> 0.10"},
      {:scrivener, "~> 1.1"},
      {:slugger, "~> 0.0.1"},

      # Dev dependencies
      {:dialyze, "~> 0.2", only: :dev},
      {:credo, "~> 0.1.6", only: [:dev, :test]},

      # Test dependencies
      {:phoenix_ecto, "~> 2.0", only: :test},
      {:blacksmith, "~> 0.1.2", only: :test},
      {:excoveralls, "~> 0.4", only: :test},

      # Documentation dependencies
      {:ex_doc, "~> 0.9", only: :docs},
      {:inch_ex, "~> 0.3", only: :docs},
    ]
  end

  defp package do
    [maintainers: ["Trond Mjøen"],
     licenses: [""],
     files: ["assets", "config", "lib", "priv", "test", "web",
             "mix.exs", "README.md", ".travis.yml", "CHANGELOG.md"],
     links: %{github: "https://github.com/twined/brando"}]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]
end
