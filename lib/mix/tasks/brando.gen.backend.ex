defmodule Mix.Tasks.Brando.Gen.Backend do
  use Mix.Task

  @shortdoc "Generates a backend template"

  @moduledoc """
  Generates a backend template

      mix brando.gen.backend

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando backend tpl generator
    -------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      # Backend tooling
      {:copy, "assets/backend/europa.config.js", "assets/backend/europa.config.js"},
      {:copy, "assets/backend/package.json", "assets/backend/package.json"},
      {:copy, "assets/backend/postcss.config.js", "assets/backend/postcss.config.js"},
      {:copy, "assets/backend/README.md", "assets/backend/README.md"},
      {:copy, "assets/backend/svelte.config.cjs", "assets/backend/svelte.config.cjs"},
      {:copy, "assets/backend/vite.config.js", "assets/backend/vite.config.js"},

      # Backend resources
      {:copy, "assets/backend/public/favicon.ico", "assets/backend/public/favicon.ico"},
      {:copy, "assets/backend/public/fonts/Mono.woff2", "assets/backend/public/fonts/Mono.woff2"},
      {:copy, "assets/backend/public/images/admin/avatar.svg",
       "assets/backend/public/images/admin/avatar.svg"},

      # Backend src
      {:copy, "assets/backend/src/main.js", "assets/backend/src/main.js"},
      {:copy, "assets/backend/src/auth.js", "assets/backend/src/auth.js"},
      {:copy, "assets/backend/src/hooks/index.js", "assets/backend/src/hooks/index.js"},
      {:copy, "assets/backend/css/app.css", "assets/backend/css/app.css"},
      {:copy, "assets/backend/css/blocks.css", "assets/backend/css/blocks.css"},
      {:copy, "assets/backend/css/fonts.css", "assets/backend/css/fonts.css"}

      # {:copy, "assets/backend/src/styles/blocks.pcss", "assets/backend/src/styles/blocks.pcss"},
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.install", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end
