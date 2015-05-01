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
    [applications: [:comeonin]]
  end

  defp deps do
    [
      {:postgrex, ">= 0.0.0"},
      {:phoenix_ecto, "~> 0.3"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 0.11"},
      {:earmark, "~> 0.1"},
      {:phoenix, "~> 0.12"},
      {:linguist, "~> 0.1"},
      {:slugger, "~> 0.0.1"},
      {:poolboy, "~> 1.5.1", override: true},
      {:mogrify, github: "twined/mogrify"},
      {:comeonin, "~> 0.8"},
      {:dialyze, "~> 0.1.3", only: :dev},
      {:excoveralls, "~> 0.3", only: :test},
      {:ex_doc, "~> 0.6", only: :docs},
      {:inch_ex, only: :docs}
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
