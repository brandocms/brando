defmodule Brando.Mixfile do
  use Mix.Project

  def project do
    [
      app: :brando,
      version: "0.0.1",
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
      """
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
      {:ecto, "~> 0.6"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 0.9"},
      {:phoenix, "~> 0.8.0"},
      {:bcrypt, github: "opscode/erlang-bcrypt"},
      {:excoveralls, "~> 0.3", only: :test}
    ]
  end
end
