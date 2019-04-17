defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  import Mix.Generator

  @moduledoc """
  Install Brando.
  """

  @shortdoc "Generates files for Brando."

  @new [
    # Mix template
    {:eex, "mix.exs", "mix.exs"},

    # Formatter
    {:eex, "formatter.exs", ".formatter.exs"},

    # Release migrator
    {:eex, "rel/commands/migrate.sh", "rel/commands/migrate.sh"},
    {:eex, "lib/application_name/release_tasks.ex", "lib/application_name/release_tasks.ex"},

    # Etc. Various OS config files and log directory.
    {:keep, "log", "log"},
    {:eex, "etc/logrotate/prod.conf", "etc/logrotate/prod.conf"},
    {:eex, "etc/nginx/prod.conf", "etc/nginx/prod.conf"},
    {:eex, "etc/nginx/staging.conf", "etc/nginx/staging.conf"},
    {:eex, "etc/nginx/502.html", "etc/nginx/502.html"},
    {:eex, "etc/supervisord/prod.conf", "etc/supervisord/prod.conf"},
    {:eex, "etc/supervisord/staging.conf", "etc/supervisord/staging.conf"},

    # Tuple implementation for Poison
    {:eex, "lib/application_name/tuple.ex", "lib/application_name/tuple.ex"},

    # Presence
    {:eex, "lib/application_name/presence.ex", "lib/application_name/presence.ex"},

    # Router template
    {:eex, "lib/application_name_web/router.ex", "lib/application_name_web/router.ex"},

    # Lockdown files
    {:eex, "lib/application_name_web/controllers/lockdown_controller.ex",
     "lib/application_name_web/controllers/lockdown_controller.ex"},
    {:eex, "lib/application_name_web/templates/layout/lockdown.html.eex",
     "lib/application_name_web/templates/layout/lockdown.html.eex"},
    {:eex, "lib/application_name_web/templates/lockdown/index.html.eex",
     "lib/application_name_web/templates/lockdown/index.html.eex"},
    {:eex, "lib/application_name_web/views/lockdown_view.ex",
     "lib/application_name_web/views/lockdown_view.ex"},

    # Page files
    {:eex, "lib/application_name_web/controllers/page_controller.ex",
     "lib/application_name_web/controllers/page_controller.ex"},
    {:eex, "lib/application_name_web/templates/page/cookies.html.eex",
     "lib/application_name_web/templates/page/cookies.html.eex"},

    # Fallback and errors
    {:eex, "lib/application_name_web/controllers/fallback_controller.ex",
     "lib/application_name_web/controllers/fallback_controller.ex"},
    {:eex, "lib/application_name_web/views/error_view.ex",
     "lib/application_name_web/views/error_view.ex"},
    {:eex, "lib/application_name_web/templates/error/404_page.html.eex",
     "lib/application_name_web/templates/error/404_page.html.eex"},
    {:eex, "lib/application_name_web/templates/error/500_page.html.eex",
     "lib/application_name_web/templates/error/500_page.html.eex"},

    # Navigation and page index
    {:eex, "lib/application_name_web/templates/page/_navigation.html.eex",
     "lib/application_name_web/templates/page/_navigation.html.eex"},
    {:eex, "lib/application_name_web/templates/page/index.html.eex",
     "lib/application_name_web/templates/page/index.html.eex"},
    {:eex, "lib/application_name_web/templates/page/_footer.html.eex",
     "lib/application_name_web/templates/page/_footer.html.eex"},
    {:eex, "lib/application_name_web/templates/page/__logo.html.eex",
     "lib/application_name_web/templates/page/__logo.html.eex"},

    # Default Villain parser
    {:eex, "lib/application_name_web/villain/parser.ex",
     "lib/application_name_web/villain/parser.ex"},

    # E2E test setup
    {:eex, "test/e2e/test_helper.exs", "test/e2e/test_helper.exs"},

    # Default configuration files
    {:eex, "config/brando.exs", "config/brando.exs"},
    {:eex, "config/e2e.exs", "config/e2e.exs"},
    {:eex, "config/prod.exs", "config/prod.exs"},
    {:eex, "config/staging.exs", "config/staging.exs"},
    {:eex, "config/staging.secret.exs", "config/staging.secret.exs"},

    # Migration files
    {:eex, "migrations/20150123230712_create_users.exs",
     "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex, "migrations/20150215090305_create_imagecategories.exs",
     "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex, "migrations/20150215090306_create_imageseries.exs",
     "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex, "migrations/20150215090307_create_images.exs",
     "priv/repo/migrations/20150215090307_create_images.exs"},
    {:eex, "migrations/20171103152200_create_pages.exs",
     "priv/repo/migrations/20171103152200_create_pages.exs"},
    {:eex, "migrations/20171103152205_create_pagefragments.exs",
     "priv/repo/migrations/20171103152205_create_pagefragments.exs"},

    # Repo seeds
    {:eex, "repo/seeds.exs", "priv/repo/seeds.exs"},

    # Master app template.
    {:eex, "lib/application_name_web/templates/layout/app.html.eex",
     "lib/application_name_web/templates/layout/app.html.eex"},

    # Gettext templates
    {:keep, "priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex, "lib/application_name_web/gettext.ex", "lib/application_name_web/gettext.ex"},

    # Guardian templates
    {:eex, "lib/application_name_web/guardian.ex", "lib/application_name_web/guardian.ex"},
    {:eex, "lib/application_name_web/guardian/gql_pipeline.ex",
     "lib/application_name_web/guardian/gql_pipeline.ex"},
    {:eex, "lib/application_name_web/guardian/token_pipeline.ex",
     "lib/application_name_web/guardian/token_pipeline.ex"},
    {:eex, "lib/application_name_web/controllers/session_controller.ex",
     "lib/application_name_web/controllers/session_controller.ex"},
    {:eex, "lib/application_name_web/views/session_view.ex",
     "lib/application_name_web/views/session_view.ex"},

    # Helpers for frontend
    {:eex, "lib/application_name_web.ex", "lib/application_name_web.ex"},

    # Channel + socket
    {:eex, "lib/application_name_web/channels/admin_channel.ex",
     "lib/application_name_web/channels/admin_channel.ex"},
    {:eex, "lib/application_name_web/channels/admin_socket.ex",
     "lib/application_name_web/channels/admin_socket.ex"},

    # Absinthe/GraphQL
    {:eex, "lib/graphql/schema.ex", "lib/application_name/graphql/schema.ex"},
    {:eex, "lib/graphql/schema/types.ex", "lib/application_name/graphql/schema/types.ex"},
    {:keep, "lib/graphql/schema/types", "lib/application_name/graphql/schema/types"},
    {:keep, "lib/graphql/resolvers", "lib/application_name/graphql/resolvers"},

    # Endpoint
    {:eex, "lib/application_name_web/endpoint.ex", "lib/application_name_web/endpoint.ex"}
  ]

  @static [
    # Deployment tools
    {:copy, "gitignore", ".gitignore"},
    {:copy, "dockerignore", ".dockerignore"},
    {:copy, "Dockerfile", "Dockerfile"},
    {:eex, "fabfile.py", "fabfile.py"},

    # Backend assets
    {:copy, "assets/backend/babel.config.js", "assets/backend/babel.config.js"},
    {:copy, "assets/backend/browserslistrc", "assets/backend/.browserslistrc"},
    {:copy, "assets/backend/eslintrc.js", "assets/backend/.eslintrc.js"},
    {:copy, "assets/backend/package.json", "assets/backend/package.json"},
    {:copy, "assets/backend/postcssrc.js", "assets/backend/.postcssrc.js"},
    {:copy, "assets/backend/vue.config.js", "assets/backend/vue.config.js"},

    # Backend CYPRESS
    {:copy, "assets/backend/cypress.json", "assets/backend/cypress.json"},
    {:copy, "assets/backend/cypress/support/index.js", "assets/backend/cypress/support/index.js"},
    {:copy, "assets/backend/cypress/support/commands.js",
     "assets/backend/cypress/support/commands.js"},
    {:copy, "assets/backend/cypress/integration/example.js",
     "assets/backend/cypress/integration/example.js"},
    {:copy, "assets/backend/cypress/integration/builtIns/auth.spec.js",
     "assets/backend/cypress/integration/builtIns/auth.spec.js"},
    {:copy, "assets/backend/cypress/integration/builtIns/pages.spec.js",
     "assets/backend/cypress/integration/builtIns/pages.spec.js"},
    {:copy, "assets/backend/cypress/integration/builtIns/users.spec.js",
     "assets/backend/cypress/integration/builtIns/users.spec.js"},

    # Backend src
    {:copy, "assets/backend/src/config.js", "assets/backend/src/config.js"},
    {:copy, "assets/backend/src/main.js", "assets/backend/src/main.js"},
    {:copy, "assets/backend/src/menus/index.js", "assets/backend/src/menus/index.js"},
    {:copy, "assets/backend/src/router.js", "assets/backend/src/router.js"},
    {:copy, "assets/backend/src/routes/dashboard.js", "assets/backend/src/routes/dashboard.js"},
    {:copy, "assets/backend/src/routes/index.js", "assets/backend/src/routes/index.js"},
    {:copy, "assets/backend/src/store/index.js", "assets/backend/src/store/index.js"},
    {:copy, "assets/backend/src/store/mutation-types.js",
     "assets/backend/src/store/mutation-types.js"},
    {:copy, "assets/backend/src/views/dashboard/DashboardView.vue",
     "assets/backend/src/views/dashboard/DashboardView.vue"},
    {:copy, "assets/backend/public/fonts/fa-light-300.eot",
     "assets/backend/public/fonts/fa-light-300.eot"},
    {:copy, "assets/backend/public/fonts/fa-light-300.otf",
     "assets/backend/public/fonts/fa-light-300.otf"},
    {:copy, "assets/backend/public/fonts/fa-light-300.svg",
     "assets/backend/public/fonts/fa-light-300.svg"},
    {:copy, "assets/backend/public/fonts/fa-light-300.ttf",
     "assets/backend/public/fonts/fa-light-300.ttf"},
    {:copy, "assets/backend/public/fonts/fa-light-300.woff",
     "assets/backend/public/fonts/fa-light-300.woff"},
    {:copy, "assets/backend/public/fonts/fa-light-300.woff2",
     "assets/backend/public/fonts/fa-light-300.woff2"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.eot",
     "assets/backend/public/fonts/fa-solid-900.eot"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.otf",
     "assets/backend/public/fonts/fa-solid-900.otf"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.svg",
     "assets/backend/public/fonts/fa-solid-900.svg"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.ttf",
     "assets/backend/public/fonts/fa-solid-900.ttf"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.woff",
     "assets/backend/public/fonts/fa-solid-900.woff"},
    {:copy, "assets/backend/public/fonts/fa-solid-900.woff2",
     "assets/backend/public/fonts/fa-solid-900.woff2"},
    {:copy, "assets/backend/public/fonts/osb.woff", "assets/backend/public/fonts/osb.woff"},
    {:copy, "assets/backend/public/fonts/osr.woff", "assets/backend/public/fonts/osr.woff"},
    {:copy, "assets/backend/public/fonts/osr.woff2", "assets/backend/public/fonts/osr.woff2"},
    {:copy, "assets/backend/public/images/admin/avatar.png",
     "assets/backend/public/images/admin/avatar.png"},
    {:copy, "assets/backend/src/styles/app.scss", "assets/backend/src/styles/app.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_animated.scss",
     "assets/backend/src/styles/fontawesome/_animated.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_bordered-pulled.scss",
     "assets/backend/src/styles/fontawesome/_bordered-pulled.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_core.scss",
     "assets/backend/src/styles/fontawesome/_core.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_fixed-width.scss",
     "assets/backend/src/styles/fontawesome/_fixed-width.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_icons.scss",
     "assets/backend/src/styles/fontawesome/_icons.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_larger.scss",
     "assets/backend/src/styles/fontawesome/_larger.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_list.scss",
     "assets/backend/src/styles/fontawesome/_list.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_mixins.scss",
     "assets/backend/src/styles/fontawesome/_mixins.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_rotated-flipped.scss",
     "assets/backend/src/styles/fontawesome/_rotated-flipped.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_screen-reader.scss",
     "assets/backend/src/styles/fontawesome/_screen-reader.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_stacked.scss",
     "assets/backend/src/styles/fontawesome/_stacked.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/_variables.scss",
     "assets/backend/src/styles/fontawesome/_variables.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/fontawesome-pro-core.scss",
     "assets/backend/src/styles/fontawesome/fontawesome-pro-core.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/fontawesome-pro-light.scss",
     "assets/backend/src/styles/fontawesome/fontawesome-pro-light.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/fontawesome-pro-regular.scss",
     "assets/backend/src/styles/fontawesome/fontawesome-pro-regular.scss"},
    {:copy, "assets/backend/src/styles/fontawesome/fontawesome-pro-solid.scss",
     "assets/backend/src/styles/fontawesome/fontawesome-pro-solid.scss"},
    {:copy, "assets/backend/src/styles/includes/_fonts.scss",
     "assets/backend/src/styles/includes/_fonts.scss"},

    # Frontend assets
    {:copy, "assets/frontend/babel.config.js", "assets/frontend/babel.config.js"},
    {:copy, "assets/frontend/browserslistrc", "assets/frontend/.browserslistrc"},
    {:copy, "assets/frontend/eslintrc.js", "assets/frontend/.eslintrc.js"},
    {:copy, "assets/frontend/package.json", "assets/frontend/package.json"},
    {:copy, "assets/frontend/postcss.config.js", "assets/frontend/postcss.config.js"},
    {:copy, "assets/frontend/stylelint.config.js", "assets/frontend/stylelint.config.js"},
    {:copy, "assets/frontend/webpack.config.js", "assets/frontend/webpack.config.js"},
    {:copy, "assets/frontend/yarn.lock", "assets/frontend/yarn.lock"},

    # Frontend CYPRESS
    {:copy, "assets/frontend/cypress.json", "assets/frontend/cypress.json"},
    {:copy, "assets/backend/cypress/integration/example.js",
     "assets/frontend/cypress/integration/example.js"},

    # Frontend src
    {:copy, "assets/frontend/css/_variables.scss", "assets/frontend/css/_variables.scss"},
    {:copy, "assets/frontend/css/app.scss", "assets/frontend/css/app.scss"},
    {:copy, "assets/frontend/css/includes/_animations.scss",
     "assets/frontend/css/includes/_animations.scss"},
    {:copy, "assets/frontend/css/includes/_containers.scss",
     "assets/frontend/css/includes/_containers.scss"},
    {:copy, "assets/frontend/css/includes/_content.scss",
     "assets/frontend/css/includes/_content.scss"},
    {:copy, "assets/frontend/css/includes/_cookies.scss",
     "assets/frontend/css/includes/_cookies.scss"},
    {:copy, "assets/frontend/css/includes/_fader.scss",
     "assets/frontend/css/includes/_fader.scss"},
    {:copy, "assets/frontend/css/includes/_fonts.scss",
     "assets/frontend/css/includes/_fonts.scss"},
    {:copy, "assets/frontend/css/includes/_footer.scss",
     "assets/frontend/css/includes/_footer.scss"},
    {:copy, "assets/frontend/css/includes/_hamburgers.scss",
     "assets/frontend/css/includes/_hamburgers.scss"},
    {:copy, "assets/frontend/css/includes/_header.scss",
     "assets/frontend/css/includes/_header.scss"},
    {:copy, "assets/frontend/css/includes/_headers.scss",
     "assets/frontend/css/includes/_headers.scss"},
    {:copy, "assets/frontend/css/includes/_lightbox.scss",
     "assets/frontend/css/includes/_lightbox.scss"},
    {:copy, "assets/frontend/css/includes/_modules.scss",
     "assets/frontend/css/includes/_modules.scss"},
    {:copy, "assets/frontend/css/includes/_navigation.scss",
     "assets/frontend/css/includes/_navigation.scss"},
    {:copy, "assets/frontend/css/includes/_navigation-nojs.scss",
     "assets/frontend/css/includes/_navigation-nojs.scss"},
    {:copy, "assets/frontend/css/includes/_paragraphs.scss",
     "assets/frontend/css/includes/_paragraphs.scss"},
    {:copy, "assets/frontend/css/includes/_sections.scss",
     "assets/frontend/css/includes/_sections.scss"},
    {:copy, "assets/frontend/css/includes/_slider.scss",
     "assets/frontend/css/includes/_slider.scss"},
    {:copy, "assets/frontend/css/includes/_templates.scss",
     "assets/frontend/css/includes/_templates.scss"},
    {:copy, "assets/frontend/js/index.js", "assets/frontend/js/index.js"},
    {:copy, "assets/frontend/static/favicon.ico", "assets/frontend/static/favicon.ico"},
    {:copy, "assets/frontend/static/ico/android-chrome-192x192.png",
     "assets/frontend/static/ico/android-chrome-192x192.png"},
    {:copy, "assets/frontend/static/ico/android-chrome-512x512.png",
     "assets/frontend/static/ico/android-chrome-512x512.png"},
    {:copy, "assets/frontend/static/ico/apple-touch-icon.png",
     "assets/frontend/static/ico/apple-touch-icon.png"},
    {:copy, "assets/frontend/static/ico/browserconfig.xml",
     "assets/frontend/static/ico/browserconfig.xml"},
    {:copy, "assets/frontend/static/ico/favicon-16x16.png",
     "assets/frontend/static/ico/favicon-16x16.png"},
    {:copy, "assets/frontend/static/ico/favicon-32x32.png",
     "assets/frontend/static/ico/favicon-32x32.png"},
    {:copy, "assets/frontend/static/ico/favicon.ico", "assets/frontend/static/ico/favicon.ico"},
    {:copy, "assets/frontend/static/ico/manifest.json",
     "assets/frontend/static/ico/manifest.json"},
    {:copy, "assets/frontend/static/ico/mstile-144x144.png",
     "assets/frontend/static/ico/mstile-144x144.png"},
    {:copy, "assets/frontend/static/ico/mstile-150x150.png",
     "assets/frontend/static/ico/mstile-150x150.png"},
    {:copy, "assets/frontend/static/ico/mstile-310x150.png",
     "assets/frontend/static/ico/mstile-310x150.png"},
    {:copy, "assets/frontend/static/ico/mstile-310x310.png",
     "assets/frontend/static/ico/mstile-310x310.png"},
    {:copy, "assets/frontend/static/ico/mstile-70x70.png",
     "assets/frontend/static/ico/mstile-70x70.png"},
    {:copy, "assets/frontend/static/ico/safari-pinned-tab.svg",
     "assets/frontend/static/ico/safari-pinned-tab.svg"},
    {:copy, "assets/frontend/static/images/brando/blank.gif",
     "assets/frontend/static/images/brando/blank.gif"},
    {:copy, "assets/frontend/static/images/brando/brando-big.png",
     "assets/frontend/static/images/brando/brando-big.png"},
    {:copy, "assets/frontend/static/images/brando/defaults/micro/avatar_default.jpg",
     "assets/frontend/static/images/brando/defaults/micro/avatar_default.jpg"},
    {:copy, "assets/frontend/static/images/brando/defaults/thumb/avatar_default.jpg",
     "assets/frontend/static/images/brando/defaults/thumb/avatar_default.jpg"},
    {:copy, "assets/frontend/static/images/logo.svg", "assets/frontend/static/images/logo.svg"}
  ]

  @root Path.expand("../../../priv", __DIR__)

  for {format, source, _} <- @new ++ @static do
    unless format in [:keep, :copy] do
      @external_resource Path.join([@root, "templates/brando.install", source])
      def render(unquote(Path.join("templates/brando.install", source))),
        do: unquote(File.read!(Path.join([@root, "templates/brando.install", source])))
    end
  end

  @doc """
  Copies Brando files from template and static directories to OTP app.
  """
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [module: :string])

    app = Mix.Project.config()[:app]

    binding = [
      application_module:
        (opts[:module] && opts[:module]) || Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    Mix.shell().info("\nDeleting old assets")
    File.rm_rf("assets")

    Mix.shell().info("\nMoving test/ to test/unit/")
    File.rename("test", "test/unit")

    copy_from("templates/brando.install", "./", binding, @new)
    copy_from("templates/brando.install", "./", binding, @static)

    Mix.shell().info("\nBrando finished copying.")
  end

  defp copy_from(src_dir, target_dir, binding, mapping) when is_list(mapping) do
    application_name = Keyword.fetch!(binding, :application_name)

    for {format, source, target_path} <- mapping do
      source = Path.join([src_dir, source])

      target =
        Path.join(target_dir, String.replace(target_path, "application_name", application_name))

      case format do
        :keep ->
          File.mkdir_p!(target)

        :text ->
          create_file(target, render(source), force: true)

        :copy ->
          File.mkdir_p!(Path.dirname(target))
          File.copy!(Path.join(@root, source), target)

        :eex ->
          contents = EEx.eval_string(render(source), binding, file: source)
          create_file(target, contents, force: true)
      end
    end
  end
end
