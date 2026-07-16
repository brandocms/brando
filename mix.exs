defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.54.0-dev"
  @description "Brando CMS"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.15",
      deps: deps(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      description: @description,
      aliases: aliases(),

      # Docs
      name: "Brando",
      docs: [
        source_ref: "v#{@version}",
        source_url: "https://github.com/brandocms/brando",
        extras: ["guides/blueprint_migrations.md"]
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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

  defp package do
    [
      maintainers: ["Univers TM"],
      licenses: ["MIT"],
      files: [
        "assets",
        "config",
        "lib",
        "guides",
        "priv",
        "test",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "UPGRADE.md"
      ]
    ]
  end

  defp deps do
    [
      {:phoenix, "1.8.8"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_view, "~> 2.0", optional: true},
      {:postgrex, "~> 0.20"},
      {:ecto, "~> 3.13.0"},
      {:ecto_sql, "~> 3.13.0"},

      # liveview
      {:phoenix_live_view, "1.2.3"},
      {:phoenix_html, "~> 4.0"},

      # hashing/passwords
      {:bcrypt_elixir, "~> 3.0"},
      {:comeonin, "~> 5.0"},
      {:base62, "~> 1.2"},

      # dsl
      {:spark, "~> 2.4"},

      # monitoring
      {:sentry, "~> 13.0"},

      # cache
      {:cachex, "~> 4.0"},

      # cron & processing
      {:oban, "~> 2.23"},

      # sitemaps
      {:sitemapper, "~> 0.10.0"},

      # images
      {:image, "~> 0.64"},

      # AWS
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, "~> 0.6"},

      # Hashing
      {:hashids, "~> 2.0"},

      # Liquid templates
      {:liquex, "~> 0.15.0"},
      {:html_entities, "~> 0.5"},
      {:html_sanitize_ex, "~> 1.5.0"},

      # Misc
      {:req_llm, "~> 1.6"},
      {:req, "~> 0.5 or ~> 1.0"},
      {:gettext, "~> 1.0.0"},
      {:earmark, "~> 1.4.0"},
      {:jason, "~> 1.0"},
      {:slugify, "~> 1.3.1"},
      {:ecto_nested_changeset, "~> 1.0.0"},
      {:nimble_csv, "~> 1.2"},
      {:tz, "~> 0.28"},
      {:polymorphic_embed, "~> 5.0.1"},

      # tracing
      {:opentelemetry_api, "~> 1.4"},

      # Dev dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:igniter, "~> 0.8.0", only: [:dev, :test]},
      {:recompile_buster, "~> 0.1.0", only: [:dev, :test], runtime: false},

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.6", only: :test, runtime: false},
      {:floki, "~> 0.32", only: :test},

      # Documentation dependencies
      {:ex_doc, "~> 0.11", only: :docs, runtime: false},
      {:inch_ex, "~> 2.1.0-rc", only: :docs, runtime: false}
    ]
  end
end
