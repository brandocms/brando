# Migrating from Brando 0.53 or 0.54

Brando 0.55 changes application source, Brando-owned database tables, Blueprint
storage contracts, persisted block data, identifiers, and Gettext structure.
Treat the upgrade as a reviewed deployment, not as one automatic command.
Applications on the `0.54` branch follow the same order; the source step below
says which task they skip.

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

### Dependencies and toolchain

The source tasks run once the new Brando resolves, so fix `mix.exs` by hand
first:

- `{:gettext, "~> 1.0"}`. Brando requires Gettext 1.0; `~> 0.26` does not
  resolve.
- Drop `only: :test` from `floki` (the Phoenix generator default). Brando uses
  Floki at runtime, and `mix deps.get` stops with "Dependencies have diverged"
  while the application restricts it to tests.
- Add Igniter, an optional Brando dependency the tasks are built on:

  ```elixir
  # mix.exs
  {:igniter, "~> 0.8", only: [:dev, :test]},
  ```

A lock from 2024 or early 2025 pins `elixir_make` 0.6, which `vix` and `image`
cannot use, so they fail to resolve. Run `mix deps.unlock elixir_make`, or start
from the `mix.lock` of a site already on 0.55, then fetch again.

Pin the toolchain with mise or asdf: a current Elixir and OTP, and Node 22 or
24. The admin's `engines` (`^20.19 || ^22.12 || >=24`) rejects an odd release
such as Node 23 in both yarn and pnpm installs. Use the same Node major as the
Dockerfile's `node:` stages.

### Run the source tasks

Update the Brando dependency and fetch it, then run:

```shell
mix deps.get
mix brando.migrate54
mix brando.migrate55
```

Neither task compiles the application. They load the dependencies and the
configuration and rewrite source that does not yet compile against the new
Brando; the application usually compiles only after both have run.

Applications already on Brando 0.54 skip `mix brando.migrate54` and run only
`mix brando.migrate55`. Both tasks match legacy syntax or missing
configuration only, so running one on source that no longer needs it changes
nothing.

Brando's optional task and helper modules automatically request recompilation
when Igniter becomes available. The dependency remains optional at runtime.

`mix brando.migrate54` covers the 0.53 to 0.54 source changes. It:

- rewrites legacy Blueprint list, single, and selection datasources; trait,
  villain/block, form, input, metadata, and JSON-LD syntax; and listing queries,
  filters, actions, selection actions, and supported exports;
- preserves legacy Meta and JSON-LD path/mutator behavior;
- renames legacy listing `filter:` keys and `list_villains/0` calls on
  `Brando.Villain`;
- rewrites every legacy LivePreview target with its own layout and template
  module;
- replaces `mix phx.digest` in a root Dockerfile, removes `?vsn=d` from font
  URLs in application styles/templates, and adds a missing single-Repo
  `config :brando, repo_module:` setting;
- removes `processor_module: Brando.Images.Processor.Sharp` from config. Brando
  refuses to boot with it, and Vix is the default;
- moves Gettext backends to `use Gettext.Backend` and their importers to
  `use Gettext, backend: ...`, leaving the `gettext` requirement alone;
- creates the `scripts/sync_gettext.sh` helper in the application, replacing a
  copy of the 0.54 helper. A copy the application edited is left alone with a
  warning.

`mix brando.migrate55` covers the 0.54 to 0.55 source changes. It:

- adds the narrow listing component imports used by custom row functions;
- defaults an unconfigured Swoosh API client to `Swoosh.ApiClient.Req` and
  pins declared `phoenix_live_view` dependencies in `assets/**/package.json`
  to the loaded server version;
- points Brando at the application's `Mailer` when it has one
  (`config :brando, mailer: MyApp.Mailer`); set the address it sends from
  yourself, as described in [Email](email.md);
- gives Villain parsers (`use Brando.Villain.Parser`) back what the parser's
  `__using__` no longer brings in, where they use it: `use Phoenix.Component`
  for `~H`, `import Brando.HTML` for components such as `<.picture>`,
  `import Phoenix.HTML`, and the `Brando.Cache`, `Content`, `Datasource`,
  `Utils`, `Villain` and `Liquex.Context` aliases. It also warns about
  overrides of blocks Brando no longer renders, such as `slideshow/2`
  (slideshows became `gallery` in `brando_77`). Delete those; nothing calls
  them;
- removes the Sharp `processor_module` setting, as `mix brando.migrate54` does;
- completes `Plural-Forms` headers in `priv/gettext/**/*.po`. Gettext 1.0 warns
  on `nplurals=2;` without a rule and on a rule without its trailing `;`, once
  per catalog per compile, so `--warnings-as-errors` fails until they read
  `nplurals=2; plural=(n != 1);`;
- refreshes `scripts/sync_gettext.sh` and archives the consumer-owned
  `mix brando.upgrade` task that 0.54 installed, wherever it lives under `lib/`,
  so Brando's own `mix brando.upgrade FROM TO` hook can take over the task name
  (copying migration files is now `mix brando.gen.migrations`);
- creates `florist.config.exs` when both legacy `deployment.cfg` and
  `fabfile.py` exist and no Florist configuration is already present, and adds
  `plug Brando.Plug.Health` to the endpoint, before the router. Florist's
  deploy and nginx templates check `/health`.

The Florist conversion reads only deterministic literal settings; it never
evaluates Python. It carries over the project/module, production and staging
targets, SSH endpoint, remote paths and names, database names/users, Docker
host/file, domains, and pgbackup intent where they can be inferred. It retains
the legacy `:single` deployment and nginx topology. Existing
`florist.config.exs`, `deployment.cfg`, and `fabfile.py` files are never
overwritten or removed.

Where `deployment.cfg` falls short, the converter reads the other legacy files:

- a target's domain comes from `<TARGET>_URL`, or, when that is missing or still
  the install template's `http://somesite.com` (which it reports), from
  `BRANDO_URL_HOST` in `.envrc.<flavor>`, then from the `server_name` of the
  `etc/nginx/<flavor>.conf` server that proxies to the application (the HTTPS
  one first);
- the application port comes from `PORT=` in `etc/supervisord/<flavor>.conf` or
  `etc/systemd/<flavor>.service`, checked against the nginx upstream. Without
  either it falls back to the bundled Fabric defaults (`8055` and `8060`) and
  says so;
- the warnings name the process manager it found: supervisord or systemd.

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

The following 0.54 and 0.55 changelog items remain manual because their
correct rewrite depends on application semantics:

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
- replacing custom processing that relied on sharp-cli, consolidating custom
  Create/Update LiveViews, adopting `<.head>`, and updating custom navigation
  markup;
- refreshing the frontend's package-manager lockfile and rebuilding it after
  the task pins `phoenix_live_view` (the admin is covered in
  [Admin assets](#admin-assets)); nonstandard frontend manifests still need
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

The tasks report these items as warnings so they cannot be missed in the
review.

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

Rerunning either task is safe; a second run should produce no source diff.

### Admin assets

A 0.54 site's `assets/backend` is usually yarn, Vite 5 and Svelte 4, and the
source tasks leave it alone. Bring it to the current template:

```shell
mix brando.gen.backend --upgrade
```

It takes the template's package versions, `engines` and `packageManager`
(keeping the application's own packages, scripts and BrandoJS source), replaces
`vite.config.js`, removes `svelte.config.cjs` and yarn/npm lockfiles, and
replaces the Dockerfile's `assets_backend` stage with the template's pnpm stage.
Customized CSS and other existing files are kept. Review the diff, then install
and build:

```shell
mix brando.assets.setup --backend-only
```

`--backend-only` leaves `assets/frontend` alone, for a frontend that still uses
yarn or its own build; without it the task installs and builds both with pnpm.
Commit the `assets/backend/pnpm-lock.yaml` it writes: the Docker build installs
from it. The Docker image ships the admin from the local `assets/backend/.yalc`,
so rerun the setup after updating BrandoJS.

### Review a generated Florist configuration

Treat switching deployment tools as its own rehearsed migration. Before the
first Florist command:

1. Compare every generated target with its `GLUE_SETTINGS` and target function
   in `fabfile.py`, especially domain, base directory, process name, database,
   Docker host, and Dockerfile. Check each domain, SSL mode and port the
   converter took from the legacy `.envrc`, nginx and process manager files
   (its warnings name the source), and any it fell back on. Florist names the
   single-deployment application port `blue_port`.
2. Keep `deployment type: :single` and `webserver type: :nginx` for the initial
   cutover. Moving to blue/green changes services, ports, proxying, and release
   directories and should be tested separately.
3. Protect persistent media deliberately. The bundled Fabric media operations
   and Florist both use `<base>/<project>/media`, but Florist changes releases
   to versioned directories and creates a `current/media` symlink. Verify any
   project-specific media path before cutover, back it up, and confirm the
   symlink points at the existing persistent directory.
4. Compare the legacy `etc/` process manager (systemd units or supervisord
   programs), nginx, logrotate, pgbackup, cron, and env files with Florist's
   generated/bootstrap behavior. Florist runs the release as a systemd service:
   on a supervisord site, stop and disable the supervisord program at cutover so
   the two do not compete for the port. Do not run bootstrap over a production
   service until the resulting paths and units have been reviewed. The
   generated staging target retains the bundled nginx `noindex` behavior.
5. Confirm `plug Brando.Plug.Health` sits in the endpoint before the router
   (`mix brando.migrate55` adds it when it creates the configuration). Florist
   checks `/health` during deploys; without the plug the check never passes.
6. Configure rclone manually if the fabfile used it. Its prompted credentials
   and deployment-specific bucket paths are intentionally not migrated.
7. Verify the Docker image contains the standard Mix release tarball at the
   path expected by Florist's `release_builder: :elixir`, then rehearse build,
   copy, upload, unpack, migrate, restart, and rollback on staging.

The legacy files remain available as an audit trail. Remove them only in a later
commit after the Florist deployment has been proven.

## 3. Generate and review database migrations

A project already on a 0.55 development build skips the source tasks above and
starts here, to pick up the migrations added since it last upgraded. First copy
every missing Brando-owned migration:

```shell
mix brando.gen.migrations
```

There are no `brando_206` or `brando_208` migrations: both numbers were
reserved and never needed, so the gap is not a missed migration.

The Igniter migration-file command does not start the application or touch the
database. It allocates monotonically increasing Ecto versions and preserves
historical files. `mix brando.migrate55` archives the unmodified
`Mix.Tasks.Brando.Upgrade` that 0.54 installed; a customized one must be renamed
and compiled before using the library-owned versioned upgrade hook.

Handle application Blueprints according to their history:

- For Blueprints with valid generated migrations and snapshots, run
  `mix brando.gen.blueprint_migration --all` and review the diffs, or plan one
  with `mix brando.gen.blueprint_migration MyApp.Domain.Schema`. `--all` also
  proposes a create-table migration for every Blueprint without a snapshot, so
  rebaseline existing tables first (next point).
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

When a migration adds the Creator trait's `edited_at` to an existing table, the
generator backfills it from `updated_at`, as `brando_175` does for Brando's own
tables.

### Legacy snapshots

A snapshot written before Brando's blocks conversion describes a table the
Brando migration chain has changed since. Diffed against it, the generator
proposes storage that already exists (`create table(:projects_blocks)`,
`rendered_blocks`) and drops the legacy Villain columns (`data`, `html`,
`*_data`). It warns when a planned table or column already exists in the
database or a planned drop looks like a Villain column. In that case:

- Compare `\d table` in a migrated copy of production with every generated
  operation.
- Where they disagree, switch to `create_if_not_exists`/`drop_if_exists` (and
  `add_if_not_exists`/`remove_if_exists` for columns), and roll back and forward
  once.
- Keep `data`, `html` and the other Villain columns until the converted
  content is verified on production data. They are the only record of what
  the conversion started from, and repairs may need them.

A trait removed from a Blueprint without a migration (Translatable, for
example) surfaces in the first generator run as a proposal to drop its columns,
indexes and tables: `language`, its index, `*_alternates`. That is correct but
destructive. Decide whether the data can go before accepting it, or put the
trait back for now.

### Test and development databases

A site that copied Brando migrations years ago may not replay them from an empty
database: early copies use modules that no longer exist (such as
`Brando.Sequence.Migration`), and `mix brando.gen.migrations` never refreshes an
existing copy. Production is unaffected, because it only runs the new
migrations. Load test and development databases from a `structure.sql` instead:
migrate a copy of production, run `mix ecto.dump`, and commit the result. Check
too that `test_paths` in `mix.exs` points at directories that exist.

Before touching a shared database:

1. Read every generated `up/0` and `down/0`.
2. Resolve data prerequisites such as duplicate unique values and null backfills.
3. Run all migrations forward, backward, and forward again on a disposable
   database.
4. Commit each Blueprint, Ecto migration, and snapshot together.

Only then run:

```shell
mix brando.migrate
# With named environments, after public migrations:
mix brando.migrate --tenants
```

`mix brando.migrate` runs the public migrations. Brando's own migrations that
work "in every environment" (their notes in the CHANGELOG say so) change
`public` and every environment schema in that run. `--tenants` then runs the
tenant migrations in each environment, including the Blueprint migrations of
content stored there; tenant discovery needs the public migrations first.

## 4. Repair derived data

After the database migration succeeds, rebuild persisted block rendering and
identifiers:

```shell
mix brando.entries.resave
mix brando.identifiers.sync
mix brando.images.adopt
```

`mix brando.images.adopt` records which config each image was made with, for
the images whose files already match it, so Utilities → Recreate changed
images only recreates the ones that differ. Try it with `--dry-run` first; see
[Media](media.md#images-made-before-fingerprints).

Run these against staging first and inspect counts and representative entries.
They mutate application data and are not reversed by `mix ecto.rollback`.

Some 0.55 features need a step of their own; the CHANGELOG's Breaking notes
describe each:

- Rebuild the admin search index once in each environment, from
  Configuration → Utilities → Search index. `brando_212` creates the table
  empty.
- Add `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to the
  endpoint, before the router.
- An application that sets `config :brando, Oban` itself adds the
  `content_events`, `webhooks` and `search_index` queues, and
  `Brando.Worker.WebhookDeliveryPurger` to its crontab.
- With group authorization, grant the Notifications permission
  (`brando.notifications.manage`) to the groups that should manage
  notification routes; see [Notifications](notifications.md).

`mix brando.doctor` reports migrations that have not run, in `public` and in
each environment, and Oban queues that are missing.

Image alt text, title and credits are now translated maps. Templates that print
them without the `i18n` filter (`{{ entry.cover.alt | i18n }}`) show the raw map.
Module, container and menu templates live in the database, so the source
migration cannot see them; list the ones to fix with:

```shell
mix brando.check.image_texts
```

## 5. Reconcile Gettext catalogs

`mix brando.migrate55` has already completed incomplete `Plural-Forms` headers
in existing catalogs. Extract each application's actual locales. For example:

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
