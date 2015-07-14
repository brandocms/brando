defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.1.0-dev"
  @description "Boilerplate for Twined applications. Experimental, do not use."

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.0",
      deps: deps,
      compilers: [:phoenix] ++ Mix.compilers,
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

  defp applications(:test), do: applications(:all) ++ [:blacksmith]
  defp applications(_all), do: [
    :comeonin, :httpoison, :phoenix, :phoenix_ecto, :phoenix_html,
    :earmark, :linguist, :mogrify, :poison, :postgrex, :scrivener,
    :slugger, :logger_file_backend
  ]

  defp deps do
    [
      {:phoenix, "~> 0.14"},
      {:phoenix_ecto, "~> 0.5"},
      {:phoenix_html, "~> 1.1"},

      {:comeonin, "~> 1.0"},
      {:earmark, "~> 0.1"},
      {:httpoison, "~> 0.6"},
      {:linguist, "~> 0.1"},
      {:mogrify, github: "twined/mogrify"},
      {:poison, "~> 1.3"},
      {:postgrex, ">= 0.0.0"},
      {:scrivener, "~> 0.8"},
      {:slugger, "~> 0.0.1"},
      {:logger_file_backend, ">= 0.0.0"},

      # Dev dependencies
      {:dialyze, "~> 0.1.3", only: :dev},

      # Test dependencies
      {:excoveralls, "~> 0.3", only: :test},
      {:blacksmith, "~> 0.1.2", only: :test},
      {:exvcr, "~> 0.4.0", only: :test},

      # Documentation dependencies
      {:ex_doc, "~> 0.6", only: :docs},
      {:inch_ex, "~> 0.3", only: :docs}
    ]
  end

  defp package do
    [contributors: ["Trond Mjøen"],
     licenses: ["MIT"],
     files: ["assets", "config", "lib", "priv", "test", "web",
             "mix.exs", "README.md", ".travis.yml", "CHANGELOG.md"],
     links: %{github: "https://github.com/twined/brando"}]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]
end
