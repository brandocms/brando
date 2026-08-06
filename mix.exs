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
      description: @description,
      aliases: aliases(),

      # Docs
      name: "Brando",
      docs: [
        source_ref: "v#{@version}",
        source_url: "https://github.com/brandocms/brando",
        extras: [
          "guides/migrating_to_054.md",
          "guides/blueprints.md",
          "guides/blueprint_migrations.md"
        ],
        groups_for_extras: [
          Upgrading: [
            "guides/migrating_to_054.md"
          ],
          "Blueprint system": [
            "guides/blueprints.md",
            "guides/blueprint_migrations.md"
          ]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
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
      # Required by Hex: without it `mix hex.build` stops with "Missing metadata
      # fields: links" and the package cannot be published. Same URL the docs
      # config already uses.
      links: %{"GitHub" => "https://github.com/brandocms/brando"},
      # `config` and `test` are deliberately absent, and nothing in a consuming
      # application can reach them: Mix compiles dependencies in `:prod`, so
      # `elixirc_paths(:test)` never fires for a dep and `test/support` is never
      # compiled (verified against the e2e project's `MIX_ENV=test` build — no
      # `Elixir.Brando.ConnCase.beam`), and Elixir has not loaded dependency
      # config files for many versions. Excluding them also keeps the test
      # fixtures out of the tarball.
      #
      # Not claimed here: that shipping placeholder credentials is itself the
      # risk. `priv/` still ships several on purpose — `brando.install`'s
      # `deployment.cfg`, `fabfile.py`, `.envrc.prod` — because a scaffold has
      # to hand the operator something to fill in.
      # `assets/` is absent on purpose. The admin frontend reaches consuming
      # applications through Yalc (`@brandocms/brandojs`), never through this
      # tarball, and the generator templates a consumer does need live under
      # `priv/templates/`, not here.
      #
      # Naming the directory was also actively harmful: Hex globs the
      # filesystem and does not read `.gitignore`, so `"assets"` swept in
      # `assets/node_modules/` — gitignored, 120 MB, and 10_976 of the 11_194
      # `assets/` entries it produced.
      files: [
        "lib",
        "guides",
        "priv",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "UPGRADE.md"
      ]
    ]
  end

  defp deps do
    [
      {:phoenix, "1.8.9"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_view, "~> 2.0", optional: true},
      {:postgrex, "~> 0.20"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},

      # liveview
      {:phoenix_live_view, "1.2.8"},
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

      # Test dependencies
      {:ex_machina, "~> 2.0", only: :test, runtime: false},
      {:excoveralls, "~> 0.6", only: :test, runtime: false},
      {:floki, "~> 0.32", only: :test},
      # Required by Phoenix.LiveViewTest — see `Brando.LiveCase`
      {:lazy_html, ">= 0.1.0", only: :test},
      # Mocks the S3 seam — see `Brando.CDN.Client`
      {:mox, "~> 1.2", only: :test},

      # Documentation dependencies
      {:ex_doc, "~> 0.11", only: :docs, runtime: false},
      {:inch_ex, "~> 2.1.0-rc", only: :docs, runtime: false}
    ]
  end
end
