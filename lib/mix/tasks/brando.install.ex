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

  root = Path.expand("../../../priv/install/templates", __DIR__)

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