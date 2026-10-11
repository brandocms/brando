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
        mix brando.gen.blueprint_migration --all --reconcile

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
    accepts --snapshot-path, --dry-run and --reconcile, but not a Blueprint module,
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

    --reconcile fits each plan to the database, for snapshots older than their
    tables (see "Legacy snapshots" in guides/migrating_from_053.md). It reads
    the schemas on the configured repo's search path, so the database must be
    reachable, and compares names only, not types, defaults or nullability. It
    is refused when tenancy_mode is :single or :multi, where content lives in
    one schema per environment:

      * a table the plan creates but the database has (no snapshot history)
        becomes an alter adding only the missing columns and indexes; a table
        that already has them all gets a snapshot only, as a baseline;
      * an existing column, index or auxiliary table the plan adds is added
        with add_if_not_exists/create_if_not_exists and left out of down/0; an
        existing column with references(...) is left out, since PostgreSQL adds
        its foreign key even when it skips the column;
      * a column or auxiliary table is dropped only when a generated migration
        in the Blueprint's history created it and it is empty; anything older
        is kept whatever it holds, a column or table with data is kept with a
        comment giving its count, and legacy Villain columns (data, html,
        *_data) are never dropped; a drop of something the database lacks is
        left out. A kept NOT NULL column without a default loses its NOT NULL,
        so inserts that leave it out keep working;
      * a change of a column the database lacks becomes an add; a rename
        already done by hand is left out, one with neither column becomes an
        add, and one with both stops the plan.

    The first comment of each migration and the summary name the repo,
    database and schemas read. A summary lists what was reconciled in each file. --reconcile works with a
    Blueprint module or --all, and with --dry-run, which still reads the
    database. It cannot be combined with --rebaseline. Accepting the plan reads
    the database again and rejects the plan if what the migration does changed
    since review; changed counts in its comments do not make it stale. Without
    --reconcile the database is only consulted for warnings.
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
          rebaseline: :boolean,
          reconcile: :boolean
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
