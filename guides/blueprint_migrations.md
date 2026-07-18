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

In the Brando repository, the full E2E reset also rolls every migration after
the monolithic test baseline back and runs it forward again before seeding:

```shell
cd e2e
source .envrc
./test_e2e.sh --reset
```

This makes reversibility part of the normal E2E gate for checked-in Blueprint
migration fixtures; it does not replace testing a generated application
migration against that application's own schema and data.

Deployment still uses the application's normal Ecto migration command. The Blueprint task generates source files; it
does not connect to or mutate a database.

## What the snapshot tracks

Snapshot format 3 records the database contract rather than the complete DSL:

- table plus the physical primary-key column and type;
- persisted physical column names, database types, defaults, nullability, precision, and scale;
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

## Physical Ecto sources

Blueprint field names remain the application-facing Ecto names. A `source:`
option gives a persisted field a different physical database column:

```elixir
primary_key {:id, :id, autogenerate: true, source: :record_pk}

attributes do
  attribute :title, :string,
    source: :headline,
    unique: [with: :tenant_id]

  attribute :tenant_id, :id, source: :account_ref
end

relations do
  relation :owner, :belongs_to,
    module: MyApp.Users.User,
    source: :owner_ref,
    unique: [with: :tenant_id]

  relation :metadata, :embeds_one,
    module: MyApp.Content.Metadata,
    source: :payload
end
```

The generator now uses `record_pk`, `headline`, `account_ref`, `owner_ref`, and
`payload` everywhere in the database contract: columns, references, auxiliary
relations, indexes, constraint names, and snapshots. Runtime constraint names
use the same physical sources, while changesets and application code continue
to use `:id`, `:title`, `:tenant_id`, `:owner_id`, and `:metadata`.

No special step is needed for a new table. For an existing Blueprint created by
an older generator, first establish which columns the database actually has:

- If the database still has an attribute's old logical column, add the physical
  source and keep the old database name as `rename_from:`. For example,
  `attribute :title, :string, source: :headline, rename_from: :title` generates
  a reversible `title` to `headline` rename. Review and run the normal generated
  migration.
- If the database already has the physical columns because its migrations were
  maintained by hand, do not apply a generated remove/add migration for the
  stale snapshot. Verify the live schema, indexes, and foreign keys against the
  Blueprint, then use `--rebaseline` to record the known-good physical state.
- Changes to a primary-key source, or source corrections for relations and
  embeds that cannot use an attribute `rename_from:`, require a reviewed
  hand-written migration followed by `--rebaseline`. Primary-key migrations
  must also update every referencing foreign key deliberately.

A belongs-to relation with `define_field: false` gets its physical source from
the separately declared foreign-key attribute. The generator attaches the
reference to that one column and rejects a missing or type-incompatible field.

Do not delete a snapshot to make a physical-source mismatch disappear. Igniter
cannot inspect deployed schemas or decide whether a column should be renamed or
re-baselined, so this upgrade is intentionally guided rather than automatic.

## Field types, options, and defaults

The migration schema uses the database representation of each Ecto field:

- string-backed enums use text, integer-backed enums use integers, and enum
  arrays use arrays of that primitive type;
- custom `Ecto.Type` and `Ecto.ParameterizedType` modules resolve to their
  primitive storage type;
- application defaults are dumped through the configured Ecto type before they
  are stored in a snapshot or rendered as database defaults;
- `null:`, and decimal `precision:`/`scale:`, affect migrations but are not
  passed to `Ecto.Schema.field/3`;
- Ecto schema-only options do not create migration churn.

This distinction is important for enum defaults. The application-facing default
remains an atom, but the database receives its string or integer mapping:

```elixir
attribute :priority, :enum,
  values: [low: 1, high: 2],
  default: :low,
  null: false
```

For a new table, generate normally. When upgrading an existing generated
history, review the next diff according to the live database:

- A string-backed enum remains text, but a stored atom default may be replaced
  with its executable string default. Run the reviewed generated migration if
  the live default is missing or wrong. If the database was already corrected
  by hand, verify it and rebaseline instead of applying a fictional change.
- An integer-mapped enum, enum array, or custom Ecto type may have an older
  snapshot containing text, `Ecto.Enum`, or an Elixir module as its database
  type. Those old generated declarations could not represent the runtime
  storage contract reliably. Do not apply an automatic type conversion to
  production data without inspection. Write an explicit migration (including
  PostgreSQL `USING` conversion when needed), test it backward and forward,
  then use `--rebaseline`. If the live database already has the correct
  primitive type because it was maintained by hand, verify and rebaseline it
  directly.

New `null:` and decimal precision/scale declarations use the normal generated
migration workflow. Before adding `null: false`, resolve existing null rows and
decide on a data backfill. A relation with `define_field: false` takes these
options from its separately declared foreign-key attribute.

Igniter does not rewrite field declarations or generate these migrations: it
cannot inspect enum data conversions, custom type implementations, live
defaults, or null rows.

## Relation option corrections

Blueprint validates relation option names, types, and scopes before generating
Ecto associations. Most corrections are runtime/schema metadata only and do
not change a Blueprint migration snapshot:

- removing an ignored or misspelled option;
- enabling Ecto's boolean `unique: true` on a many-to-many association;
- changing cast messages, collection sort/drop params, preload order, defaults,
  `where:`/`join_where:`, or `on_replace:`;
- expressing a has-one association with `through:`.

No migration or Igniter task is needed for those changes. Compile and test the
affected forms and queries. In particular, `sort_param:` and `drop_param:` are
valid only for cardinality-many casting; remove them from embeds-one or
has-one declarations instead of preserving options Ecto cannot execute.

Belongs-to storage options are different. A correction to `source:`, `null:`,
`type:`, `references:`, `foreign_key:`, `constraint_name:`, or `on_delete:` can
change a column or foreign-key constraint. Generate the normal Blueprint
migration, inspect the exact constraint replacement, and run its rollback and
forward paths. Before adding `null: false`, backfill null rows. Before changing
`on_delete:`, verify that both the new deletion behavior and the reverse
migration are safe for production data.

If the live database was already corrected by hand, verify the column and
foreign-key definitions and rebaseline rather than applying a fictional
change. Igniter intentionally does not rewrite relation declarations or select
delete rules because it cannot inspect deployed constraints, dependent data,
or application ownership semantics.

## Scoping a custom collision callback

An arity-one `prevent_collision` callback controls the candidate query. When that query scopes uniqueness by
persisted fields, declare the same fields with `with:` so the runtime constraint and generated database index agree:

```elixir
attribute :slug,
  :slug,
  unique: [
    prevent_collision: fn changeset ->
      language = Ecto.Changeset.get_field(changeset, :language)
      from entry in MyApp.Content.Entry, where: entry.language == ^language
    end,
    with: :language
  ]
```

Callback-only declarations remain globally unique in the database. If an existing callback already narrows
candidates by one or more persisted columns, add those columns to `with:` and run the normal Blueprint migration
generator:

```shell
mix brando.gen.blueprint_migration MyApp.Content.Entry
```

Review the generated replacement of the global unique index with the composite index, then run the rollback/forward
checks from the normal workflow. This source decision cannot be inferred safely by Igniter, so the upgrade task does
not add `with:` or generate the migration automatically.

## Long index and foreign-key names

PostgreSQL stores at most 63 bytes for an identifier and silently truncates
longer index and constraint names. Blueprint migrations, snapshots, and Ecto
changeset constraints use that stored form consistently, including names built
from long tables, fields, composite unique scopes, and custom
`constraint_name:` values.

No database migration or Igniter step is required when upgrading. PostgreSQL
already stored existing overlong names in truncated form. Brando canonicalizes
older Blueprint snapshots while loading them, so running
`mix brando.gen.blueprint_migration MyApp.Content.Entry` does not emit a
drop/recreate migration solely because of this correction. Continue to review
the generator output normally; any operations it does emit represent other
storage changes.

### Collisions after identifier normalization

Different generated names can share the same first 63 bytes. PostgreSQL cannot
create both indexes in one schema, and it cannot create two constraints with
the same name on one table. Blueprint generation therefore stops before
writing a migration or snapshot when it detects:

- duplicate persisted column or auxiliary-table names;
- duplicate index names across the owner table and its auxiliary tables;
- duplicate foreign-key constraint names within one table;
- any of those index or constraint collisions after 63-byte normalization.

The error includes the stored name that collided. Shorten the table or field
names, remove an unintended duplicate uniqueness declaration, or give
belongs-to relations distinct `constraint_name:` values, then run the normal
generator again. Do not re-baseline a collision: that would record a contract
the database cannot represent.

### Unique language attributes

Earlier generators could silently retain the ordinary language lookup index
and discard the unique index when a Blueprint explicitly combined the two:

```elixir
attribute :language, :language, unique: true
```

The generator now emits one unique index, which also serves normal language
lookups. Applications with this declaration must run:

```shell
mix brando.gen.blueprint_migration MyApp.Content.Entry
```

Review the generated replacement of the non-unique index, then run it backward
and forward using the normal workflow. Existing rows must already be unique;
resolve duplicates deliberately before applying the migration. Igniter does
not generate this migration because it cannot safely enumerate application
Blueprints, snapshots, or deployed data.

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
snapshot, an unsupported snapshot format, a filename/embedded-version mismatch, a malformed normalized storage schema,
an invalid rename source, colliding database identifiers, or another history inconsistency. Restore the missing file
from version control first.
Re-baseline only when restoration is impossible and you have independently confirmed the live database schema.

## Upgrading legacy snapshots

Existing external-term snapshots are decoded as legacy format 1 and normalized in memory. Format 2 snapshots with a
conventional `id` primary key are also upgraded in memory. The next successful generation writes format 3; an
unchanged Blueprint upgrades the existing snapshot atomically without creating a migration. A physical primary-key
source is a real identity change relative to format 2 and follows the hand-written migration or verified rebaseline
workflow above.

Snapshot files are source-controlled migration history and must be reviewed like migration source. Brando accepts
retired declaration and field-name atoms in legacy snapshots while rejecting executable terms and validating the
decoded structure. Do not copy snapshots from an untrusted source into the repository.

Before upgrading Brando:

1. Commit every existing Blueprint migration and snapshot.
2. Run the task once for each Blueprint that uses generated migrations.
3. Review and commit any upgraded snapshots together.

If decoding reports a corrupt or incompatible legacy snapshot, do not delete it and rerun the generator—that would
make the current Blueprint look like a brand-new table. Restore a valid copy from version control. If none exists,
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
