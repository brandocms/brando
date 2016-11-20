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
    {:eex,  "templates/brando.install/lib/web/router.ex", "lib/web/router.ex"},

    # Lockdown files
    {:eex,  "templates/brando.install/lib/web/controllers/lockdown_controller.ex", "lib/web/controllers/lockdown_controller.ex"},
    {:eex,  "templates/brando.install/lib/web/templates/layout/lockdown.html.eex", "lib/web/templates/layout/lockdown.html.eex"},
    {:eex,  "templates/brando.install/lib/web/templates/lockdown/index.html.eex", "lib/web/templates/lockdown/index.html.eex"},
    {:eex,  "templates/brando.install/lib/web/views/lockdown_view.ex", "lib/web/views/lockdown_view.ex"},

    # Default Villain parser
    {:eex,  "templates/brando.install/lib/web/villain/parser.ex", "lib/web/villain/parser.ex"},

    # Default configuration files
    {:eex,  "templates/brando.install/config/brando.exs", "config/brando.exs"},
    {:eex,  "templates/brando.install/config/prod.exs", "config/prod.exs"},

    # Migration files
    {:eex,  "templates/brando.install/migrations/20150123230712_create_users.exs", "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090305_create_imagecategories.exs", "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090306_create_imageseries.exs", "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex,  "templates/brando.install/migrations/20150215090307_create_images.exs", "priv/repo/migrations/20150215090307_create_images.exs"},

    # Repo seeds
    {:eex,  "templates/brando.install/repo/seeds.exs", "priv/repo/seeds.exs"},

    # Master app template.
    {:text, "templates/brando.install/lib/web/templates/layout/app.html.eex", "lib/web/templates/layout/app.html.eex"},

    # Gettext templates
    {:keep, "templates/brando.install/priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "templates/brando.install/priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex,  "templates/brando.install/lib/web/gettext.ex", "lib/web/gettext.ex"},

    # Frontend helpers
    {:eex,  "templates/brando.install/lib/web/helpers/date_time_helpers.ex", "lib/web/helpers/date_time_helpers.ex"},

    # Web helpers for admin and frontend
    {:eex, "templates/brando.install/lib/admin_web.ex", "lib/admin_web.ex"},
    {:eex, "templates/brando.install/lib/web.ex", "lib/web.ex"},
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
    {:copy, "templates/brando.install/assets/js/app/app.js", "assets/js/app/app.js"},
    {:copy, "templates/brando.install/assets/js/app/flexslider.js", "assets/js/app/flexslider.js"},
    {:copy, "templates/brando.install/assets/js/admin/index.js", "assets/js/admin/index.js"},

    # Frontend SCSS
    {:copy, "templates/brando.install/assets/css/app.scss", "assets/css/app.scss"},
    {:copy, "templates/brando.install/assets/css/custom/brando.custom.scss", "assets/css/custom/brando.custom.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_general.scss", "assets/css/includes/_general.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_colorbox.scss", "assets/css/includes/_colorbox.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_cookielaw.scss", "assets/css/includes/_cookielaw.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_dropdown.scss", "assets/css/includes/_dropdown.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_instagram.scss", "assets/css/includes/_instagram.scss"},
    {:copy, "templates/brando.install/assets/css/includes/_nav.scss", "assets/css/includes/_nav.scss"},

    # Icons
    {:copy, "templates/brando.install/assets/static/brando/favicon.ico", "assets/static/favicon.ico"},

    # Webfonts - icons
    {:copy, "templates/brando.install/assets/static/brando/fonts/fontawesome-webfont.eot", "assets/static/fonts/fontawesome-webfont.eot"},
    {:copy, "templates/brando.install/assets/static/brando/fonts/fontawesome-webfont.svg", "assets/static/fonts/fontawesome-webfont.svg"},
    {:copy, "templates/brando.install/assets/static/brando/fonts/fontawesome-webfont.ttf", "assets/static/fonts/fontawesome-webfont.ttf"},
    {:copy, "templates/brando.install/assets/static/brando/fonts/fontawesome-webfont.woff", "assets/static/fonts/fontawesome-webfont.woff"},
    {:copy, "templates/brando.install/assets/static/brando/fonts/fontawesome-webfont.woff2", "assets/static/fonts/fontawesome-webfont.woff2"},
    {:copy, "templates/brando.install/assets/static/brando/fonts/FontAwesome.otf", "assets/static/fonts/FontAwesome.otf"},

    # Images
    {:copy, "templates/brando.install/assets/static/brando/images/blank.gif", "assets/static/images/brando/blank.gif"},
    {:copy, "templates/brando.install/assets/static/brando/images/flags.png", "assets/static/images/brando/flags.png"},
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

    Mix.shell.info "\nDeleting web/static/app.css"
    File.rm("web/static/css/app.css")

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
