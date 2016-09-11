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

    # EXRM release tasks (migrations)
    {:eex,  "templates/brando.install/lib/release_tasks.ex", "lib/application_name/release_tasks.ex"},

    # Etc. Various OS config files and log directory.
    {:keep, "templates/brando.install/logs", "logs"},
    {:eex,  "templates/brando.install/etc/logrotate/prod.conf", "etc/logrotate/prod.conf"},
    {:eex,  "templates/brando.install/etc/nginx/prod.conf", "etc/nginx/prod.conf"},
    {:eex,  "templates/brando.install/etc/supervisord/prod.conf", "etc/supervisord/prod.conf"},

    # Router template
    {:eex,  "templates/brando.install/web/router.ex", "web/router.ex"},

    # Lockdown files
    {:eex,  "templates/brando.install/web/controllers/lockdown_controller.ex", "web/controllers/lockdown_controller.ex"},
    {:eex,  "templates/brando.install/web/templates/layout/lockdown.html.eex", "web/templates/layout/lockdown.html.eex"},
    {:eex,  "templates/brando.install/web/templates/lockdown/index.html.eex", "web/templates/lockdown/index.html.eex"},
    {:eex,  "templates/brando.install/web/views/lockdown_view.ex", "web/views/lockdown_view.ex"},

    # Default Villain parser
    {:eex,  "templates/brando.install/web/villain/parser.ex", "web/villain/parser.ex"},

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
    {:text, "templates/brando.install/web/templates/layout/app.html.eex", "web/templates/layout/app.html.eex"},

    # Gettext templates
    {:keep, "templates/brando.install/logs", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "templates/brando.install/logs", "priv/static/gettext/frontend"},
    {:eex,  "templates/brando.install/web/gettext.ex", "web/gettext.ex"},

    # Admin web.ex
    {:eex, "templates/brando.install/web/admin_web.ex", "web/admin_web.ex"}
  ]

  @static [
    # Javascript assets
    {:copy, "templates/brando.install/package.json", "package.json"},
    {:copy, "templates/brando.install/brunch-config.js", "brunch-config.js"},
    {:copy, "templates/brando.install/web/static/js/cookie_law.js", "web/static/vendor/cookie_law.js"},

    # Deployment tools
    {:copy, "templates/brando.install/gitignore", ".gitignore"},
    {:copy, "templates/brando.install/dockerignore", ".dockerignore"},
    {:copy, "templates/brando.install/Dockerfile", "Dockerfile"},
    {:eex,  "templates/brando.install/fabfile.py", "fabfile.py"},
    {:copy, "templates/brando.install/compile", "compile"},

    # Frontend JS
    {:copy, "templates/brando.install/web/static/js/app/app.js", "web/static/js/app.js"},
    {:copy, "templates/brando.install/web/static/js/app/flexslider.js", "web/static/js/flexslider.js"},
    {:copy, "templates/brando.install/web/static/js/admin/custom.js", "web/static/js/admin/custom.js"},

    # Frontend SCSS
    {:copy, "templates/brando.install/web/static/css/app.scss", "web/static/css/app.scss"},
    {:copy, "templates/brando.install/web/static/css/custom/brando.custom.scss", "web/static/css/custom/brando.custom.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_general.scss", "web/static/css/includes/_general.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_colorbox.scss", "web/static/css/includes/_colorbox.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_cookielaw.scss", "web/static/css/includes/_cookielaw.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_dropdown.scss", "web/static/css/includes/_dropdown.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_instagram.scss", "web/static/css/includes/_instagram.scss"},
    {:copy, "templates/brando.install/web/static/css/includes/_nav.scss", "web/static/css/includes/_nav.scss"},

    # Icons
    {:copy, "templates/brando.install/static/brando/favicon.ico", "web/static/assets/favicon.ico"},

    # Webfonts - icons
    {:copy, "templates/brando.install/static/brando/fonts/fontawesome-webfont.eot", "web/static/assets/fonts/fontawesome-webfont.eot"},
    {:copy, "templates/brando.install/static/brando/fonts/fontawesome-webfont.svg", "web/static/assets/fonts/fontawesome-webfont.svg"},
    {:copy, "templates/brando.install/static/brando/fonts/fontawesome-webfont.ttf", "web/static/assets/fonts/fontawesome-webfont.ttf"},
    {:copy, "templates/brando.install/static/brando/fonts/fontawesome-webfont.woff", "web/static/assets/fonts/fontawesome-webfont.woff"},
    {:copy, "templates/brando.install/static/brando/fonts/fontawesome-webfont.woff2", "web/static/assets/fonts/fontawesome-webfont.woff2"},
    {:copy, "templates/brando.install/static/brando/fonts/FontAwesome.otf", "web/static/assets/fonts/FontAwesome.otf"},

    # Webfonts - backend
    {:copy, "templates/brando.install/static/brando/fonts/ab.woff", "web/static/assets/fonts/ab.woff"},
    {:copy, "templates/brando.install/static/brando/fonts/am.woff", "web/static/assets/fonts/am.woff"},
    {:copy, "templates/brando.install/static/brando/fonts/ar.woff", "web/static/assets/fonts/ar.woff"},

    # Images
    {:copy, "templates/brando.install/static/brando/images/blank.gif", "web/static/assets/images/brando/blank.gif"},
    {:copy, "templates/brando.install/static/brando/images/flags.png", "web/static/assets/images/brando/flags.png"},
    {:copy, "templates/brando.install/static/brando/images/brando-big.png", "web/static/assets/images/brando/brando-big.png"},

    {:copy, "templates/brando.install/static/brando/images/defaults/thumb/avatar_default.jpg", "web/static/assets/images/brando/defaults/thumb/avatar_default.jpg"},
    {:copy, "templates/brando.install/static/brando/images/defaults/micro/avatar_default.jpg", "web/static/assets/images/brando/defaults/micro/avatar_default.jpg"},
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
