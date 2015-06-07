defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  import Mix.Generator

  @moduledoc """
  Install Brando.
  """

  @shortdoc "Generates files for Brando."

  @new [
    {:eex,  "web/villain/parser.ex",                                    "web/villain/parser.ex"},
    {:eex,  "config/brando.exs",                                        "config/brando.exs"},
    {:text, "media/defaults/thumb/avatar_default.jpg",                  "priv/media/defaults/thumb/avatar_default.jpg"},
    {:eex,  "migrations/20150123230712_add_users_table.exs",            "priv/repo/migrations/20150123230712_add_users_table.exs"},
    {:eex,  "migrations/20150210211010_add_posts_table.exs",            "priv/repo/migrations/20150210211010_add_posts_table.exs"},
    {:eex,  "migrations/20150212162739_add_postimages_table.exs",       "priv/repo/migrations/20150212162739_add_postimages_table.exs"},
    {:eex,  "migrations/20150215090305_add_imagecategories_table.exs",  "priv/repo/migrations/20150215090305_add_imagecategories_table.exs"},
    {:eex,  "migrations/20150215090306_add_imageseries_table.exs",      "priv/repo/migrations/20150215090306_add_imageseries_table.exs"},
    {:eex,  "migrations/20150215090307_add_images_table.exs",           "priv/repo/migrations/20150215090307_add_images_table.exs"},
    {:eex,  "migrations/20150520211010_add_pages_table.exs",            "priv/repo/migrations/20150520211010_add_pages_table.exs"},
    {:eex,  "migrations/20150520221010_add_pagefragments_table.exs",    "priv/repo/migrations/20150520221010_add_pagefragments_table.exs"}
  ]

  @static [
    {:text, "brando/css/brando.css", "priv/static/brando/css/brando.css"},
    {:text, "brando/css/brando-min.css", "priv/static/brando/css/brando-min.css"},
    {:text, "brando/css/brando.vendor.css", "priv/static/brando/css/brando.vendor.css"},
    {:text, "brando/css/brando.vendor-min.css", "priv/static/brando/css/brando.vendor-min.css"},

    {:text, "brando/js/brando-min.js", "priv/static/brando/js/brando-min.js"},
    {:text, "brando/js/brando-min.js.map", "priv/static/brando/js/brando-min.js.map"},
    {:text, "brando/js/brando.auth-min.js", "priv/static/brando/js/brando.auth-min.js"},
    {:text, "brando/js/brando.auth.js", "priv/static/brando/js/brando.auth.js"},
    {:text, "brando/js/brando.js", "priv/static/brando/js/brando.js"},
    {:text, "brando/js/brando.vendor-min.js", "priv/static/brando/js/brando.vendor-min.js"},
    {:text, "brando/js/brando.vendor.js", "priv/static/brando/js/brando.vendor.js"},

    # These are villain deps. Hopefully we can shed these in the future.
    {:text, "brando/js/markdown.min.js", "priv/static/brando/js/markdown.min.js"},
    {:text, "brando/js/to-markdown.js", "priv/static/brando/js/to-markdown.js"},
    {:text, "brando/js/libs/backbone/backbone.js", "priv/static/brando/js/libs/backbone/backbone.js"},
    {:text, "brando/js/libs/backbone/underscore.js", "priv/static/brando/js/libs/backbone/underscore.js"},

    {:text, "brando/fonts/fontawesome-webfont.eot", "priv/static/brando/fonts/fontawesome-webfont.eot"},
    {:text, "brando/fonts/fontawesome-webfont.svg", "priv/static/brando/fonts/fontawesome-webfont.svg"},
    {:text, "brando/fonts/fontawesome-webfont.ttf", "priv/static/brando/fonts/fontawesome-webfont.ttf"},
    {:text, "brando/fonts/fontawesome-webfont.woff", "priv/static/brando/fonts/fontawesome-webfont.woff"},
    {:text, "brando/fonts/fontawesome-webfont.woff2", "priv/static/brando/fonts/fontawesome-webfont.woff2"},
    {:text, "brando/fonts/FontAwesome.otf", "priv/static/brando/fonts/FontAwesome.otf"},

    {:text, "brando/img/blank.gif", "priv/static/brando/img/blank.gif"},
    {:text, "brando/img/flags.png", "priv/static/brando/img/flags.png"},
    {:text, "brando/img/brando-big.png", "priv/static/brando/img/brando-big.png"},

    {:text, "villain/villain-min.css", "priv/static/villain/villain-min.css"},
    {:text, "villain/villain-min.js", "priv/static/villain/villain-min.js"},
    {:text, "villain/villain.css", "priv/static/villain/villain.css"},
    {:text, "villain/villain.css.map", "priv/static/villain/villain.css.map"},
    {:text, "villain/villain.js", "priv/static/villain/villain.js"},
  ]

  root = Path.expand("../../../priv/install/templates", __DIR__)
  static_root = Path.expand("../../../priv/static", __DIR__)

  for {format, source, _} <- @new do
    unless format == :keep do
      @external_resource Path.join(root, source)
      def render(unquote(source)), do: unquote(File.read!(Path.join(root, source)))
    end
  end

  for {format, source, _} <- @static do
    unless format == :keep do
      @external_resource Path.join(static_root, source)
      def render(unquote(source)), do: unquote(File.read!(Path.join(static_root, source)))
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
        :eex  -> contents = EEx.eval_string(render(source), binding, file: source)
                 create_file(target, contents)
      end
    end
  end
end