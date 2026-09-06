defmodule Mix.Brando.Install.Templates do
  @moduledoc false

  @new [
    # Mix template
    {:eex, "mix.exs", "mix.exs"},

    # VERSION
    {:eex, "VERSION", "VERSION"},

    # README
    {:eex, "README.md", "README.md"},

    # Formatter
    {:eex, "formatter.exs", ".formatter.exs"},

    # Release cfg & setup
    {:eex, ".envrc", ".envrc"},
    {:eex, ".envrc.prod", ".envrc.prod"},
    {:eex, ".envrc.staging", ".envrc.staging"},
    {:eex, "rel/env.sh.eex", "rel/env.sh.eex"},
    {:eex, "rel/vm.args.eex", "rel/vm.args.eex"},
    {:eex, "lib/application_name/release_tasks.ex", "lib/application_name/release_tasks.ex"},

    # Brando migrator
    {:eex, "lib/mix/brando.upgrade.ex", "lib/mix/brando.upgrade.ex"},

    # Application-owned migrations for named environment schemas
    {:keep, "tenant_migrations", "priv/repo/tenant_migrations"},
    {:eex, "tenant_migrations/20260816002300_add_shared_content_library.exs",
     "priv/repo/tenant_migrations/20260816002300_add_shared_content_library.exs"},

    # Etc. Various OS config files and log directory.
    {:keep, "log", "log"},
    {:eex, "etc/pgbkup.sh", "etc/pgbkup.sh"},
    {:eex, "etc/logrotate/prod.conf", "etc/logrotate/prod.conf"},
    {:eex, "etc/logrotate/staging.conf", "etc/logrotate/staging.conf"},
    {:eex, "etc/nginx/prod.conf", "etc/nginx/prod.conf"},
    {:eex, "etc/nginx/staging.conf", "etc/nginx/staging.conf"},
    {:eex, "etc/nginx/502.html", "etc/nginx/502.html"},
    {:eex, "etc/systemd/prod.service", "etc/systemd/prod.service"},
    {:eex, "etc/systemd/staging.service", "etc/systemd/staging.service"},

    # Main application file
    {:eex, "lib/application_name/application.ex", "lib/application_name/application.ex"},

    # Tuple implementation for Jason
    {:eex, "lib/application_name/tuple.ex", "lib/application_name/tuple.ex"},

    # Presence
    {:eex, "lib/application_name/presence.ex", "lib/application_name/presence.ex"},

    # Router template
    {:eex, "lib/application_name_web/router.ex", "lib/application_name_web/router.ex"},

    # Lockdown files
    {:eex, "lib/application_name_web/controllers/lockdown_controller.ex",
     "lib/application_name_web/controllers/lockdown_controller.ex"},
    {:eex, "lib/application_name_web/components/layouts/lockdown.html.heex",
     "lib/application_name_web/components/layouts/lockdown.html.heex"},
    {:eex, "lib/application_name_web/controllers/lockdown_html/index.html.heex",
     "lib/application_name_web/controllers/lockdown_html/index.html.heex"},
    {:eex, "lib/application_name_web/controllers/lockdown_html.ex",
     "lib/application_name_web/controllers/lockdown_html.ex"},

    # Page files
    {:eex, "lib/application_name_web/controllers/page_controller.ex",
     "lib/application_name_web/controllers/page_controller.ex"},
    {:eex, "lib/application_name_web/controllers/page_html.ex", "lib/application_name_web/controllers/page_html.ex"},
    {:eex, "lib/application_name_web/controllers/page_html/index.html.heex",
     "lib/application_name_web/controllers/page_html/index.html.heex"},
    {:eex, "lib/application_name_web/controllers/page_html/default.html.heex",
     "lib/application_name_web/controllers/page_html/default.html.heex"},

    # Fallback and errors
    {:eex, "lib/application_name_web/controllers/fallback_controller.ex",
     "lib/application_name_web/controllers/fallback_controller.ex"},
    {:eex, "lib/application_name_web/controllers/error_html.ex", "lib/application_name_web/controllers/error_html.ex"},
    {:eex, "lib/application_name_web/controllers/error_html/404.html.heex",
     "lib/application_name_web/controllers/error_html/404.html.heex"},
    {:eex, "lib/application_name_web/controllers/error_html/500.html.heex",
     "lib/application_name_web/controllers/error_html/500.html.heex"},

    # Partials
    {:eex, "lib/application_name_web/components/partials/navigation.html.heex",
     "lib/application_name_web/components/partials/navigation.html.heex"},
    {:eex, "lib/application_name_web/components/partials/footer.html.heex",
     "lib/application_name_web/components/partials/footer.html.heex"},
    {:eex, "lib/application_name_web/components/partials/logo.html.heex",
     "lib/application_name_web/components/partials/logo.html.heex"},

    # Default Villain parser & filters
    {:eex, "lib/application_name_web/villain/parser.ex", "lib/application_name_web/villain/parser.ex"},
    {:eex, "lib/application_name_web/villain/filters.ex", "lib/application_name_web/villain/filters.ex"},

    # E2E test setup
    {:eex, "lib/application_name/factory.ex", "lib/application_name/factory.ex"},
    {:eex, "test/e2e/test_helper.exs", "test/e2e/test_helper.exs"},

    # Default configuration files
    {:eex, "config/brando.exs", "config/brando.exs"},
    {:eex, "config/config.exs", "config/config.exs"},
    {:eex, "config/dev.exs", "config/dev.exs"},
    {:eex, "config/e2e.exs", "config/e2e.exs"},
    {:eex, "config/prod.exs", "config/prod.exs"},
    {:eex, "config/staging.exs", "config/staging.exs"},
    {:eex, "config/runtime.exs", "config/runtime.exs"},

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

    # Repo seeds
    {:eex, "repo/seeds.exs", "priv/repo/seeds.exs"},

    # Layouts
    {:eex, "lib/application_name_web/components/layouts.ex", "lib/application_name_web/components/layouts.ex"},
    {:eex, "lib/application_name_web/components/layouts/app.html.heex",
     "lib/application_name_web/components/layouts/app.html.heex"},
    {:eex, "lib/application_name_web/components/layouts/bare.html.heex",
     "lib/application_name_web/components/layouts/bare.html.heex"},

    # Gettext templates
    {:keep, "priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex, "lib/application_name_web/gettext.ex", "lib/application_name_web/gettext.ex"},

    # Endpoint
    {:eex, "lib/application_name_web/endpoint.ex", "lib/application_name_web/endpoint.ex"},

    # Repo
    {:eex, "lib/application_name/repo.ex", "lib/application_name/repo.ex"},

    # Authorization
    {:eex, "lib/application_name/authorization.ex", "lib/application_name/authorization.ex"},

    # Telemetry
    {:eex, "lib/application_name_web/telemetry.ex", "lib/application_name_web/telemetry.ex"},

    # Live Preview
    {:eex, "lib/application_name_web/live_preview.ex", "lib/application_name_web/live_preview.ex"},

    # Admin
    {:eex, "lib/application_name_admin/menus.ex", "lib/application_name_admin/menus.ex"},
    {:eex, "lib/application_name_admin/live/dashboard_live.ex", "lib/application_name_admin/live/dashboard_live.ex"}
  ]

  @static [
    # Deployment tools
    {:copy, "gitignore", ".gitignore"},
    {:copy, "dockerignore", ".dockerignore"},
    {:copy, "Dockerfile", "Dockerfile"},
    {:copy, "fabfile.py", "fabfile.py"},
    {:eex, "deployment.cfg", "deployment.cfg"},
    {:eex, "scripts/sync_media_from_local_to_remote.sh", "scripts/sync_media_from_local_to_remote.sh"},
    {:eex, "scripts/sync_media_from_remote_to_local.sh", "scripts/sync_media_from_remote_to_local.sh"},

    # Backend tooling
    {:copy, "assets/backend/europa.config.cjs", "assets/backend/europa.config.cjs"},
    {:copy, "assets/backend/package.json", "assets/backend/package.json"},
    {:copy, "assets/backend/postcss.config.cjs", "assets/backend/postcss.config.cjs"},
    {:copy, "assets/backend/README.md", "assets/backend/README.md"},
    {:copy, "assets/backend/svelte.config.cjs", "assets/backend/svelte.config.cjs"},
    {:copy, "assets/backend/vite.config.js", "assets/backend/vite.config.js"},

    # Backend resources
    {:copy, "assets/backend/public/favicon.ico", "assets/backend/public/favicon.ico"},
    {:copy, "assets/backend/public/fonts/Mono.woff2", "assets/backend/public/fonts/Mono.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Light.woff2", "assets/backend/public/fonts/Main-Light.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Medium.woff2", "assets/backend/public/fonts/Main-Medium.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Regular.woff2", "assets/backend/public/fonts/Main-Regular.woff2"},
    {:copy, "assets/backend/public/images/admin/avatar.svg", "assets/backend/public/images/admin/avatar.svg"},

    # Backend src
    {:copy, "assets/backend/src/main.js", "assets/backend/src/main.js"},
    {:copy, "assets/backend/css/app.css", "assets/backend/css/app.css"},
    {:copy, "assets/backend/css/blocks.css", "assets/backend/css/blocks.css"},

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
    {:copy, "assets/frontend/css/includes/cookies.css", "assets/frontend/css/includes/cookies.css"},
    {:copy, "assets/frontend/css/includes/fonts.css", "assets/frontend/css/includes/fonts.css"},
    {:copy, "assets/frontend/css/includes/modules.css", "assets/frontend/css/includes/modules.css"},
    {:copy, "assets/frontend/css/includes/navigation.css", "assets/frontend/css/includes/navigation.css"},

    # Frontend JS

    {:keep, "assets/frontend/js/modules", "assets/frontend/js/modules"},
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
