if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.BlueprintMigration do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task
    @shortdoc "Plans a reversible Blueprint migration and snapshot for review"
    @moduledoc """
    Plans storage changes from an accepted, compiled Blueprint using Igniter.

        mix brando.gen.blueprint_migration MyApp.Catalog.Product
        mix brando.gen.blueprint_migration MyApp.Catalog.Product --dry-run
        mix brando.gen.blueprint_migration MyApp.Catalog.Product --rebaseline
        mix brando.gen.blueprint_migration --all

    The exact migration source and snapshot version are printed before acceptance.
    Migration and binary snapshot writes use Brando's checked, paired writer after
    acceptance. They do not pass through Igniter's generic text writer. A dry run
    or declined plan does not create files or advance snapshot history.

    The commit rejects changes to Blueprint metadata or migration/snapshot history
    since review. Generate one Blueprint storage plan per invocation, or every
    plan at once with --all; accept and compile pending Blueprint source changes
    before planning their storage.

    --all plans every application Blueprint (those compiled into the configured
    :otp_app) whose storage differs from its latest snapshot, or that has no
    snapshot yet, and lists the rest as up to date. Each Blueprint keeps the
    migration path a single run would pick. The migrations get increasing
    versions, a Blueprint coming after the Blueprints whose tables it references
    and otherwise in alphabetical order. One review covers them all, and after
    acceptance every plan is checked again before any file is written: if one is
    stale, none are written. A Blueprint whose migration path cannot be inferred
    is left out with a warning; plan it on its own with --migration-path. --all
    accepts --snapshot-path and --dry-run, but not a Blueprint module,
    --migration-path or --rebaseline. Brando's own tables come from
    mix brando.gen.migrations instead.

    New storage uses priv/repo/migrations in classic mode and tenant_migrations
    for tenant content in single/multi mode. Shared public-schema Blueprints
    use public migration history. Existing history in the other directory requires
    an explicit --migration-path decision; source settings do not move tables.

    --migration-path and --snapshot-path select custom directories. --rebaseline
    explicitly records storage already implemented by a reviewed manual migration;
    it must not be used to hide missing or failed database migrations. The command
    only creates source files; apply them separately with mix brando.migrate,
    followed by mix brando.migrate --tenants when using named environments.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        positional: [blueprint: [optional: true]],
        schema: [
          all: :boolean,
          interactive: :boolean,
          migration_path: :string,
          snapshot_path: :string,
          rebaseline: :boolean
        ],
        example: "mix brando.gen.blueprint_migration MyApp.Catalog.Product"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Migration.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.BlueprintMigration do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans Blueprint storage changes (requires igniter)"
    @impl Mix.Task
    def run(_), do: Mix.Brando.missing_igniter!("brando.gen.blueprint_migration")
  end
end
