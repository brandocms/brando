defmodule <%= application_module %>.Mixfile do
  use Mix.Project

  @version "0.0.1"

  def project do
    [app: :<%= application_name %>,
     version: @version,
     elixir: "~> 1.2",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {<%= application_module %>, []},
     included_applications: [:brando_news, :brando_pages, :brando_villain],
     applications: [:brando, :phoenix, :phoenix_html, :cowboy, :logger, :gettext,
                    :phoenix_ecto, :postgrex]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [{:phoenix, "~> 1.1"},
     {:phoenix_ecto, "~> 3.0.0"},
     {:postgrex, ">= 0.0.0"},
     {:phoenix_html, "~> 2.4"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:gettext, "~> 0.10"},
     {:cowboy, "~> 1.0"},

     # release management
     {:exrm, "~> 1.0"},

     # brando
     {:brando, github: "twined/brando"},
     {:brando_villain, github: "twined/brando_villain"},

     # optional brando modules
     {:brando_news, github: "twined/brando_news"},
     {:brando_pages, github: "twined/brando_pages"}]
  end

  # Aliases are shortcut or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"]]
  end
end
