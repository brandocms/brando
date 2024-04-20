defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.53.0"
  @description "Brando CMS"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.14",
      deps: deps(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
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

  defp deps do
    [
      {:phoenix, "~> 1.7.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_view, "~> 2.0", optional: true},
      {:postgrex, "~> 0.17"},
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},

      # liveview
      {:phoenix_live_view, "0.20.14"},
      {:phoenix_html, "~> 4.0"},

      # hashing/passwords
      {:bcrypt_elixir, "~> 3.0"},
      {:comeonin, "~> 5.0"},
      {:base62, "~> 1.2"},

      # monitoring
      {:sentry, "~> 10.0"},

      # cache
      {:cachex, "~> 3.5"},

      # cron
      {:oban, "~> 2.17.0"},

      # sitemaps
      {:sitemapper, "~> 0.8"},

      # images
      {:fastimage, "~> 1.0.0-rc4"},

      # AWS
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},

      # Hashing
      {:hashids, "~> 2.0"},

      # Liquid templates
      {:liquex, "~> 0.11"},
      {:html_sanitize_ex, "~> 1.4", override: true},

      # Misc
      {:req, "~> 0.4.5"},
      {:gettext, "~> 0.20"},
      {:earmark, "~> 1.4.0"},
      {:jason, "~> 1.0"},
      {:slugger, "~> 0.2"},
      {:recase, "~> 0.2"},
      {:ecto_nested_changeset, "~> 0.2"},
      {:nimble_csv, "~> 1.2"},
      {:tzdata, "~> 1.1"},
      {:polymorphic_embed, github: "SteffenDE/polymorphic_embed"},

      # Dev dependencies
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.6", only: :test, runtime: false},
      {:floki, "~> 0.32", only: :test},

      # Documentation dependencies
      {:ex_doc, "~> 0.11", only: :docs, runtime: false},
      {:inch_ex, "~> 2.1.0-rc", only: :docs, runtime: false}
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
        "CHANGELOG.md",
        "UPGRADE.md"
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
