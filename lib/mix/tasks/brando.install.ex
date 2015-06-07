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

  # @static [
  #   {:text, "static/brando/css/brando.css", "priv/static/brando/css/brando.css"},
  #   {:text, "static/brando/css/brando-min.css", "priv/static/brando/css/brando-min.css"},
  #   {:text, "static/brando/css/brando.vendor.css", "priv/static/brando/css/brando.vendor.css"},
  #   {:text, "static/brando/css/brando.vendor-min.css", "priv/static/brando/css/brando.vendor-min.css"},

  #   {:text, "static/brando/js/brando-min.js", "priv/static/brando/js/brando-min.js"},
  #   {:text, "static/brando/js/brando-min.js.map", "priv/static/brando/js/brando-min.js.map"},
  #   {:text, "static/brando/js/brando.auth-min.js", "priv/static/brando/js/brando.auth-min.js"},
  #   {:text, "static/brando/js/brando.auth.js", "priv/static/brando/js/brando.auth.js"},
  #   {:text, "static/brando/js/brando.js", "priv/static/brando/js/brando.js"},
  #   {:text, "static/brando/js/brando.vendor-min.js", "priv/static/brando/js/brando.vendor-min.js"},
  #   {:text, "static/brando/js/brando.vendor.js", "priv/static/brando/js/brando.vendor.js"},

  #   {:text, "static/brando/js/markdown.min.js", "priv/static/brando/js/markdown.min.js"},
  #   {:text, "static/brando/js/to-markdown.js", "priv/static/brando/js/to-markdown.js"},
  #   {:text, "static/brando/js/libs/backbone/backbone.js", "priv/static/brando/js/libs/backbone/backbone.js"},
  #   {:text, "static/brando/js/libs/backbone/underscore.js", "priv/static/brando/js/libs/backbone/underscore.js"},

  #   {:text, "static/brando/fonts/fontawesome-webfont.eot", "priv/static/brando/fonts/fontawesome-webfont.eot"},
  #   {:text, "static/brando/fonts/fontawesome-webfont.svg", "priv/static/brando/fonts/fontawesome-webfont.svg"},
  #   {:text, "static/brando/fonts/fontawesome-webfont.ttf", "priv/static/brando/fonts/fontawesome-webfont.ttf"},
  #   {:text, "static/brando/fonts/fontawesome-webfont.woff", "priv/static/brando/fonts/fontawesome-webfont.woff"},
  #   {:text, "static/brando/fonts/fontawesome-webfont.woff2", "priv/static/brando/fonts/fontawesome-webfont.woff2"},
  #   {:text, "static/brando/fonts/FontAwesome.otf", "priv/static/brando/fonts/FontAwesome.otf"},

  #   {:text, "static/brando/img/blank.gif", "priv/static/brando/img/blank.gif"},
  #   {:text, "static/brando/img/flags.png", "priv/static/brando/img/flags.png"},
  #   {:text, "static/brando/img/brando-big.png", "priv/static/brando/img/brando-big.png"},

  #   {:text, "static/villain/villain-min.css", "priv/static/villain/villain-min.css"},
  #   {:text, "static/villain/villain-min.js", "priv/static/villain/villain-min.js"},
  #   {:text, "static/villain/villain.css", "priv/static/villain/villain.css"},
  #   {:text, "static/villain/villain.css.map", "priv/static/villain/villain.css.map"},
  #   {:text, "static/villain/villain.js", "priv/static/villain/villain.js"}
  # ]

  root = Path.expand("../../../priv", __DIR__)

  for {format, source, _} <- @new do
    unless format == :keep do
      @external_resource Path.join(root, source)
      def render(unquote(source)), do: unquote(File.read!(Path.join(root, source)))
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
    # copy_from "./", binding, @static

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
        :eex  -> contents = EEx.eval_string(render(source), binding, file: source)
                 create_file(target, contents)
      end
    end
  end
end