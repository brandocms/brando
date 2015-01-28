defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.0",
      deps: deps,
      test_coverage: [tool: ExCoveralls],
      package: [
        contributors: ["Trond Mjøen"],
        licenses: ["MIT"],
        links: %{github: "https://github.com/twined/brando"}
      ],
      description: """
      Boilerplate for Twined applications.
      """,

      # Docs
      name: "Brando",
      docs: [source_ref: "v#{@version}",
             source_url: "https://github.com/twined/brando"]
    ]
  end

  def application do
    [
      applications: [:postgrex, :ecto, :cowboy, :plug, :bcrypt]
    ]
  end

  defp deps do
    [
      {:postgrex, "~> 0.5"},
      {:ecto, "~> 0.7"},
      {:cowboy, "~> 1.0"},
      #{:plug, "~> 0.9"},
      {:plug, github: "elixir-lang/plug", override: true},
      {:phoenix, "~> 0.8.0"},
      {:mogrify, github: "twined/mogrify"},
      {:bcrypt, github: "opscode/erlang-bcrypt"},
      {:excoveralls, "~> 0.3", only: :test},
      {:ex_doc, "~> 0.6", only: :docs},
      {:earmark, "~> 0.1", only: :docs},
      {:inch_ex, only: :docs}
    ]
  end
end
