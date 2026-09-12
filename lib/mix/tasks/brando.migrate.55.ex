if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate55 do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    alias Mix.Brando.Igniter.SourceUpgrade

    @shortdoc "Migrates application source from Brando 0.54 to 0.55"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. Applications still on 0.53 syntax must run
    `mix brando.migrate54` first.

    The task adds the explicit listing component imports, configures Req as
    Swoosh's API client, pins the declared `phoenix_live_view` JavaScript
    dependency, converts a legacy Fabric deployment to a reviewable Florist
    configuration, refreshes the gettext recovery helper, and retires the
    consumer-owned `brando.upgrade` task that 0.54 installed.

    The task changes source files only. Review and compile its diff before
    generating or running database migrations. The complete ordered workflow is
    documented in `guides/migrating_from_053.md`.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    def igniter(igniter) do
      igniter
      |> SourceUpgrade.rewrite_blueprints(&SourceUpgrade.add_listing_component_imports/1)
      |> SourceUpgrade.configure_swoosh_client()
      |> SourceUpgrade.pin_live_view_javascript()
      |> SourceUpgrade.create_florist_config()
      |> SourceUpgrade.refresh_gettext_script()
      |> Mix.Brando.Igniter.Upgrade.prepare()
      |> add_notices()
      |> add_warnings()
    end

    defp add_notices(igniter) do
      Igniter.add_notice(igniter, """
      Brando 0.55 source migration prepared.

      Custom listing rows get the narrow component imports they use. The task
      adds Req as Swoosh's API client when none is configured and pins the
      declared `phoenix_live_view` JavaScript dependency under `assets/` to the
      loaded server version.

      When both legacy `deployment.cfg` and `fabfile.py` exist and no Florist
      configuration exists, the task also creates a reviewable
      `florist.config.exs`. It preserves the legacy single-release/nginx model,
      does not copy passwords, and leaves the legacy files untouched.

      Tenancy remains opt-in. Applications adopting named environments can run
      `mix brando.setup.tenancy` after this general source upgrade to prepare
      their configuration, router pipelines, and tenant migration support.

      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
        2. If `florist.config.exs` was created, set its required password
           environment variables and complete the deployment review in the
           migration guide before running Florist.
        3. Run `mix brando.gen.migrations` to plan missing Brando Ecto migrations.
        4. For every application Blueprint with generated migration history,
           run `mix brando.gen.blueprint_migration MyApp.Domain.Schema`.
        5. Review every generated `up/0` and `down/0`, test rollback/forward,
           and commit the source, migrations, and snapshots together.
        6. Run `mix ecto.migrate` only after that review.
        7. After the database migration, run `mix brando.entries.resave` and
           `mix brando.identifiers.sync`.

      See `guides/migrating_from_053.md` and `guides/blueprint_migrations.md` in
      Brando for the full recovery and rebaseline instructions.
      """)
    end

    defp add_warnings(igniter) do
      Igniter.add_warning(igniter, """
      Manual 0.55 decisions remain:

        * Add `persist_identifier false` to every Blueprint that must not create
          persisted identifiers. Persistence defaults to true.
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
        * Fabric deployments must ensure the application database role owns the
          `oban_job_state` enum before `brando_153` upgrades Oban to v14. Follow
          the changelog's updated `grant_db`/`ALTER TYPE ... OWNER TO` procedure.
        * A generated Florist configuration deliberately retains `:single`
          deployment with nginx. Validate domains, Docker/release paths, remote
          directories, systemd/nginx behavior, the persistent media symlink, and
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
