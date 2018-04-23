defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  import Mix.Generator

  @moduledoc """
  Install Brando.
  """

  @shortdoc "Generates files for Brando."

  @new [
    # Mix template
    {:eex,  "templates/brando.install/mix.exs", "mix.exs"},

    # Etc. Various OS config files and log directory.
    {:keep, "templates/brando.install/log", "log"},
    {:eex,  "templates/brando.install/etc/logrotate/prod.conf", "etc/logrotate/prod.conf"},
    {:eex,  "templates/brando.install/etc/nginx/prod.conf", "etc/nginx/prod.conf"},
    {:eex,  "templates/brando.install/etc/supervisord/prod.conf", "etc/supervisord/prod.conf"},

    # Tuple implementation for Poison
    {:eex,  "templates/brando.install/lib/application_name/tuple.ex", "lib/application_name/tuple.ex"},

    # Router template
    {:eex,  "templates/brando.install/lib/application_name_web/router.ex", "lib/application_name_web/router.ex"},

    # Lockdown files
    {:eex,  "templates/brando.install/lib/application_name_web/controllers/lockdown_controller.ex", "lib/application_name_web/controllers/lockdown_controller.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/templates/layout/lockdown.html.eex", "lib/application_name_web/templates/layout/lockdown.html.eex"},
    {:eex,  "templates/brando.install/lib/application_name_web/templates/lockdown/index.html.eex", "lib/application_name_web/templates/lockdown/index.html.eex"},
    {:eex,  "templates/brando.install/lib/application_name_web/views/lockdown_view.ex", "lib/application_name_web/views/lockdown_view.ex"},

    # Fallback and errors
    {:eex,  "templates/brando.install/lib/application_name_web/controllers/fallback_controller.ex", "lib/application_name_web/controllers/fallback_controller.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/views/error_view.ex", "lib/application_name_web/views/error_view.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/templates/error/404_page.html.eex", "lib/application_name_web/templates/error/404_page.html.eex"},
    {:eex,  "templates/brando.install/lib/application_name_web/templates/error/500_page.html.eex", "lib/application_name_web/templates/error/500_page.html.eex"},

    # Navigation and page index
    {:text,  "templates/brando.install/lib/application_name_web/templates/page/_navigation.html.eex", "lib/application_name_web/templates/page/_navigation.html.eex"},
    {:text,  "templates/brando.install/lib/application_name_web/templates/page/index.html.eex", "lib/application_name_web/templates/page/index.html.eex"},

    # Default Villain parser
    {:eex,  "templates/brando.install/lib/application_name_web/villain/parser.ex", "lib/application_name_web/villain/parser.ex"},

    # Default configuration files
    {:eex,  "templates/brando.install/config/brando.exs", "config/brando.exs"},
    {:eex,  "templates/brando.install/config/prod.exs", "config/prod.exs"},

    # Migration files
    {:eex,  "templates/brando.install/migrations/20150123230712_create_users.exs", "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090305_create_imagecategories.exs", "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090306_create_imageseries.exs", "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090307_create_images.exs", "priv/repo/migrations/20150215090307_create_images.exs"},

    {:eex,  "templates/brando.install/migrations/20171103152200_create_pages.exs", "priv/repo/migrations/20171103152200_create_pages.exs"},
    {:eex,  "templates/brando.install/migrations/20171103152205_create_pagefragments.exs", "priv/repo/migrations/20171103152205_create_pagefragments.exs"},

    # Repo seeds
    {:eex,  "templates/brando.install/repo/seeds.exs", "priv/repo/seeds.exs"},

    # Master app template.
    {:eex, "templates/brando.install/lib/application_name_web/templates/layout/app.html.eex", "lib/application_name_web/templates/layout/app.html.eex"},

    # Gettext templates
    {:keep, "templates/brando.install/priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "templates/brando.install/priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex,  "templates/brando.install/lib/application_name_web/gettext.ex", "lib/application_name_web/gettext.ex"},

    # Guardian templates
    {:eex,  "templates/brando.install/lib/application_name_web/guardian.ex", "lib/application_name_web/guardian.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/guardian/gql_pipeline.ex", "lib/application_name_web/guardian/gql_pipeline.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/guardian/token_pipeline.ex", "lib/application_name_web/guardian/token_pipeline.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/controllers/session_controller.ex", "lib/application_name_web/controllers/session_controller.ex"},
    {:eex,  "templates/brando.install/lib/application_name_web/views/session_view.ex", "lib/application_name_web/views/session_view.ex"},

    # Helpers for frontend
    {:eex, "templates/brando.install/lib/application_name_web.ex", "lib/application_name_web.ex"},

    # Postgrex types
    {:eex, "templates/brando.install/lib/postgrex_types.ex", "lib/application_name/postgrex_types.ex"},

    # Channel + socket
    {:eex, "templates/brando.install/lib/application_name_web/channels/admin_channel.ex", "lib/application_name_web/channels/admin_channel.ex"},
    {:eex, "templates/brando.install/lib/application_name_web/channels/admin_socket.ex", "lib/application_name_web/channels/admin_socket.ex"},

    # Absinthe/GraphQL
    {:eex, "templates/brando.install/lib/graphql/schema.ex", "lib/application_name/graphql/schema.ex"},
    {:eex, "templates/brando.install/lib/graphql/schema/types.ex", "lib/application_name/graphql/schema/types.ex"},
    {:keep, "templates/brando.install/lib/graphql/schema/types", "lib/application_name/graphql/schema/types"},
    {:keep, "templates/brando.install/lib/graphql/resolvers", "lib/application_name/graphql/resolvers"},

    # Endpoint
    {:eex, "templates/brando.install/lib/application_name_web/endpoint.ex", "lib/application_name_web/endpoint.ex"},
  ]

  @static [
    # Deployment tools
    {:copy, "templates/brando.install/gitignore", ".gitignore"},
    {:copy, "templates/brando.install/dockerignore", ".dockerignore"},
    {:copy, "templates/brando.install/Dockerfile", "Dockerfile"},
    {:eex,  "templates/brando.install/fabfile.py", "fabfile.py"},

    # Backend assets
    {:copy, "templates/brando.install/assets/backend/build/build.js", "assets/backend/build/build.js"},
    {:copy, "templates/brando.install/assets/backend/build/check-versions.js", "assets/backend/build/check-versions.js"},
    {:copy, "templates/brando.install/assets/backend/build/utils.js", "assets/backend/build/utils.js"},
    {:copy, "templates/brando.install/assets/backend/build/vue-loader.conf.js", "assets/backend/build/vue-loader.conf.js"},
    {:copy, "templates/brando.install/assets/backend/build/webpack.base.conf.js", "assets/backend/build/webpack.base.conf.js"},
    {:copy, "templates/brando.install/assets/backend/build/webpack.dev.conf.js", "assets/backend/build/webpack.dev.conf.js"},
    {:copy, "templates/brando.install/assets/backend/build/webpack.prod.conf.js", "assets/backend/build/webpack.prod.conf.js"},
    {:copy, "templates/brando.install/assets/backend/build/webpack.test.conf.js", "assets/backend/build/webpack.test.conf.js"},
    {:copy, "templates/brando.install/assets/backend/config/dev.env.js", "assets/backend/config/dev.env.js"},
    {:copy, "templates/brando.install/assets/backend/config/index.js", "assets/backend/config/index.js"},
    {:copy, "templates/brando.install/assets/backend/config/prod.env.js", "assets/backend/config/prod.env.js"},
    {:copy, "templates/brando.install/assets/backend/config/test.env.js", "assets/backend/config/test.env.js"},
    {:copy, "templates/brando.install/assets/backend/babelrc", "assets/backend/.babelrc"},
    {:copy, "templates/brando.install/assets/backend/package.json", "assets/backend/package.json"},
    {:copy, "templates/brando.install/assets/backend/src/config.js", "assets/backend/src/config.js"},
    {:copy, "templates/brando.install/assets/backend/src/main.js", "assets/backend/src/main.js"},
    {:copy, "templates/brando.install/assets/backend/src/menus/index.js", "assets/backend/src/menus/index.js"},
    {:copy, "templates/brando.install/assets/backend/src/router.js", "assets/backend/src/router.js"},
    {:copy, "templates/brando.install/assets/backend/src/routes/dashboard.js", "assets/backend/src/routes/dashboard.js"},
    {:copy, "templates/brando.install/assets/backend/src/routes/index.js", "assets/backend/src/routes/index.js"},
    {:copy, "templates/brando.install/assets/backend/src/store/index.js", "assets/backend/src/store/index.js"},
    {:copy, "templates/brando.install/assets/backend/src/store/mutation-types.js", "assets/backend/src/store/mutation-types.js"},
    {:copy, "templates/brando.install/assets/backend/src/views/dashboard/DashboardView.vue", "assets/backend/src/views/dashboard/DashboardView.vue"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.eot", "assets/backend/static/fonts/fa-light-300.eot"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.otf", "assets/backend/static/fonts/fa-light-300.otf"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.svg", "assets/backend/static/fonts/fa-light-300.svg"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.ttf", "assets/backend/static/fonts/fa-light-300.ttf"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.woff", "assets/backend/static/fonts/fa-light-300.woff"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-light-300.woff2", "assets/backend/static/fonts/fa-light-300.woff2"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.eot", "assets/backend/static/fonts/fa-solid-900.eot"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.otf", "assets/backend/static/fonts/fa-solid-900.otf"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.svg", "assets/backend/static/fonts/fa-solid-900.svg"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.ttf", "assets/backend/static/fonts/fa-solid-900.ttf"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.woff", "assets/backend/static/fonts/fa-solid-900.woff"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/fa-solid-900.woff2", "assets/backend/static/fonts/fa-solid-900.woff2"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/osb.woff", "assets/backend/static/fonts/osb.woff"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/osr.woff", "assets/backend/static/fonts/osr.woff"},
    {:copy, "templates/brando.install/assets/backend/static/fonts/osr.woff2", "assets/backend/static/fonts/osr.woff2"},
    {:copy, "templates/brando.install/assets/backend/static/images/admin/avatar.png", "assets/backend/static/images/admin/avatar.png"},
    {:copy, "templates/brando.install/assets/backend/styles/app.scss", "assets/backend/styles/app.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_animated.scss", "assets/backend/styles/fontawesome/_animated.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_bordered-pulled.scss", "assets/backend/styles/fontawesome/_bordered-pulled.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_core.scss", "assets/backend/styles/fontawesome/_core.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_fixed-width.scss", "assets/backend/styles/fontawesome/_fixed-width.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_icons.scss", "assets/backend/styles/fontawesome/_icons.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_larger.scss", "assets/backend/styles/fontawesome/_larger.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_list.scss", "assets/backend/styles/fontawesome/_list.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_mixins.scss", "assets/backend/styles/fontawesome/_mixins.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_rotated-flipped.scss", "assets/backend/styles/fontawesome/_rotated-flipped.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_screen-reader.scss", "assets/backend/styles/fontawesome/_screen-reader.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_stacked.scss", "assets/backend/styles/fontawesome/_stacked.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/_variables.scss", "assets/backend/styles/fontawesome/_variables.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/fontawesome-pro-core.scss", "assets/backend/styles/fontawesome/fontawesome-pro-core.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/fontawesome-pro-light.scss", "assets/backend/styles/fontawesome/fontawesome-pro-light.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/fontawesome-pro-regular.scss", "assets/backend/styles/fontawesome/fontawesome-pro-regular.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/fontawesome/fontawesome-pro-solid.scss", "assets/backend/styles/fontawesome/fontawesome-pro-solid.scss"},
    {:copy, "templates/brando.install/assets/backend/styles/includes/_fonts.scss", "assets/backend/styles/includes/_fonts.scss"},

    # Frontend assets
    {:copy, "templates/brando.install/assets/frontend/css/_bootstrap.scss", "assets/frontend/css/_bootstrap.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/_variables.scss", "assets/frontend/css/_variables.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/app.scss", "assets/frontend/css/app.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_animations.scss", "assets/frontend/css/includes/_animations.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_containers.scss", "assets/frontend/css/includes/_containers.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_fonts.scss", "assets/frontend/css/includes/_fonts.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_headers.scss", "assets/frontend/css/includes/_headers.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_navigation.scss", "assets/frontend/css/includes/_navigation.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_paragraphs.scss", "assets/frontend/css/includes/_paragraphs.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_sections.scss", "assets/frontend/css/includes/_sections.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_slider.scss", "assets/frontend/css/includes/_slider.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_utils.scss", "assets/frontend/css/includes/_utils.scss"},
    {:copy, "templates/brando.install/assets/frontend/js/index.js", "assets/frontend/js/index.js"},
    {:copy, "templates/brando.install/assets/frontend/package.json", "assets/frontend/package.json"},
    {:copy, "templates/brando.install/assets/frontend/postcss.config.js", "assets/frontend/postcss.config.js"},
    {:copy, "templates/brando.install/assets/frontend/static/favicon.ico", "assets/frontend/static/favicon.ico"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/android-chrome-192x192.png", "assets/frontend/static/ico/android-chrome-192x192.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/android-chrome-512x512.png", "assets/frontend/static/ico/android-chrome-512x512.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/apple-touch-icon.png", "assets/frontend/static/ico/apple-touch-icon.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/browserconfig.xml", "assets/frontend/static/ico/browserconfig.xml"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/favicon-16x16.png", "assets/frontend/static/ico/favicon-16x16.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/favicon-32x32.png", "assets/frontend/static/ico/favicon-32x32.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/favicon.ico", "assets/frontend/static/ico/favicon.ico"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/manifest.json", "assets/frontend/static/ico/manifest.json"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/mstile-144x144.png", "assets/frontend/static/ico/mstile-144x144.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/mstile-150x150.png", "assets/frontend/static/ico/mstile-150x150.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/mstile-310x150.png", "assets/frontend/static/ico/mstile-310x150.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/mstile-310x310.png", "assets/frontend/static/ico/mstile-310x310.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/mstile-70x70.png", "assets/frontend/static/ico/mstile-70x70.png"},
    {:copy, "templates/brando.install/assets/frontend/static/ico/safari-pinned-tab.svg", "assets/frontend/static/ico/safari-pinned-tab.svg"},
    {:copy, "templates/brando.install/assets/frontend/static/images/brando/blank.gif", "assets/frontend/static/images/brando/blank.gif"},
    {:copy, "templates/brando.install/assets/frontend/static/images/brando/brando-big.png", "assets/frontend/static/images/brando/brando-big.png"},
    {:copy, "templates/brando.install/assets/frontend/static/images/brando/defaults/micro/avatar_default.jpg", "assets/frontend/static/images/brando/defaults/micro/avatar_default.jpg"},
    {:copy, "templates/brando.install/assets/frontend/static/images/brando/defaults/thumb/avatar_default.jpg", "assets/frontend/static/images/brando/defaults/thumb/avatar_default.jpg"},
    {:copy, "templates/brando.install/assets/frontend/static/images/logo.svg", "assets/frontend/static/images/logo.svg"},
    {:copy, "templates/brando.install/assets/frontend/webpack.config.js", "assets/frontend/webpack.config.js"},
  ]

  @root Path.expand("../../../priv", __DIR__)

  for {format, source, _} <- @new ++ @static do
    unless format in [:keep, :copy] do
      @external_resource Path.join(@root, source)
      def render(unquote(source)), do: unquote(File.read!(Path.join(@root, source)))
    end
  end

  @doc """
  Copies Brando files from template and static directories to OTP app.
  """
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [module: :string])

    app = Mix.Project.config()[:app]
    binding = [
      application_module: opts[:module] && opts[:module] || Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    Mix.shell.info "\nDeleting old assets"
    File.rm_rf("assets")

    copy_from "./", binding, @new
    copy_from "./", binding, @static

    Mix.shell.info "\nBrando finished copying."
  end

  defp copy_from(target_dir, binding, mapping) when is_list(mapping) do
    application_name = Keyword.fetch!(binding, :application_name)
    for {format, source, target_path} <- mapping do
      target = Path.join(target_dir, String.replace(target_path,
                         "application_name", application_name))
      case format do
        :keep -> File.mkdir_p!(target)
        :text -> create_file(target, render(source))
        :copy -> File.mkdir_p!(Path.dirname(target))
                 File.copy!(Path.join(@root, source), target)
        :eex  -> contents = EEx.eval_string(render(source), binding, file: source)
                 create_file(target, contents)
      end
    end
  end
end
