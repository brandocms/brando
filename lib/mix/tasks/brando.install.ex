defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  import Mix.Generator

  @moduledoc """
  Install Brando.
  """

  @shortdoc "Generates files for Brando."

  @new [
    {:eex,  "install/templates/web/villain/parser.ex",                                    "web/villain/parser.ex"},
    {:eex,  "install/templates/config/brando.exs",                                        "config/brando.exs"},
    {:text, "install/templates/media/defaults/thumb/avatar_default.jpg",                  "priv/media/defaults/thumb/avatar_default.jpg"},
    {:eex,  "install/templates/migrations/20150123230712_add_users_table.exs",            "priv/repo/migrations/20150123230712_add_users_table.exs"},
    {:eex,  "install/templates/migrations/20150210211010_add_posts_table.exs",            "priv/repo/migrations/20150210211010_add_posts_table.exs"},
    {:eex,  "install/templates/migrations/20150212162739_add_postimages_table.exs",       "priv/repo/migrations/20150212162739_add_postimages_table.exs"},
    {:eex,  "install/templates/migrations/20150215090305_add_imagecategories_table.exs",  "priv/repo/migrations/20150215090305_add_imagecategories_table.exs"},
    {:eex,  "install/templates/migrations/20150215090306_add_imageseries_table.exs",      "priv/repo/migrations/20150215090306_add_imageseries_table.exs"},
    {:eex,  "install/templates/migrations/20150215090307_add_images_table.exs",           "priv/repo/migrations/20150215090307_add_images_table.exs"},
    {:eex,  "install/templates/migrations/20150520211010_add_pages_table.exs",            "priv/repo/migrations/20150520211010_add_pages_table.exs"},
    {:eex,  "install/templates/migrations/20150520221010_add_pagefragments_table.exs",    "priv/repo/migrations/20150520221010_add_pagefragments_table.exs"}
  ]

  @static [
    {:copy, "install/templates/bower.json", "bower.json"},
    {:copy, "install/templates/brunch-config.js", "brunch-config.js"},

    {:copy, "install/templates/web/static/js/cookie_law.js", "web/static/vendor/cookie_law.js"},

    {:copy, "static/brando/css/brando.css", "priv/static/brando/css/brando.css"},
    {:copy, "static/brando/css/brando-min.css", "priv/static/brando/css/brando-min.css"},
    {:copy, "static/brando/css/brando.vendor.css", "priv/static/brando/css/brando.vendor.css"},
    {:copy, "static/brando/css/brando.vendor-min.css", "priv/static/brando/css/brando.vendor-min.css"},

    {:copy, "static/brando/js/brando-min.js", "priv/static/brando/js/brando-min.js"},
    {:copy, "static/brando/js/brando-min.js.map", "priv/static/brando/js/brando-min.js.map"},
    {:copy, "static/brando/js/brando.auth-min.js", "priv/static/brando/js/brando.auth-min.js"},
    {:copy, "static/brando/js/brando.auth.js", "priv/static/brando/js/brando.auth.js"},
    {:copy, "static/brando/js/brando.js", "priv/static/brando/js/brando.js"},
    {:copy, "static/brando/js/brando.vendor-min.js", "priv/static/brando/js/brando.vendor-min.js"},
    {:copy, "static/brando/js/brando.vendor.js", "priv/static/brando/js/brando.vendor.js"},

    {:copy, "static/brando/js/markdown.min.js", "priv/static/brando/js/markdown.min.js"},
    {:copy, "static/brando/js/to-markdown.js", "priv/static/brando/js/to-markdown.js"},
    {:copy, "static/brando/js/libs/backbone/backbone.js", "priv/static/brando/js/libs/backbone/backbone.js"},
    {:copy, "static/brando/js/libs/backbone/underscore.js", "priv/static/brando/js/libs/backbone/underscore.js"},

    {:copy, "static/brando/fonts/fontawesome-webfont.eot", "priv/static/brando/fonts/fontawesome-webfont.eot"},
    {:copy, "static/brando/fonts/fontawesome-webfont.svg", "priv/static/brando/fonts/fontawesome-webfont.svg"},
    {:copy, "static/brando/fonts/fontawesome-webfont.ttf", "priv/static/brando/fonts/fontawesome-webfont.ttf"},
    {:copy, "static/brando/fonts/fontawesome-webfont.woff", "priv/static/brando/fonts/fontawesome-webfont.woff"},
    {:copy, "static/brando/fonts/fontawesome-webfont.woff2", "priv/static/brando/fonts/fontawesome-webfont.woff2"},
    {:copy, "static/brando/fonts/FontAwesome.otf", "priv/static/brando/fonts/FontAwesome.otf"},

    {:copy, "static/brando/img/blank.gif", "priv/static/brando/img/blank.gif"},
    {:copy, "static/brando/img/flags.png", "priv/static/brando/img/flags.png"},
    {:copy, "static/brando/img/brando-big.png", "priv/static/brando/img/brando-big.png"},

    {:copy, "static/villain/villain-min.css", "priv/static/villain/villain-min.css"},
    {:copy, "static/villain/villain.all-min.js", "priv/static/villain/villain.all-min.js"},
    {:copy, "static/villain/villain.css", "priv/static/villain/villain.css"},
    {:copy, "static/villain/villain.css.map", "priv/static/villain/villain.css.map"},
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
    run(args, nil)
  end
  @doc """
  Copies Brando files from template and static directories to OTP app.
  """
  def run(_, _opts) do
    app = Mix.Project.config()[:app]
    binding = [application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
               application_name: Atom.to_string(app)]

    copy_from "./", binding, @new
    copy_from "./", binding, @static

    Mix.shell.info """
    ------------------------------------------------------------------
    Brando finished copying.
    ------------------------------------------------------------------
    """
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