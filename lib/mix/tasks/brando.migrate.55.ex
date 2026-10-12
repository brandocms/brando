if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate55 do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    alias Mix.Brando.Igniter.PersistIdentifiers
    alias Mix.Brando.Igniter.Mailer
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.SourceUpgrade.BlueprintGettext
    alias Mix.Brando.Igniter.UpgradeOrder
    alias Mix.Brando.Igniter.SourceUpgrade.ListOrder
    alias Mix.Brando.Igniter.SourceUpgrade.VideoMarkup

    @shortdoc "Migrates application source from Brando 0.54 to 0.55"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. Applications still on 0.53 syntax must run
    `mix brando.migrate54` first.

    The task points references to the modules renamed in 0.55 at their new
    names, adds the explicit listing component imports, gives Villain parsers
    back the `use Phoenix.Component`, imports and aliases they relied on from
    `use Brando.Villain.Parser`, configures Req as
    Swoosh's API client, points Brando at the application's mailer (creating
    `MyApp.Mailer`, its development and test adapters and a placeholder
    sender when the application has none), adds
    `Brando.Plug.Markdown` and `Brando.Plug.IndexNow` to the endpoint, removes the
    retired Sharp image processor from config, pins the declared `phoenix_live_view` JavaScript
    dependency, builds Vite source maps `hidden`, converts a legacy Fabric deployment to a reviewable Florist
    configuration, refreshes the gettext recovery helper, copies the
    translations of each Blueprint's 0.53 `_naming`, `_forms` and `_listings`
    Gettext domains into the domain 0.55 extracts to, along with the `default`
    domain's translations of the Blueprint's `t/1` labels, sets
    `persist_identifier false` on Blueprints with no admin editor, completes
    `Plural-Forms` headers Gettext 1.0 warns about, and retires the
    consumer-owned `brando.upgrade` task that 0.54 installed.

    Calls to the application's `list_<plural>/1` queries whose options order
    a Sequenced Blueprint only by `sequence` get the admin listing's
    tiebreak, `order: "asc sequence, desc inserted_at"`. The 0.55 data
    migrations rewrite rows, and rows with equal `sequence` came back in
    storage order. Calls with no `order:` at all are listed, since adding one
    changes what the site shows.

    It also lists, without changing them, front-end scripts under `assets/`
    that read a video's `data-src`, which 0.55 moved from the `<video>` to
    its `[data-smart-video]` wrapper.

    The task changes source files only. Review and compile its diff before
    generating or running database migrations. The complete ordered workflow is
    documented in `guides/migrating_from_053.md`; the task's closing notice
    lists its remaining steps in that order, and in the guide's "Legacy
    snapshots" order (Brando's migrations, then the Blueprint migrations with
    `--reconcile`) when the newest copied Brando migration is `brando_102` or
    older, or a Blueprint's latest snapshot still has a Villain field.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    # Loads dependencies and configuration only; the application's source is
    # what this task fixes, so it may not compile yet.
    @impl Mix.Task
    def run(argv), do: Mix.Brando.Igniter.SourceTask.run(__MODULE__, argv)

    def igniter(igniter) do
      igniter
      |> SourceUpgrade.rewrite_blueprints(&SourceUpgrade.add_listing_component_imports/1)
      |> SourceUpgrade.update_villain_parsers()
      |> SourceUpgrade.rename_moved_modules()
      |> SourceUpgrade.configure_swoosh_client()
      |> Mailer.configure_for_upgrade()
      |> SourceUpgrade.remove_sharp_processor()
      |> SourceUpgrade.pin_live_view_javascript()
      |> SourceUpgrade.hide_source_maps()
      |> SourceUpgrade.create_florist_config()
      |> SourceUpgrade.add_content_plugs()
      |> SourceUpgrade.refresh_gettext_script()
      |> SourceUpgrade.carry_blueprint_translations()
      |> BlueprintGettext.carry_default_translations()
      |> SourceUpgrade.complete_plural_forms_headers()
      |> SourceUpgrade.warn_image_text_reads()
      |> PersistIdentifiers.update()
      |> VideoMarkup.warn_video_data_src_reads()
      |> ListOrder.order_list_queries()
      |> SourceUpgrade.start_endpoint_last()
      |> Mix.Brando.Igniter.Upgrade.prepare()
      |> add_notices()
      |> add_warnings()
    end

    defp add_notices(igniter) do
      {igniter, order} = UpgradeOrder.notice(igniter)

      Igniter.add_notice(igniter, """
      Brando 0.55 source migration prepared.

      References to the modules renamed in 0.55 (`Brando.SEOController`,
      `Brando.UserChannel` and the rest; see UPGRADE.md) now
      use the new names. Custom listing rows get the narrow component
      imports they use, and
      Villain parsers get back the `use Phoenix.Component`, `Brando.HTML` and
      `Phoenix.HTML` imports, and aliases they used, which
      `use Brando.Villain.Parser` no longer brings in. The task
      adds Req as Swoosh's API client when none is configured, points Brando at
      the application's `Mailer`, creating one when it has none, and pins the
      declared `phoenix_live_view` JavaScript dependency under `assets/` to the
      loaded server version. Vite configs under `assets/` that set
      `sourcemap: true` now build hidden maps, and `mix brando.digest` deletes
      them before release. See the Docker build section of
      `guides/deployment.md` to upload them to Sentry instead.

      Translations in each Blueprint's 0.53 Gettext domains
      (`<domain>_<schema>_naming`, `_forms`, `_listings`) are copied into
      `<domain>_<schema>.po`, the domain 0.55 extracts to, so
      `mix brando.gettext.reconcile` keeps them. So are the `default` domain's
      translations of the Blueprint's `t/1` labels, which were extracted
      there while they were written with `gettext/1`; a translation the
      schema's catalog has is kept.

      Calls to the application's `list_<plural>/1` queries that order a
      Sequenced Blueprint only by `sequence` now order by
      `"asc sequence, desc inserted_at"`, as the admin listing does, so
      entries with equal `sequence` no longer come back in storage order,
      which the data migrations change.

      The endpoint gets `plug Brando.Plug.Markdown` (entries as Markdown at
      their URL + `.md`) and `plug Brando.Plug.IndexNow` (the IndexNow key
      file), before the router, unless it has them.

      When both legacy `deployment.cfg` and `fabfile.py` exist and no Florist
      configuration exists, the task also creates a reviewable
      `florist.config.exs`. It preserves the legacy single-release/nginx model,
      takes domains and ports the legacy `.envrc.<flavor>`, `etc/nginx` and
      `etc/supervisord`/`etc/systemd` files name, does not copy passwords, and
      leaves the legacy files untouched. It adds `plug Brando.Plug.Health` to
      the endpoint, before the router, because Florist checks `/health`.

      Tenancy remains opt-in. Applications adopting named environments can run
      `mix brando.setup.tenancy` after this general source upgrade to prepare
      their configuration, router pipelines, and tenant migration support.

      #{order}
      See `guides/migrating_from_053.md` and `guides/blueprint_migrations.md` in
      Brando for the full recovery and rebaseline instructions.
      """)
    end

    defp add_warnings(igniter) do
      Igniter.add_warning(igniter, """
      Manual 0.55 decisions remain:

        * Add `persist_identifier false` to every other Blueprint that must not
          create persisted identifiers. Persistence defaults to true. The task
          sets it on Blueprints with no admin editor (no
          `admin_<singular>_form_path` route for `:update` and no admin
          LiveView) and no `absolute_url`, whose entries cannot be opened from
          Search, the command palette or the dashboard; its notice lists them.
        * Table, primary-key, and existing column-level primary-key changes are
          never inferred. Write the Ecto migration, verify the live schema, then
          use the documented Blueprint `--rebaseline` workflow.
        * Update code that traverses generated `*_identifiers` associations for
          `:entries` relations. The relation now exposes its join entries
          directly, and application query/preload intent cannot be inferred.
        * The task pins declared `phoenix_live_view` dependencies in
          `assets/**/package.json` to the loaded server version. Review any
          nonstandard frontend manifest, refresh the package-manager lockfile,
          and rebuild assets. If application code directly uses Hackney, add it
          explicitly; the Req Swoosh default only replaces Swoosh's client.
        * Custom admin components must repoint form primitives and image, file,
          and video drawer calls from `BrandoAdmin.Components.Form` to
          `Form.Primitives`, `Form.ImageDrawer`, `Form.FileDrawer`, or
          `Form.VideoDrawer` as documented. Markup aliases and local component
          names are application-specific, so the task does not guess them.
        * Review callers of `Brando.Videos.Uploader.initiate_upload/3`, provider
          credential failures, and `Brando.CDN.key_exists?/2`. The CDN replacement
          is `key_available?/2` with inverted and deliberately safer error
          semantics; a mechanical function rename would be unsafe.
        * Move function-based asset `config_target` callbacks from helper modules
          onto their Blueprint schema. The hardened resolver rejects plain helper
          modules and there is no safe target schema the task can choose.
        * Brando now sends email through the application's Swoosh mailer
          (`config :brando, mailer: MyApp.Mailer`; this task creates one when
          the application has none). Set the address it sends from, which the
          mail provider must accept, in place of any `noreply@example.com`
          placeholder: `config :brando, Brando.Mailer, from: {"My site", "noreply@my-site.com"}`,
          and the mailer's production adapter in `config/runtime.exs`.
        * Fabric deployments must ensure the application database role owns the
          `oban_job_state` enum before `brando_153` upgrades Oban to v14. Follow
          the changelog's updated `grant_db`/`ALTER TYPE ... OWNER TO` procedure.
        * A generated Florist configuration deliberately retains `:single`
          deployment with nginx. Validate domains, Docker/release paths, remote
          directories, systemd or supervisord and nginx behavior, the persistent media symlink, and
          database backups before replacing Fabric. Opt into blue/green only as
          a separately rehearsed deployment change. Legacy rclone credentials
          and bucket paths are never inferred.
      """)
    end
  end
else
  defmodule Mix.Tasks.Brando.Migrate55 do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)

    @shortdoc "Migrates a Brando 0.54 application to 0.55 (requires igniter)"
    @moduledoc """
    #{@shortdoc}.

    This task is built on Igniter, an optional Brando dependency. Add it to your
    application's deps, run `mix deps.get`, then recompile Brando with
    `mix deps.compile brando --force` to enable the task.
    """

    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.migrate55")
  end
end
