defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.46.0-dev"
  @description "Brando CMS"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.10",
      deps: deps(),
      compilers: [:gettext, :phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      package: package(),
      description: @description,
      aliases: aliases(),

      # Docs
      name: "Brando",
      docs: [
        source_ref: "v#{@version}",
        source_url: "https://github.com/brandocms/brando"
      ]
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
        :dataloader,
        :absinthe_plug
      ]
  end

  defp applications(_all) do
    [
      :cachex,
      :flow,
      :absinthe,
      :dataloader,
      :gettext,
      :comeonin,
      :hashids,
      :httpoison,
      :inflex,
      :earmark,
      :fastimage,
      :guardian,
      :guardian_phoenix,
      :mogrify,
      :nimble_parsec,
      :phoenix_html,
      :poison,
      :recase,
      :sentry,
      :slugger,
      :timex,
      :ex_aws,
      :hackney,
      :sweet_xml
    ]
  end

  defp deps do
    [
      {:bcrypt_elixir, "~> 2.0"},
      {:comeonin, "~> 5.0"},
      {:earmark, "1.4.4"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.0"},
      {:phoenix, "~> 1.4"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_ecto, "~> 4.0"},
      {:postgrex, "~> 0.14"},
      {:slugger, "~> 0.2"},
      {:recase, "~> 0.2"},
      {:guardian, "~> 2.0"},
      {:guardian_phoenix, "~> 2.0"},
      {:timex, "~> 3.0"},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:flow, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:poison, "~> 4.0"},
      {:inflex, "~> 2.0"},

      # graphql
      {:absinthe, "~> 1.5.0"},
      {:absinthe_plug, "~> 1.5.0"},
      {:dataloader, "~> 1.0"},

      # monitoring
      {:sentry, "~> 7.0"},
      {:mogrify, "~> 0.5"},

      # cache
      {:cachex, "~> 3.2"},

      # images
      {:fastimage, "~> 1.0.0-rc4"},

      # AWS
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},

      # Hashing
      {:hashids, "~> 2.0"},

      # Parser
      {:nimble_parsec, "~> 0.6", override: true},
      {:html_entities, "~> 0.5"},
      {:html_sanitize_ex, "~> 1.4"},

      # Dev dependencies
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.6", only: :test, runtime: false},

      # Documentation dependencies
      {:ex_doc, "~> 0.11", only: :docs, runtime: false},
      {:inch_ex, "~> 2.0", only: :docs, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Univers TM"],
      licenses: ["MIT"],
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
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.seed": ["run priv/repo/seeds.exs"]
    ]
  end
end
