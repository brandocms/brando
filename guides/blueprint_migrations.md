# Blueprint migrations

Blueprint migrations turn storage-relevant DSL changes into reviewed Ecto migrations. The generator stores a
versioned, normalized schema snapshot beside the migration history and compares the next Blueprint definition to that
snapshot. It does not compare arbitrary runtime structs or infer state from the database.

## Normal workflow

After changing a Blueprint, run:

```shell
mix brando.gen.blueprint_migration MyApp.Projects.Project
```

The task creates two files:

- an Ecto migration under `priv/repo/migrations/`;
- a storage snapshot under `priv/blueprints/snapshots/<blueprint>/`.

Commit the Blueprint, migration, and snapshot together. Never edit a snapshot by hand, and do not delete old snapshots
or migration files. If no storage-relevant configuration changed, the task reports that no migration is needed and
does not create another version.

Before committing a generated migration:

1. Read both `up/0` and `down/0`. The task calls out removed columns and tables, but the developer remains responsible
   for deciding whether data loss is acceptable.
2. Run the migration against a disposable or development database.
3. Roll it back and run it forward again. This is especially important for foreign keys, unique indexes, block fields,
   entries relations, and alternates.
4. Run the affected application tests.

```shell
mix ecto.migrate
mix ecto.rollback
mix ecto.migrate
mix test
```

Deployment still uses the application's normal Ecto migration command. The Blueprint task generates source files; it
does not connect to or mutate a database.

## What the snapshot tracks

Snapshot format 2 records the database contract rather than the complete DSL:

- table and primary-key type;
- persisted attribute names, database types, defaults, nullability, precision, and scale;
- asset and belongs-to foreign keys, including referenced table, key type, delete action, and constraint name;
- embedded JSON columns;
- unique and language indexes with deterministic names;
- timestamps;
- auxiliary block, entries, and alternate tables, their foreign keys, and indexes.

Presentation-only changes—forms, listings, translations, upload UI, and media processing settings—do not generate a
database migration unless they also change one of those storage contracts.

## Renaming an attribute

Renames must be explicit. Replace the old declaration and retain its storage name as a migration hint:

```elixir
attributes do
  attribute :headline, :string, rename_from: :title
end
```

The generator emits a column rename in `up/0` and the inverse rename in `down/0`. It also handles a type or option
change on the renamed column. Do not declare both `:title` and `:headline`; the semantic validator rejects that
ambiguous state. The hint may remain in the Blueprint after the migration; once the new column exists it is a no-op.

## Changes that require a hand-written migration

Table and primary-key changes are deliberately refused. Their safe implementation depends on deployed data, foreign
keys, application rollout order, and sometimes concurrent versions of the application. Write and test the Ecto
migration yourself, then record the new known-good Blueprint state:

```shell
mix brando.gen.blueprint_migration MyApp.Projects.Project --rebaseline
```

`--rebaseline` creates only a new snapshot and marks it as an intentional baseline. Future generator runs may therefore
continue without a generated migration for that baseline; the hand-written migration remains the database history. It
is not a shortcut for a missing database migration. Use it only after a reviewed hand-written migration exists and the
database has been verified to match the current Blueprint.

The generator also stops if it finds migrations without snapshots, snapshots without migrations, an unreadable
snapshot, an invalid rename source, or another history inconsistency. Restore the missing file from version control
first. Re-baseline only when restoration is impossible and you have independently confirmed the live database schema.

## Upgrading legacy snapshots

Existing external-term snapshots are decoded as legacy format 1 and normalized in memory. The next successful
generation writes format 2; an unchanged Blueprint upgrades the existing snapshot atomically without creating a
migration.

Before upgrading Brando:

1. Commit every existing Blueprint migration and snapshot.
2. Run the task once for each Blueprint that uses generated migrations.
3. Review and commit any upgraded snapshots together.

If safe decoding reports a corrupt or incompatible legacy snapshot, do not delete it and rerun the generator—that
would make the current Blueprint look like a brand-new table. Restore a valid copy from version control. If none exists,
compare the Blueprint with the database manually and use `--rebaseline` only after they are known to match.

## Umbrella and custom paths

Use explicit paths when the application's migrations or snapshots do not live under the current working directory:

```shell
mix brando.gen.blueprint_migration MyApp.Projects.Project \
  --migration-path apps/my_app/priv/repo/migrations \
  --snapshot-path apps/my_app/priv/blueprints/snapshots
```

Always use the same pair of paths for a Blueprint. Migration generation is serialized across the migration directory,
and Ecto versions are allocated monotonically across every migration in that directory, including migrations for other
Blueprints.

## Why this is not automatic in the Igniter upgrade

Igniter can rewrite source syntax, but it cannot prove that a particular production database matches a Blueprint or
that a missing historical snapshot is safe to reconstruct. The 0.54 Igniter task therefore does not generate or
re-baseline Blueprint migrations. Run the commands in this guide deliberately after the source upgrade, with the
database history and generated diff available for review.
