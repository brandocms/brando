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
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      # Frontend assets
      {:keep, "assets/frontend/fonts", "assets/frontend/public/fonts"},
      {:keep, "assets/frontend/fonts", "assets/frontend/public/images"},
      {:copy, "assets/frontend/europa.config.js", "assets/frontend/europa.config.js"},
      {:copy, "assets/frontend/vite.config.js", "assets/frontend/vite.config.js"},
      {:copy, "assets/frontend/postcss.config.js", "assets/frontend/postcss.config.js"},
      {:copy, "assets/frontend/stylelint.config.js", "assets/frontend/stylelint.config.js"},
      {:copy, "assets/frontend/yarn.lock", "assets/frontend/yarn.lock"},
      {:eex, "assets/frontend/package.json", "assets/frontend/package.json"},

      # Frontend static
      {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/favicon.ico"},

      # Frontend CYPRESS
      {:copy, "assets/frontend/cypress.json", "assets/frontend/cypress.json"},
      {:copy, "assets/frontend/cypress/fixtures/example.json",
       "assets/frontend/cypress/fixtures/example.json"},
      {:copy, "assets/frontend/cypress/integration/example.js",
       "assets/frontend/cypress/integration/example.js"},
      {:copy, "assets/frontend/cypress/plugins/index.js",
       "assets/frontend/cypress/plugins/index.js"},
      {:copy, "assets/frontend/cypress/support/commands.js",
       "assets/frontend/cypress/support/commands.js"},
      {:copy, "assets/frontend/cypress/support/index.js",
       "assets/frontend/cypress/support/index.js"},

      # Frontend src - CSS
      {:copy, "assets/frontend/css/app.css", "assets/frontend/css/app.css"},
      {:copy, "assets/frontend/css/includes/animations.css",
       "assets/frontend/css/includes/animations.css"},
      {:copy, "assets/frontend/css/includes/arrows.css",
       "assets/frontend/css/includes/arrows.css"},
      {:copy, "assets/frontend/css/includes/containers.css",
       "assets/frontend/css/includes/containers.css"},
      {:copy, "assets/frontend/css/includes/content.css",
       "assets/frontend/css/includes/content.css"},
      {:copy, "assets/frontend/css/includes/cookies.css",
       "assets/frontend/css/includes/cookies.css"},
      {:copy, "assets/frontend/css/includes/fader.css", "assets/frontend/css/includes/fader.css"},
      {:copy, "assets/frontend/css/includes/fonts.css", "assets/frontend/css/includes/fonts.css"},
      {:copy, "assets/frontend/css/includes/footer.css",
       "assets/frontend/css/includes/footer.css"},
      {:copy, "assets/frontend/css/includes/general.css",
       "assets/frontend/css/includes/general.css"},
      {:copy, "assets/frontend/css/includes/header.css",
       "assets/frontend/css/includes/header.css"},
      {:copy, "assets/frontend/css/includes/headers.css",
       "assets/frontend/css/includes/headers.css"},
      {:copy, "assets/frontend/css/includes/lazyload.css",
       "assets/frontend/css/includes/lazyload.css"},
      {:copy, "assets/frontend/css/includes/lightbox.css",
       "assets/frontend/css/includes/lightbox.css"},
      {:copy, "assets/frontend/css/includes/modules.css",
       "assets/frontend/css/includes/modules.css"},
      {:copy, "assets/frontend/css/includes/navigation-nojs.css",
       "assets/frontend/css/includes/navigation-nojs.css"},
      {:copy, "assets/frontend/css/includes/navigation.css",
       "assets/frontend/css/includes/navigation.css"},
      {:copy, "assets/frontend/css/includes/newsletter.css",
       "assets/frontend/css/includes/newsletter.css"},
      {:copy, "assets/frontend/css/includes/panners.css",
       "assets/frontend/css/includes/panners.css"},
      {:copy, "assets/frontend/css/includes/paragraphs.css",
       "assets/frontend/css/includes/paragraphs.css"},
      {:copy, "assets/frontend/css/includes/partials.css",
       "assets/frontend/css/includes/partials.css"},
      {:copy, "assets/frontend/css/includes/popup.css", "assets/frontend/css/includes/popup.css"},
      {:copy, "assets/frontend/css/includes/slider.css",
       "assets/frontend/css/includes/slider.css"},

      # Frontend JS

      {:keep, "assets/frontend/js/modules", "assets/frontend/js/modules"},
      {:copy, "assets/frontend/js/index.js", "assets/frontend/js/index.js"},
      {:copy, "assets/frontend/js/critical.js", "assets/frontend/js/critical.js"},
      {:copy, "assets/frontend/js/config/BREAKPOINTS.js",
       "assets/frontend/js/config/BREAKPOINTS.js"},
      {:copy, "assets/frontend/js/config/HERO_VIDEO.js",
       "assets/frontend/js/config/HERO_VIDEO.js"},
      {:copy, "assets/frontend/js/config/LIGHTBOX.js", "assets/frontend/js/config/LIGHTBOX.js"},
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
