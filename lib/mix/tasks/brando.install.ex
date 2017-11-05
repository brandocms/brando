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
    {:eex,  "templates/brando.install/lib/application_name_web/templates/error/500_page.html.eex", "lib/application_name_web/templates/error/404_page.html.eex"},

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
    {:text, "templates/brando.install/lib/application_name_web/templates/layout/app.html.eex", "lib/application_name_web/templates/layout/app.html.eex"},

    # Gettext templates
    {:keep, "templates/brando.install/priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "templates/brando.install/priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex,  "templates/brando.install/lib/application_name_web/gettext.ex", "lib/application_name_web/gettext.ex"},

    # Helpers for frontend
    {:eex, "templates/brando.install/lib/application_name_web.ex", "lib/application_name_web.ex"},

    # Postgrex types
    {:eex, "templates/brando.install/lib/postgrex_types.ex", "lib/application_name/postgrex_types.ex"},

    # Channel + socket
    {:eex, "templates/brando.install/lib/application_name_web/channels/admin_channel.ex", "lib/application_name/application_name_web/channels/admin_channel.ex"},
    {:eex, "templates/brando.install/lib/application_name_web/channels/admin_socket.ex", "lib/application_name/application_name_web/channels/admin_socket.ex"},
  ]

  @static [
    # Javascript assets
    {:copy, "templates/brando.install/package.json", "assets/package.json"},
    {:copy, "templates/brando.install/brunch-config.js", "assets/brunch-config.js"},
    {:copy, "templates/brando.install/assets/js/cookie_law.js", "assets/vendor/cookie_law.js"},

    # Deployment tools
    {:copy, "templates/brando.install/gitignore", ".gitignore"},
    {:copy, "templates/brando.install/dockerignore", ".dockerignore"},
    {:copy, "templates/brando.install/Dockerfile", "Dockerfile"},
    {:eex,  "templates/brando.install/fabfile.py", "fabfile.py"},

    # Frontend JS
    {:copy, "templates/brando.install/assets/frontend/js/index.js", "assets/frontend/js/index.js"},
    {:copy, "templates/brando.install/assets/frontend/js/flexslider.js", "assets/frontend/js/flexslider.js"},

    # Backend JS
    {:copy, "templates/brando.install/assets/backend/src/main.js", "assets/backend/src/main.js"},

    # Frontend SCSS
    {:copy, "templates/brando.install/assets/frontend/css/app.scss", "assets/frontend/css/app.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_general.scss", "assets/frontend/css/includes/_general.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_colorbox.scss", "assets/frontend/css/includes/_colorbox.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_cookielaw.scss", "assets/frontend/css/includes/_cookielaw.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_dropdown.scss", "assets/frontend/css/includes/_dropdown.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_instagram.scss", "assets/frontend/css/includes/_instagram.scss"},
    {:copy, "templates/brando.install/assets/frontend/css/includes/_nav.scss", "assets/frontend/css/includes/_nav.scss"},

    # Icons
    {:copy, "templates/brando.install/assets/static/brando/favicon.ico", "assets/static/favicon.ico"},

    # Images
    {:copy, "templates/brando.install/assets/static/brando/images/blank.gif", "assets/static/images/brando/blank.gif"},
    {:copy, "templates/brando.install/assets/static/brando/images/brando-big.png", "assets/static/images/brando/brando-big.png"},
    {:copy, "templates/brando.install/assets/static/brando/images/defaults/thumb/avatar_default.jpg", "assets/static/images/brando/defaults/thumb/avatar_default.jpg"},
    {:copy, "templates/brando.install/assets/static/brando/images/defaults/micro/avatar_default.jpg", "assets/static/images/brando/defaults/micro/avatar_default.jpg"},
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
    {opts, _, _} = OptionParser.parse(args, switches: [static: :boolean])
    app = Mix.Project.config()[:app]
    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    copy_from "./", binding, @new

    static? = if opts[:static] do
      true
    else
      Mix.shell.yes?("\nInstall static files?")
    end
    if static? do
      copy_from "./", binding, @static
    end

    Mix.shell.info "\nDeleting assets/css/app.css"
    File.rm("assets/css/app.css")
    Mix.shell.info "\nDeleting assets/css/phoenix.css"
    File.rm("assets/css/phoenix.css")
    Mix.shell.info "\nDeleting assets/js/app.js"
    File.rm("assets/js/app.js")
    Mix.shell.info "\nDeleting assets/js/socket.js"
    File.rm("assets/js/socket.js")

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
        :eex  -> contents = EEx.eval_string(render(source),
                                            binding, file: source)
                 create_file(target, contents)
      end
    end
  end
end
