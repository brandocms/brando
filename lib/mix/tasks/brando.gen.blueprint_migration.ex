if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.BlueprintMigration do
    use Igniter.Mix.Task
    @shortdoc "Plans a reversible Blueprint migration and snapshot for review"
    @moduledoc """
    Plans storage changes from an accepted, compiled Blueprint using Igniter.

        mix brando.gen.blueprint_migration MyApp.Catalog.Product
        mix brando.gen.blueprint_migration MyApp.Catalog.Product --dry-run
        mix brando.gen.blueprint_migration MyApp.Catalog.Product --rebaseline

    The exact migration source and snapshot version are printed before acceptance.
    Migration and binary snapshot writes use Brando's checked, paired writer after
    acceptance. They do not pass through Igniter's generic text writer. A dry run
    or declined plan does not create files or advance snapshot history.

    The commit rejects changes to Blueprint metadata or migration/snapshot history
    since review. Generate one Blueprint storage plan per invocation; accept and
    compile pending Blueprint source changes before planning its storage.

    New storage uses priv/repo/migrations in classic mode and tenant_migrations
    for tenant content in single/multi mode. Explicit schema-prefixed Blueprints
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
        schema: [interactive: :boolean, migration_path: :string, snapshot_path: :string, rebaseline: :boolean],
        example: "mix brando.gen.blueprint_migration MyApp.Catalog.Product"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Migration.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.BlueprintMigration do
    use Mix.Task
    @shortdoc "Plans Blueprint storage changes (requires igniter)"
    @impl Mix.Task
    def run(_), do: Mix.Brando.missing_igniter!("brando.gen.blueprint_migration")
  end
end
