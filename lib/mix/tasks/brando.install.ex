defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  import Mix.Generator

  @moduledoc """
  Install Brando.
  """

  @shortdoc "Generates files for Brando."

  @new [
    {:keep, "install/templates/logs", "logs"},
    {:eex,  "install/templates/etc/logrotate/prod.conf",                                  "etc/logrotate/prod.conf"},
    {:eex,  "install/templates/etc/logrotate/staging.conf",                               "etc/logrotate/staging.conf"},
    {:eex,  "install/templates/etc/nginx/prod.conf",                                      "etc/nginx/prod.conf"},
    {:eex,  "install/templates/etc/nginx/staging.conf",                                   "etc/nginx/staging.conf"},
    {:eex,  "install/templates/etc/supervisord/prod.conf",                                "etc/supervisord/prod.conf"},
    {:eex,  "install/templates/etc/supervisord/staging.conf",                             "etc/supervisord/staging.conf"},

    {:eex,  "install/templates/web/router.ex",                                            "web/router.ex"},
    {:eex,  "install/templates/web/controllers/lockdown_controller.ex",                   "web/controllers/lockdown_controller.ex"},
    {:eex,  "install/templates/web/templates/layout/lockdown.html.eex",                   "web/templates/layout/lockdown.html.eex"},
    {:eex,  "install/templates/web/templates/lockdown/index.html.eex",                    "web/templates/lockdown/index.html.eex"},
    {:eex,  "install/templates/web/views/lockdown_view.ex",                               "web/views/lockdown_view.ex"},

    {:eex,  "install/templates/web/villain/parser.ex",                                    "web/villain/parser.ex"},
    {:eex,  "install/templates/config/brando.exs",                                        "config/brando.exs"},

    {:eex,  "install/templates/migrations/20150123230712_create_users.exs",            "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex,  "install/templates/migrations/20150210211010_create_posts.exs",            "priv/repo/migrations/20150210211010_create_posts.exs"},
    {:eex,  "install/templates/migrations/20150212162739_create_postimages.exs",       "priv/repo/migrations/20150212162739_create_postimages.exs"},
    {:eex,  "install/templates/migrations/20150215090305_create_imagecategories.exs",  "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex,  "install/templates/migrations/20150215090306_create_imageseries.exs",      "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex,  "install/templates/migrations/20150215090307_create_images.exs",           "priv/repo/migrations/20150215090307_create_images.exs"},
    {:eex,  "install/templates/migrations/20150520211010_create_pages.exs",            "priv/repo/migrations/20150520211010_create_pages.exs"},
    {:eex,  "install/templates/migrations/20150520221010_create_pagefragments.exs",    "priv/repo/migrations/20150520221010_create_pagefragments.exs"},
    {:eex,  "install/templates/migrations/20150505122654_create_instagramimages.exs",  "priv/repo/migrations/20150505122654_create_instagramimages.exs"},

    {:eex,  "install/templates/repo/seeds.exs",                                        "priv/repo/seeds.exs"},

    {:text, "install/templates/web/templates/layout/app.html.eex",                     "web/templates/layout/app.html.eex"}
  ]

  @static [
    {:copy, "install/templates/bower.json",                                             "bower.json"},
    {:copy, "install/templates/brunch-config.js",                                       "brunch-config.js"},

    {:copy, "install/templates/web/static/js/cookie_law.js",                            "web/static/vendor/cookie_law.js"},

    {:copy, "install/templates/web/static/css/app.scss",                                "web/static/css/app.scss"},
    {:copy, "install/templates/web/static/css/includes/_colorbox.scss",                 "web/static/css/includes/_colorbox.scss"},
    {:copy, "install/templates/web/static/css/includes/_cookielaw.scss",                "web/static/css/includes/_cookielaw.scss"},
    {:copy, "install/templates/web/static/css/includes/_dropdown.scss",                 "web/static/css/includes/_dropdown.scss"},
    {:copy, "install/templates/web/static/css/includes/_instagram.scss",                "web/static/css/includes/_instagram.scss"},
    {:copy, "install/templates/web/static/css/includes/_nav.scss",                      "web/static/css/includes/_nav.scss"},
    {:copy, "install/templates/web/static/css/includes/_pages.scss",                    "web/static/css/includes/_pages.scss"},

    {:copy, "install/templates/static/brando/css/brando.css",                           "priv/static/css/brando.css"},
    {:copy, "install/templates/static/brando/css/brando-min.css",                       "priv/static/css/brando-min.css"},
    {:copy, "install/templates/static/brando/css/brando.vendor.css",                    "priv/static/css/brando.vendor.css"},
    {:copy, "install/templates/static/brando/css/brando.vendor-min.css",                "priv/static/css/brando.vendor-min.css"},

    {:copy, "install/templates/static/brando/css/maps/brando-min.css.map",              "priv/static/css/maps/brando-min.css.map"},
    {:copy, "install/templates/static/brando/css/maps/brando.css.map",                  "priv/static/css/maps/brando.css.map"},

    {:copy, "install/templates/static/brando/js/brando-min.js",                         "priv/static/js/brando-min.js"},
    {:copy, "install/templates/static/brando/js/brando.auth-min.js",                    "priv/static/js/brando.auth-min.js"},
    {:copy, "install/templates/static/brando/js/brando.auth.js",                        "priv/static/js/brando.auth.js"},
    {:copy, "install/templates/static/brando/js/brando.js",                             "priv/static/js/brando.js"},
    {:copy, "install/templates/static/brando/js/brando.vendor-min.js",                  "priv/static/js/brando.vendor-min.js"},
    {:copy, "install/templates/static/brando/js/brando.vendor.js",                      "priv/static/js/brando.vendor.js"},

    {:copy, "install/templates/static/brando/js/maps/brando-min.js.map",                "priv/static/js/maps/brando-min.js.map"},
    {:copy, "install/templates/static/brando/js/maps/brando.auth-min.js.map",           "priv/static/js/maps/brando.auth-min.js.map"},
    {:copy, "install/templates/static/brando/js/maps/brando.vendor-min.js.map",         "priv/static/js/maps/brando.vendor-min.js.map"},

    {:copy, "install/templates/static/brando/fonts/fontawesome-webfont.eot",            "priv/static/fonts/fontawesome-webfont.eot"},
    {:copy, "install/templates/static/brando/fonts/fontawesome-webfont.svg",            "priv/static/fonts/fontawesome-webfont.svg"},
    {:copy, "install/templates/static/brando/fonts/fontawesome-webfont.ttf",            "priv/static/fonts/fontawesome-webfont.ttf"},
    {:copy, "install/templates/static/brando/fonts/fontawesome-webfont.woff",           "priv/static/fonts/fontawesome-webfont.woff"},
    {:copy, "install/templates/static/brando/fonts/fontawesome-webfont.woff2",          "priv/static/fonts/fontawesome-webfont.woff2"},
    {:copy, "install/templates/static/brando/fonts/FontAwesome.otf",                    "priv/static/fonts/FontAwesome.otf"},

    {:copy, "install/templates/static/brando/fonts/ab.woff",                            "priv/static/fonts/ab.woff"},
    {:copy, "install/templates/static/brando/fonts/am.woff",                            "priv/static/fonts/am.woff"},
    {:copy, "install/templates/static/brando/fonts/ar.woff",                            "priv/static/fonts/ar.woff"},

    {:copy, "install/templates/static/brando/images/blank.gif",                         "priv/static/images/brando/blank.gif"},
    {:copy, "install/templates/static/brando/images/flags.png",                         "priv/static/images/brando/flags.png"},
    {:copy, "install/templates/static/brando/images/brando-big.png",                    "priv/static/images/brando/brando-big.png"},

    {:copy, "install/templates/static/brando/images/defaults/thumb/avatar_default.jpg", "priv/static/images/brando/defaults/thumb/avatar_default.jpg"},
    {:copy, "install/templates/static/brando/images/defaults/micro/avatar_default.jpg", "priv/static/images/brando/defaults/micro/avatar_default.jpg"},

    {:copy, "install/templates/static/villain/villain.all-min.js",                      "priv/static/js/villain.all-min.js"},
    {:copy, "install/templates/static/villain/villain.css",                             "priv/static/css/villain.css"},
    {:copy, "install/templates/static/villain/villain-min.css",                         "priv/static/css/villain-min.css"},
    {:copy, "install/templates/static/villain/villain.css.map",                         "priv/static/css/villain.css.map"},
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
    binding = [application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
               application_name: Atom.to_string(app)]

    copy_from "./", binding, @new

    static? = if opts[:static] == true do
      true
    else
      Mix.shell.yes?("\nInstall static files?")
    end
    if static? do
      copy_from "./", binding, @static
    end

    Mix.shell.info "\nBrando finished copying."
  end

  defp copy_from(target_dir, binding, mapping) when is_list(mapping) do
    application_name = Keyword.fetch!(binding, :application_name)
    for {format, source, target_path} <- mapping do
      target = Path.join(target_dir, String.replace(target_path, "application_name", application_name))
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