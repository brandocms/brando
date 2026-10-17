defmodule Mix.Brando.Install.Templates do
  @moduledoc false

  @new [
    # Release environment files (Mix.Brando.Igniter.Install.Deployment)
    {:eex, ".envrc.prod", ".envrc.prod"},
    {:eex, ".envrc.staging", ".envrc.staging"},
    {:eex, "rel/env.sh.eex", "rel/env.sh.eex"},
    {:eex, "lib/application_name/release_tasks.ex", "lib/application_name/release_tasks.ex"},

    # Application-owned migrations for named environment schemas
    {:keep, "tenant_migrations", "priv/repo/tenant_migrations"},
    {:eex, "tenant_migrations/20260816002300_add_shared_content_library.exs",
     "priv/repo/tenant_migrations/20260816002300_add_shared_content_library.exs"},

    # Presence
    {:eex, "lib/application_name/presence.ex", "lib/application_name/presence.ex"},

    # Default Villain parser & filters
    {:eex, "lib/application_name_web/villain/parser.ex", "lib/application_name_web/villain/parser.ex"},
    {:eex, "lib/application_name_web/villain/filters.ex", "lib/application_name_web/villain/filters.ex"},

    # The Brando.Images defaults the installer configures
    {:eex, "config/brando.exs", "config/brando.exs"},

    # Tables that predate versioned Brando migrations
    {:eex, "migrations/20150123230712_create_users.exs", "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex, "migrations/20150215090305_create_imagecategories.exs",
     "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex, "migrations/20150215090306_create_imageseries.exs",
     "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex, "migrations/20150215090307_create_images.exs", "priv/repo/migrations/20150215090307_create_images.exs"},
    {:eex, "migrations/20171103152200_create_pages.exs", "priv/repo/migrations/20171103152200_create_pages.exs"},
    {:eex, "migrations/20171103152205_create_pagefragments.exs",
     "priv/repo/migrations/20171103152205_create_pagefragments.exs"},
    {:eex, "migrations/20190426105600_create_templates.exs", "priv/repo/migrations/20190426105600_create_templates.exs"},

    # Authorization
    {:eex, "lib/application_name/authorization.ex", "lib/application_name/authorization.ex"},

    # Admin
    {:eex, "lib/application_name_admin/menus.ex", "lib/application_name_admin/menus.ex"},
    {:eex, "lib/application_name_admin/live/dashboard_live.ex", "lib/application_name_admin/live/dashboard_live.ex"}
  ]

  @static [
    # Deployment tools
    {:copy, "dockerignore", ".dockerignore"},
    {:copy, "Dockerfile", "Dockerfile"},

    # The toolchain, for asdf and mise (Mix.Brando.Igniter.Install)
    {:copy, "tool-versions", ".tool-versions"},

    # Backend tooling
    {:copy, "assets/backend/europa.json5", "assets/backend/europa.json5"},
    {:copy, "assets/backend/package.json", "assets/backend/package.json"},
    {:copy, "assets/backend/README.md", "assets/backend/README.md"},
    {:copy, "assets/backend/vite.config.js", "assets/backend/vite.config.js"},

    # Backend resources
    {:copy, "assets/backend/public/favicon.ico", "assets/backend/public/favicon.ico"},
    {:copy, "assets/backend/public/images/admin/avatar.svg", "assets/backend/public/images/admin/avatar.svg"},

    # Backend src
    {:copy, "assets/backend/src/main.js", "assets/backend/src/main.js"},
    {:copy, "assets/backend/css/app.css", "assets/backend/css/app.css"},

    # Frontend assets
    {:keep, "assets/frontend/public/fonts", "assets/frontend/public/fonts"},
    {:keep, "assets/frontend/public/fonts", "assets/frontend/public/images"},
    {:copy, "assets/frontend/eslint.config.js", "assets/frontend/eslint.config.js"},
    {:copy, "assets/frontend/europa.config.cjs", "assets/frontend/europa.config.cjs"},
    {:copy, "assets/frontend/vite.config.js", "assets/frontend/vite.config.js"},
    {:copy, "assets/frontend/postcss.config.cjs", "assets/frontend/postcss.config.cjs"},
    {:eex, "assets/frontend/package.json", "assets/frontend/package.json"},

    # Frontend static
    {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/favicon.ico"},
    {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/ico/favicon.ico"},

    # Frontend src - CSS
    {:copy, "assets/frontend/css/app.css", "assets/frontend/css/app.css"},
    {:copy, "assets/frontend/css/critical.css", "assets/frontend/css/critical.css"},
    {:copy, "assets/frontend/css/includes/common.css", "assets/frontend/css/includes/common.css"},
    {:copy, "assets/frontend/css/includes/cookies.css", "assets/frontend/css/includes/cookies.css"},
    {:copy, "assets/frontend/css/includes/fonts.css", "assets/frontend/css/includes/fonts.css"},
    {:copy, "assets/frontend/css/includes/footer.css", "assets/frontend/css/includes/footer.css"},
    {:copy, "assets/frontend/css/includes/modules.css", "assets/frontend/css/includes/modules.css"},
    {:copy, "assets/frontend/css/includes/navigation.css", "assets/frontend/css/includes/navigation.css"},

    # Frontend JS

    {:copy, "assets/frontend/js/modules/highlight.js", "assets/frontend/js/modules/highlight.js"},
    {:copy, "assets/frontend/js/index.js", "assets/frontend/js/index.js"},
    {:copy, "assets/frontend/js/critical.js", "assets/frontend/js/critical.js"},
    {:copy, "assets/frontend/js/config/BREAKPOINTS.js", "assets/frontend/js/config/BREAKPOINTS.js"},
    {:copy, "assets/frontend/js/config/MOBILE_MENU.js", "assets/frontend/js/config/MOBILE_MENU.js"},
    {:copy, "assets/frontend/js/config/MOONWALK.js", "assets/frontend/js/config/MOONWALK.js"},
    {:copy, "assets/frontend/js/config/HEADER.js", "assets/frontend/js/config/HEADER.js"}
  ]

  # credo:disable-for-next-line ExSlop.Check.Warning.PathExpandPriv
  @root Path.expand("../../../../priv", __DIR__)

  # Fresh installs must use the same maintained migration templates as upgrades,
  # in their numeric order. The former frozen subset omitted intermediate tables
  # and copied data migrations that still called removed APIs. Timestamps after
  # the initial table migrations keep this deterministic across install dates.
  @brando_migrations @root
                     |> Path.join("templates/brando.upgrade/migrations/*.exs")
                     |> Path.wildcard()
                     |> Enum.map(fn path ->
                       filename = Path.basename(path)
                       [_, sequence] = Regex.run(~r/^brando_(\d+)_/, filename)
                       {String.to_integer(sequence), filename}
                     end)
                     |> Enum.sort_by(&elem(&1, 0))
                     |> Enum.map(fn {sequence, filename} ->
                       version =
                         ~U[2026-01-01 00:00:00Z]
                         |> DateTime.add(sequence, :second)
                         |> Calendar.strftime("%Y%m%d%H%M%S")

                       {:eex, "../brando.upgrade/migrations/#{filename}", "priv/repo/migrations/#{version}_#{filename}"}
                     end)

  @new @new ++ @brando_migrations

  # The list above is read at compile time, so a new migration template would
  # go unseen by `mix brando.gen.migrations` until this module was rebuilt.
  @migration_templates Path.wildcard(Path.join(@root, "templates/brando.upgrade/migrations/*.exs"))

  def __mix_recompile__?,
    do: Path.wildcard(Path.join(@root, "templates/brando.upgrade/migrations/*.exs")) != @migration_templates

  for {format, source, _} <- @new ++ @static do
    if format not in [:keep, :copy] do
      @external_resource Path.join([@root, "templates/brando.install", source])
      def render(unquote(Path.join("templates/brando.install", source))),
        do: unquote(File.read!(Path.join([@root, "templates/brando.install", source])))
    end
  end

  def manifest, do: @new ++ @static

  def contents(:copy, source), do: File.read!(Path.join([@root, "templates/brando.install", source]))
  def contents(:eex, source), do: render(Path.join("templates/brando.install", source))
end
