defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.10.0-dev"
  @description "Boilerplate for Twined applications. Experimental, do not use."

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
      {:comeonin, "~> 1.0"},
      {:earmark, "~> 0.1"},
      {:eightyfour, github: "twined/eightyfour"},
      {:gettext, github: "tmjoen/gettext"},
      {:httpoison, "~> 0.6"},
      {:mogrify, github: "twined/mogrify"},
      {:poison, "~> 1.3"},
      {:scrivener, "~> 1.0"},
      {:slugger, "~> 0.0.1"},

      # Dev dependencies
      {:dialyze, "~> 0.2", only: :dev},
      {:dogma, github: "lpil/dogma", only: :dev},

      # Test dependencies
      {:phoenix, "~> 1.0", only: :test},
      {:phoenix_ecto, "~> 1.1", only: :test},
      {:phoenix_html, "~> 2.1", only: :test},
      {:postgrex, ">= 0.0.0", only: :test},

      {:blacksmith, "~> 0.1.2", only: :test},
      {:excoveralls, "~> 0.3", only: :test},
      {:exvcr, "~> 0.5.0", only: :test},

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
