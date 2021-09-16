defmodule Brando.Mixfile do
  use Mix.Project

  @version "0.52.0-dev"
  @description "Brando CMS"

  def project do
    [
      app: :brando,
      version: @version,
      elixir: "~> 1.10",
      deps: deps(),
      package: package(),
      compilers: [:gettext] ++ Mix.compilers(),
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
      {:phoenix, "~> 1.6.0-rc.0", override: true},
      {:phoenix_ecto, "~> 4.0"},
      {:postgrex, "~> 0.14"},
      {:ecto, "~> 3.7"},
      {:ecto_sql, "~> 3.7"},

      # liveview
      {:phoenix_live_view, "~> 0.16"},
      {:phoenix_html, "~> 3.0", override: true},
      {:surface, "~> 0.5"},
      {:surface_formatter, "~> 0.5.4"},
      {:floki, ">= 0.27.0", only: :test},

      # hashing/passwords
      {:bcrypt_elixir, "~> 2.0"},
      {:comeonin, "~> 5.0"},
      {:base62, "~> 1.2"},

      # tokens/auth
      {:guardian, "~> 2.0"},
      {:guardian_phoenix, "~> 2.0"},

      # monitoring
      {:sentry, "~> 8.0"},

      # cache
      {:cachex, "~> 3.2"},

      # cron
      {:oban, "~> 2.4"},

      # sitemaps
      {:sitemapper, "~> 0.5"},

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
      {:liquex, "~> 0.5"},

      # Misc
      # {:brotli, "~> 0.2"},
      {:polymorphic_embed, "~> 1.6"},
      {:httpoison, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:timex, "~> 3.0"},
      {:earmark, "1.4.4"},
      {:jason, "~> 1.0"},
      {:poison, "~> 4.0"},
      {:flow, "~> 1.0"},
      {:slugger, "~> 0.2"},
      {:recase, "~> 0.2"},
      {:inflex, "~> 2.0"},

      # Dev dependencies
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.6", only: :test, runtime: false},

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
