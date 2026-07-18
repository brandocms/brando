# Migrating to Brando 0.54

Brando 0.54 changes application source, Brando-owned database tables, Blueprint
storage contracts, persisted block data, identifiers, and Gettext structure.
Treat the upgrade as a reviewed deployment, not as one automatic command.

## 1. Establish a recovery point

Before updating the dependency:

1. Commit the complete application worktree, including every existing Ecto
   migration and Blueprint snapshot.
2. Back up the production database and Gettext catalogs.
3. Rehearse the upgrade on a copy of production data or an equivalent staging
   database.
4. Record which database-backed Blueprints already have generated snapshots
   under `priv/blueprints/snapshots`.

Do not delete a snapshot to repair history. A missing snapshot can make an
existing table look new to the generator.

## 2. Update source with Igniter

Update the Brando dependency and fetch it, then run:

```shell
mix deps.get
mix brando.migrate54
```

The task:

- rewrites legacy Blueprint datasource, trait, villain/block, form, listing,
  input, metadata, and JSON-LD syntax;
- rewrites every legacy LivePreview target with its own layout and template
  module;
- updates Gettext source declarations through `igniter.update_gettext`;
- copies the current `mix brando.upgrade` task and
  `scripts/sync_gettext.sh` helper into the application.

It does not connect to the database, generate application Blueprint migrations,
choose identifier persistence, migrate data, or resolve production constraints.

Review every source change. In particular, decide which Blueprints should not
persist identifiers:

```elixir
persist_identifier false
```

Then validate and commit the source migration:

```shell
mix format
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

Rerunning `mix brando.migrate54` is safe; a second run should produce no source
diff.

## 3. Generate and review database migrations

First copy every missing Brando-owned migration:

```shell
mix brando.upgrade
```

The copied upgrader does not start the application or touch the database. It
allocates unique, monotonically increasing Ecto versions and is idempotent.

Handle application Blueprints according to their history:

- For a Blueprint with valid generated migrations and snapshots, run
  `mix brando.gen.blueprint_migration MyApp.Domain.Schema` and review the diff.
- For an existing table with no generated Blueprint snapshot, do not apply the
  create-table migration that a first normal run would propose. Independently
  verify the live table, columns, indexes, and foreign keys against the current
  Blueprint, then establish the known-good baseline with `--rebaseline`.
- For a genuinely new table, use the normal generator output.
- For a table, root primary-key, physical primary-key source, or existing
  column-level primary-key change, write and test a hand-written Ecto migration,
  then rebaseline. The generator deliberately refuses to infer these operations.

See [Blueprint migrations](blueprint_migrations.md) for renames, physical Ecto
sources, relation corrections, type/default conversions, legacy snapshots,
custom paths, and fail-closed history recovery.

Before touching a shared database:

1. Read every generated `up/0` and `down/0`.
2. Resolve data prerequisites such as duplicate unique values and null backfills.
3. Run all migrations forward, backward, and forward again on a disposable
   database.
4. Commit each Blueprint, Ecto migration, and snapshot together.

Only then run:

```shell
mix ecto.migrate
```

## 4. Repair derived data

After the database migration succeeds, rebuild persisted block rendering and
identifiers:

```shell
mix brando.entries.resave
mix brando.identifiers.sync
```

Run these against staging first and inspect counts and representative entries.
They mutate application data and are not reversed by `mix ecto.rollback`.

## 5. Reconcile Gettext catalogs

Extract each application's actual locales. For example:

```shell
mix gettext.extract --merge priv/gettext/backend --locale no \
  --plural-forms-header "nplurals=2; plural=(n != 1);"
mix gettext.extract --merge priv/gettext/frontend --locale no \
  --plural-forms-header "nplurals=2; plural=(n != 1);"
```

The copied helper can fill an empty, single-line `msgstr` from the same `msgid`
in a sibling catalog:

```shell
bash scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES
```

Run it only on backed-up catalogs and review the diff. It deliberately does not
guess multiline, plural, or contextual translations; reconcile those manually.

## 6. Final deployment gate

Before deploying, run the application unit suite and its full serial E2E suite,
including a clean database reset. Verify at least forms, listings, uploads,
LivePreview, block rendering, identifier-backed selections, rollback, and a
second forward migration.

If the upgrade must be abandoned, restore both the pre-upgrade application
release and database backup. Code rollback plus `mix ecto.rollback` does not
undo entry resaves, identifier synchronization, or manual Gettext changes.
