defmodule Mix.Tasks.Brando.Gen.Frontend do
  use Mix.Task

  @shortdoc "Generates a frontend template"

  @moduledoc """
  Generates a frontend template

      mix brando.gen.frontend

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando frontend tpl generator
    -------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      # Frontend assets
      {:keep, "assets/frontend/public/fonts", "assets/frontend/public/fonts"},
      {:keep, "assets/frontend/public/fonts", "assets/frontend/public/images"},
      {:copy, "assets/frontend/europa.config.js", "assets/frontend/europa.config.js"},
      {:copy, "assets/frontend/vite.config.js", "assets/frontend/vite.config.js"},
      {:copy, "assets/frontend/postcss.config.js", "assets/frontend/postcss.config.js"},
      {:copy, "assets/frontend/stylelint.config.js", "assets/frontend/stylelint.config.js"},
      {:copy, "assets/frontend/yarn.lock", "assets/frontend/yarn.lock"},
      {:eex, "assets/frontend/package.json", "assets/frontend/package.json"},

      # Frontend static
      {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/favicon.ico"},

      # Frontend src - CSS
      {:copy, "assets/frontend/css/app.css", "assets/frontend/css/app.css"},
      {:copy, "assets/frontend/css/critical.css", "assets/frontend/css/critical.css"},
      {:copy, "assets/frontend/css/includes/cookies.css",
       "assets/frontend/css/includes/cookies.css"},
      {:copy, "assets/frontend/css/includes/fonts.css", "assets/frontend/css/includes/fonts.css"},
      {:copy, "assets/frontend/css/includes/modules.css",
       "assets/frontend/css/includes/modules.css"},
      {:copy, "assets/frontend/css/includes/navigation.css",
       "assets/frontend/css/includes/navigation.css"},

      # Frontend JS

      {:keep, "assets/frontend/js/modules", "assets/frontend/js/modules"},
      {:copy, "assets/frontend/js/index.js", "assets/frontend/js/index.js"},
      {:copy, "assets/frontend/js/critical.js", "assets/frontend/js/critical.js"},
      {:copy, "assets/frontend/js/config/BREAKPOINTS.js",
       "assets/frontend/js/config/BREAKPOINTS.js"},
      {:copy, "assets/frontend/js/config/MOBILE_MENU.js",
       "assets/frontend/js/config/MOBILE_MENU.js"},
      {:copy, "assets/frontend/js/config/MOONWALK.js", "assets/frontend/js/config/MOONWALK.js"},
      {:copy, "assets/frontend/js/config/HEADER.js", "assets/frontend/js/config/HEADER.js"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.install", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end
