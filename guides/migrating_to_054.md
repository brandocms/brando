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

This task is built on Igniter, an optional Brando dependency. Add it to the
application's own deps:

```elixir
# mix.exs
{:igniter, "~> 0.8", only: [:dev, :test]},
```

Update the Brando dependency and fetch it, then run:

```shell
mix deps.get
mix deps.compile brando --force
mix brando.migrate54
```

The forced recompile matters: Brando only defines its Igniter-backed tasks if
`igniter` is loadable when Brando itself compiles, so a stale Brando build keeps
reporting `The task "brando.migrate54" could not be found`.

The task:

- rewrites legacy Blueprint list, single, and selection datasources; trait,
  villain/block, form, input, metadata, and JSON-LD syntax; and listing queries,
  filters, actions, selection actions, and supported exports;
- preserves legacy Meta and JSON-LD path/mutator behavior and adds the narrow
  listing component imports used by custom row functions;
- renames legacy listing `filter:` keys and `list_villains/0` calls on
  `Brando.Villain`;
- rewrites every legacy LivePreview target with its own layout and template
  module;
- replaces `mix phx.digest` in a root Dockerfile, removes `?vsn=d` from font
  URLs in application styles/templates, adds a missing single-Repo
  `config :brando, repo_module:` setting, and defaults an unconfigured Swoosh
  API client to `Swoosh.ApiClient.Req`, and pins declared
  `phoenix_live_view` dependencies in `assets/**/package.json` to the loaded
  server version;
- updates Gettext source declarations through `igniter.update_gettext`;
- copies the current `mix brando.upgrade` task and
  `scripts/sync_gettext.sh` helper into the application;
- creates `florist.config.exs` when both legacy `deployment.cfg` and
  `fabfile.py` exist and no Florist configuration is already present.

The Florist conversion reads only deterministic literal settings; it never
evaluates Python. It carries over the project/module, production and staging
targets, SSH endpoint, remote paths and names, database names/users, Docker
host/file, domains, and pgbackup intent where they can be inferred. It retains
the legacy `:single` deployment and nginx topology. Existing
`florist.config.exs`, `deployment.cfg`, and `fabfile.py` files are never
overwritten or removed.

Passwords are deliberately omitted. Before loading the generated configuration,
export `FLORIST_DB_PASSWORD_PROD` and, when generated,
`FLORIST_DB_PASSWORD_STAGING`. Florist uses the SSH agent by default; do not
copy `SSH_PASS` into source control. The task warns and uses a documented
fallback for any Python expression it cannot convert safely.

It does not connect to the database, generate application Blueprint migrations,
choose identifier persistence, migrate data, or resolve production constraints.

Named environments and multi-site tenancy remain opt-in. Projects staying in
the default `tenancy_mode: :none` keep their existing content and media in the
classic locations; they still apply the ordinary Brando-owned public
migrations, but do not add the tenant plug, create tenant migrations, provision
site/environment records, or copy data with `mix brando.migrate_to_tenant`.

After completing this general source upgrade, applications deliberately
choosing tenancy can run
`mix brando.setup.tenancy --mode single --site-key my-site` or
`mix brando.setup.tenancy --mode multi`. That separate Igniter task configures
the deterministic application source changes without running migrations or
copying live data; see `guides/tenancy_and_environments.md` for the ordered
conversion workflow.

The following 0.54 changelog items remain manual because their correct rewrite
depends on application semantics:

- converting legacy `Brando.Type.Video` embedded values to
  `Brando.Videos.Video` records and migrating their data;
- updating source-controlled Liquid/HEEx ref paths and `gallery_images` access
  (Brando-owned migrations handle database-stored module/fragment code);
- updating code that traverses generated `*_identifiers` associations for
  `:entries` relations, whose join entries are now exposed directly;
- moving datasource declarations that still use `Brando.Datasource` outside a
  Blueprint module onto the appropriate Blueprint;
- replacing legacy listing `field`, `template`, and positional `child_listing`
  declarations with application-specific row components/child schemas, and
  redesigning exports that use the removed `after_export` callback;
- changing a Vite manifest only when that application actually uses Vite 5+;
- replacing custom Sharp processing, consolidating custom Create/Update
  LiveViews, adopting `<.head>`, and updating custom navigation markup;
- refreshing the package-manager lockfile and rebuilding backend assets after
  the task pins `phoenix_live_view`; nonstandard frontend manifests still need
  manual review. Retain Hackney explicitly if application code uses it;
- updating callers of `Brando.Videos.Uploader.initiate_upload/3` for its new
  error tuples and provider credential behavior;
- replacing the removed Brando.CDN key-existence check by hand. `key_available?/2` has inverted
  truth and deliberately different error semantics, so a mechanical rename is
  unsafe;
- moving function-based asset `config_target` callbacks from helper modules to
  the relevant Blueprint schema;
- repointing custom admin form components at the modules the form's markup was
  split into. `BrandoAdmin.Components.Form` no longer exports the input
  primitives (`field_base/1`, `input/1`, `label/1`, `error_tag/1`,
  `submit_button/1`, `inputs_for_block/1`, `inputs_for_poly/1`,
  `array_inputs/1`, `array_inputs_from_data/1`, `map_inputs/1`,
  `map_value_inputs/1`, `translate_error/1`) — those are now
  `BrandoAdmin.Components.Form.Primitives` — nor the image, file and video
  drawers and their JS command helpers, which are `Form.ImageDrawer`,
  `Form.FileDrawer` and `Form.VideoDrawer`. The functions and their assigns are
  unchanged, so each is a rename, but the compiler cannot rewrite them for you
  because the call sites are in application markup. `mix compile
  --warnings-as-errors` reports every one as an undefined function;
- transferring ownership of PostgreSQL's `oban_job_state` enum before the Oban
  v14 migration when deploying through the bundled Fabric workflow.

The task reports these items as warnings so they cannot be missed in the review.

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

### Review a generated Florist configuration

Treat switching deployment tools as its own rehearsed migration. Before the
first Florist command:

1. Compare every generated target with its `GLUE_SETTINGS` and target function
   in `fabfile.py`, especially domain, base directory, process name, database,
   Docker host, and Dockerfile. The converter emits the bundled Fabric ports
   (`8055` for production and `8060` for staging); verify each one against the
   corresponding `.envrc.<flavor>` `PORT` and legacy nginx upstream. Florist
   names the single-deployment application port `blue_port`.
2. Keep `deployment type: :single` and `webserver type: :nginx` for the initial
   cutover. Moving to blue/green changes services, ports, proxying, and release
   directories and should be tested separately.
3. Protect persistent media deliberately. The bundled Fabric media operations
   and Florist both use `<base>/<project>/media`, but Florist changes releases
   to versioned directories and creates a `current/media` symlink. Verify any
   project-specific media path before cutover, back it up, and confirm the
   symlink points at the existing persistent directory.
4. Compare the legacy `etc/` systemd, nginx, logrotate, pgbackup, cron, and env
   files with Florist's generated/bootstrap behavior. Do not run bootstrap over
   a production service until the resulting paths and units have been reviewed.
   The generated staging target retains the bundled nginx `noindex` behavior.
5. Configure rclone manually if the fabfile used it. Its prompted credentials
   and deployment-specific bucket paths are intentionally not migrated.
6. Verify the Docker image contains the standard Mix release tarball at the
   path expected by Florist's `release_builder: :elixir`, then rehearse build,
   copy, upload, unpack, migrate, restart, and rollback on staging.

The legacy files remain available as an audit trail. Remove them only in a later
commit after the Florist deployment has been proven.

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
