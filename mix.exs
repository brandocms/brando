defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.0",
      deps: deps,
      compilers: [:phoenix] ++ Mix.compilers,
      elixirc_paths: elixirc_paths(Mix.env),
      test_coverage: [tool: ExCoveralls],
      package: [
        contributors: ["Trond Mjøen"],
        licenses: ["MIT"],
        links: %{github: "https://github.com/twined/brando"}
      ],
      description: "Boilerplate for Twined applications.",
      # Docs
      name: "Brando",
      docs: [source_ref: "v#{@version}",
             source_url: "https://github.com/twined/brando"]
    ]
  end

  def application do
    [
      applications: [:phoenix, :postgrex, :ecto, :cowboy, :plug, :bcrypt]
    ]
  end

  defp deps do
    [
      {:postgrex, "~> 0.5"},
      {:ecto, "~> 0.10"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 0.11", override: true},
      {:earmark, "~> 0.1"},
      {:phoenix, "~> 0.11"},
      {:linguist, "~> 0.1"},
      {:mogrify, github: "twined/mogrify"},
      {:bcrypt, github: "opscode/erlang-bcrypt"},
      {:dialyze, "~> 0.1.3", only: :dev},
      {:excoveralls, "~> 0.3", only: :test},
      {:ex_doc, "~> 0.6", only: :docs},
      {:inch_ex, only: :docs}
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]
end
