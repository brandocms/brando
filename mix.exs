defmodule Brando.Mixfile do
  use Mix.Project

  @version "2.0.0-alpha.1-dev"
  @description "A helping hand for Twined applications."

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.6",
      deps: deps(),
      compilers: [:gettext, :phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      package: package(),
      description: @description,
      aliases: aliases(),

      # Docs
      name: "Brando",
      docs: [source_ref: "v#{@version}", source_url: "https://github.com/twined/brando"]
    ]
  end

  def application do
    [mod: {Brando, []}, applications: applications(Mix.env())]
  end

  defp applications(:test) do
    applications(:all) ++
      [
        :ecto,
        :postgrex,
        :absinthe,
        :absinthe_ecto,
        :absinthe_plug
      ]
  end

  defp applications(_all) do
    [
      :flow,
      :absinthe,
      :gettext,
      :comeonin,
      :httpoison,
      :earmark,
      :guardian,
      :mogrify,
      :phoenix_html,
      :poison,
      :recase,
      :sentry,
      :slugger,
      :timex
    ]
  end

  defp deps do
    [
      {:bcrypt_elixir, "~> 2.0"},
      {:comeonin, "~> 5.0"},
      {:earmark, "~> 1.2"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.0"},
      {:mogrify, "~> 0.5"},
      {:phoenix, "~> 1.4.0"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_ecto, "~> 4.0"},
      {:postgrex, "~> 0.14"},
      {:slugger, "~> 0.2"},
      {:recase, "~> 0.2"},
      {:guardian, "~> 1.0"},
      {:timex, "~> 3.0"},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:flow, "~> 0.14"},
      {:jason, "~> 1.0"},
      {:poison, "~> 4.0"},

      # monitoring
      {:sentry, "~> 7.0"},

      # Dev dependencies
      {:credo, ">= 0.0.0", only: :dev},
      {:dialyxir, "~> 0.3", only: :dev},
      {:mix_test_watch, "~> 0.8", only: :dev, runtime: false},

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test},
      {:excoveralls, "~> 0.6", only: :test},
      {:absinthe, "~> 1.4"},
      {:absinthe_plug, "~> 1.4"},
      {:absinthe_ecto, "~> 0.1.0"},

      # Documentation dependencies
      {:ex_doc, "~> 0.11", only: :docs},
      {:inch_ex, "~> 2.0", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Univers/Twined"],
      licenses: [""],
      files: [
        "assets",
        "config",
        "lib",
        "priv",
        "test",
        "mix.exs",
        "README.md",
        "CHANGELOG.md"
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_), do: ["lib", "web"]

  # Aliases are shortcut or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
