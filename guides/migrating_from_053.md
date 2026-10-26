# Migrating from Brando 0.53 or 0.54

Brando 0.55 changes application source, Brando-owned database tables, Blueprint
storage contracts, persisted block data, identifiers, and Gettext structure.
Tasks do most of the work, and each phase stops for you to review what they
did, so treat the upgrade as a rehearsed deployment. Applications on the `0.54`
branch follow the same order and skip one task.

## Which guide

Find the newest Brando migration the application has copied:

```shell
ls priv/repo/migrations | grep -o 'brando_[0-9]*' | sort -t_ -k2 -n | tail -1
```

| Newest migration | The application is on | Follow |
| --- | --- | --- |
| `brando_55` or lower | 0.51 (`legacy`): Vue admin, no Blueprints | [Migrating from 0.51](migrating_from_051.md) |
| `brando_56` to `brando_102` | 0.52 or 0.53: Blueprints, content still Villain JSON in `data` columns, no `*_blocks` tables | This guide, both source tasks |
| `brando_103` to `brando_130` | 0.54: blocks | This guide, without `mix brando.migrate54` |
| `brando_131` or higher | a 0.55 development build | Rerun `mix brando.migrate55` (see [Run the source tasks](#run-the-source-tasks)), then this guide from section 3 |

The `@version` in `deps/brando/mix.exs` is a weaker signal: a development
checkout reported `0.53.0-dev` from mid-2022 to the 0.53.0 release in 2024.

- On 0.52 (`brando_87` or lower), first make the changes in the 0.53.0
  section of `CHANGELOG.md`. No task covers the 0.52 to 0.53 source changes.
- With Villain content, `mix brando.migrate` converts it to blocks
  (`brando_103` onward), and the Blueprint snapshots predate that conversion.
  Read [Legacy snapshots](#legacy-snapshots) before generating Blueprint
  migrations.
- `mix brando.migrate54` ships in 0.55 and is removed in 0.56, so a 0.53 site
  upgrades to 0.55 before going further ("How long source migrations ship" in
  `UPGRADE.md`).

## The short version

Without named environments, the upgrade is these commands, in this order:

```shell
# 1. Recovery point: commit, back up, start the old site (by hand)

# 2. Source
elixir /path/to/brando/scripts/prepare_055_deps.exs --brando-ref <commit sha>
mix deps.unlock --all
mix deps.get
mix brando.migrate54                  # from 0.53 only
mix brando.migrate55
mix format
mix compile --warnings-as-errors
mix brando.gen.backend --upgrade
mix brando.assets.setup --backend-only

# 3 and 4. Database and derived data
mix brando.upgrade.database           # again after each stop, until it says it is done

# 5. Gettext
mix brando.gettext.reconcile

# 6. Compare the public pages with the old site
mix brando.upgrade.snapshot …
```

Stop and review at these points:

- **After each source task.** Igniter shows the diff and asks before writing.
  What the task prints is your to-do list: its warnings and notices name, with
  file and line, what it left for you. Work through them in
  [Fix what the tasks list](#fix-what-the-tasks-list) before compiling.
- **After `mix brando.gen.backend --upgrade`.** Review its diff, and port the
  application's own admin CSS ([Admin assets](#admin-assets)).
- **At each stop of `mix brando.upgrade.database`.** It stops after copying
  Brando's migrations, after a failed conversion check, and after writing the
  Blueprint migrations, and asks before every step that changes the database.
  Publish the fragments the site shows before you answer yes to the resave
  ([section 4](#4-repair-derived-data)).
- **After `mix brando.gettext.reconcile`.** Review the catalog diff.

And these, which no task does for you:

- Change the Dockerfile's `FROM … twined/fehn:<tag>` to a fehn 4.2 variant for
  the server's Ubuntu release, and build the admin with Node 24
  ([Dependencies and toolchain](#dependencies-and-toolchain)).
- On a database deployed with the bundled Fabric workflow, give the
  application's database user ownership of `oban_job_state` before
  `brando_153` runs ([section 3](#3-generate-and-review-database-migrations)).
- In an application that sets `config :brando, Oban` itself, add Brando's
  queues and cron jobs ([section 4](#4-repair-derived-data)).
- With group authorization, grant `brando.notifications.manage` to the groups
  that should manage notification routes ([section 4](#4-repair-derived-data)).

With named environments, `mix brando.upgrade.database` refuses to run: follow
sections 3 and 4 by hand.

`mix igniter.upgrade brando` does not cover this upgrade. It updates Brando and
runs Brando's `mix brando.upgrade FROM TO` hook, which runs
`mix brando.migrate55` when the upgrade crosses into 0.55 and copies Brando's
missing migrations. But a 0.53 or 0.54 `mix.exs` needs the changes in
[Dependencies and toolchain](#dependencies-and-toolchain) before Brando 0.55
resolves, and the hook refuses versions older than `0.54.0-dev`. Within the
0.55 line it copies new migrations without rerunning `mix brando.migrate55`
([Framework migrations and upgrades](generators.md#framework-migrations-and-upgrades)).

## 1. Establish a recovery point

Before updating the dependency:

1. Commit the complete application worktree, including every existing Ecto
   migration and Blueprint snapshot.
2. Back up the production database and Gettext catalogs.
3. Rehearse the upgrade on a copy of production data or an equivalent staging
   database.
4. Record which database-backed Blueprints already have generated snapshots
   under `priv/blueprints/snapshots`.
5. Start the old site and leave it running through the upgrade (below).

Do not delete a snapshot to repair history. A missing snapshot can make an
existing table look new to the generator.

### Keep the old site running

The final gate compares the public pages before and after the upgrade with
`mix brando.upgrade.snapshot` (see [Final deployment gate](#6-final-deployment-gate)),
which fetches the pages from both sites while they run. Start the old site now,
before changing anything:

1. Restore the production dump twice: one database to upgrade, and an
   untouched copy for the old site.
2. Run the old site from a checkout of the pre-upgrade commit, such as a Git
   worktree (`git worktree add ../myapp-before HEAD`), against the untouched
   copy and on a port of its own (4000, say).
3. Check that it compiles and serves, and leave it running.

A new worktree compiles every dependency from scratch, and an old lock may not
build on a current OTP: one 0.53 site's lock held a `mochiweb` that does not
compile on OTP 27, where `maybe` is a reserved word, and built on OTP 26 with
Elixir 1.17. Give the worktree the toolchain its lock builds on, in a
`.mise.toml` of its own.

## 2. Update source with Igniter

### Dependencies and toolchain

Brando 0.55 does not resolve against a 0.53 or 0.54 `mix.exs`, and the source
tasks run only once it does. Brando's script makes the changes; run it from the
application's root:

```shell
elixir /path/to/brando/scripts/prepare_055_deps.exs --brando-ref <commit sha>
```

`--brando-ref` points the Brando dependency at a commit on GitHub. To rehearse
against a local checkout, give `--brando-path /path/to/brando` instead (see
[Working against a Brando checkout](#working-against-a-brando-checkout) for
picking up edits to it); deploy from the commit, since the release's Docker
build cannot see a checkout outside the project. `--dry-run` writes nothing. The script edits `mix.exs` as text and
prints each change, then lists the `timex` calls left in `lib/` and what
`mix.lock` still has on HTTPoison or hackney 1. Running it again changes
nothing.

Then unlock everything and fetch. The old lock holds versions the new Brando
cannot use, and Mix names `the lock` in the conflict:

```shell
mix deps.unlock --all
mix deps.get
```

On a 0.53 site this resolves on the first `mix deps.get`. When it does not,
the conflict is in a package the script leaves alone:
[Dependencies by hand](#dependencies-by-hand) lists what the script changes and
how to fix the rest. Starting from the `mix.lock` of a site already on 0.55
also works.

Pin the toolchain with mise or asdf:

- Elixir 1.18 or newer on OTP 27 or newer. Develop on Elixir 1.19 or newer: on
  older Elixir, Phoenix 1.8's code reloader unloads every consolidated protocol
  on every request, which adds 50 to 70 ms to each request in development.
- Node 24. The admin's `engines` (`>=24.0.0`) rejects Node 22 and older, and
  the odd 23, in pnpm installs. The script and `mix brando.doctor` print the
  `node` on the PATH and warn about one the builds refuse.
- For the release build, change the Dockerfile's
  `FROM --platform=linux/amd64 twined/fehn:<tag> as deps` line to the fehn 4.2
  variant for your server's Ubuntu release: older tags cannot compile Brando's
  Elixir `~> 1.18`, and no task rewrites `FROM`. [The Docker build](deployment.md#the-docker-build)
  lists the variants and how to check a server.

### Run the source tasks

If the application has never been run through `mix format`, run it and commit
the result first, so the tasks' diff holds only their changes. Then:

```shell
mix brando.migrate54   # from 0.53 only
mix brando.migrate55
```

Neither task compiles the application. They load the dependencies and the
configuration and rewrite source written for the old Brando, which usually
compiles only after both have run. Each shows its diff and asks before writing;
`--dry-run` only shows it. Both match legacy syntax and missing configuration
only, so a second run on migrated source changes nothing. Rerun
`mix brando.migrate55` after updating Brando to a later 0.55 build, to pick up
rewrites added since.

Read what each task prints:

- **The diff** is what it rewrote. Review it as you would a colleague's commit;
  [What the source tasks change](#what-the-source-tasks-change) describes each
  rewrite.
- **Notices** say what it decided, such as the Blueprints it set
  `persist_identifier false` on and the listing actions it removed.
- **Warnings** list, with file and line, what it found and could not rewrite,
  and the decisions it leaves to you. They are the next step.

`mix brando.migrate54` writes every `config :brando` setting the upgrade asks
for at once (`repo_module`, `mailer` and a placeholder sender), and
`mix brando.migrate55` finds them in place: any change to the configuration
recompiles Brando, which takes about a minute.

When a site deploys with Fabric (`deployment.cfg` and `fabfile.py`),
`mix brando.migrate55` also writes a `florist.config.exs`. Review it before the
first Florist command, as
[Review a generated Florist configuration](#review-a-generated-florist-configuration)
describes. Named environments and multi-site tenancy stay opt-in: see
[Named environments](#named-environments).

### Fix what the tasks list

Work through what the tasks listed, then the items no task can find. Fix the
sender first, before the first compile.

**Listed by the tasks:**

1. **The placeholder sender.** Replace `noreply@example.com` in
   `config :brando, Brando.Mailer, from: {"My site", "noreply@my-site.com"}`
   with an address your mail provider sends for, and configure the mailer's
   production adapter in `config/runtime.exs` ([Email](email.md)). Make your
   own configuration changes in the same pass. Outside development and test,
   Brando treats a sender on a domain reserved for examples as no sender: it
   sends nothing, and `mix brando.doctor` fails until it is replaced. A sender
   set anywhere in `config/*.exs`, inside an `if config_env() == :prod` block
   included, gets no placeholder.
2. **Listings left as they are.** Write a row component for each
   ([Rows](blueprint_listings.md#rows)). Replace positional `child_listing`
   declarations with child schemas, and redesign exports that use the removed
   `after_export` callback. Of the listed actions with options beyond `label`,
   `event` and `confirm`, remove the ones `default_actions` already offers
   (edit, duplicate, delete).
3. **Edited Create/Update LiveView pairs.** Merge each into one
   `<Name>FormLive`, as the task did for the unedited ones, and point both
   routes at it. For a route shape the task could not scope, it prints the
   fix: `as:` on the scope and `router_scope:` on the Blueprints routed in it.
   Without the form route, the listing's edit links crash; `mix brando.doctor`
   reports each Blueprint whose route helper is missing.
4. **Navigation reads and page loads.** Read menu items through
   `Brando.HTML.get_menu_item_url/1`, `get_menu_item_text/1`,
   `get_menu_item_target_blank/1` and `item.children`. Give the listed
   `Pages.get_page/1` calls `preload: [:vars]` where their page's vars are
   read.
5. **`.html` reads.** A fragment, and a schema whose Villain field moved to
   blocks, has no `html`, and reading it fails the page with a `KeyError`. Read
   `rendered_blocks` (`rendered_hero_blocks` for `hero_html`), or render a
   fragment with `Brando.Pages.render_fragment/1`.
6. **Reads of an `:entries` relation.** It holds the join rows, each with its
   `identifier`, so `Enum.map(project.related_entries, & &1.entry_id)` fails
   with a `KeyError`. Preload the identifiers through the rows and read the
   entry id there:

   ```elixir
   project = Brando.Repo.preload(project, related_entries: :identifier)
   ids = Enum.map(project.related_entries, & &1.identifier.entry_id)
   ```

   The rows come in the order the editor picked them; a list query on `ids`
   does not keep it (see [Entries](blueprint_fields.md#entries)).
7. **Blueprint inputs.** Give a listed `:multi_select` on a has_many relation
   `relation:` as well as `relation_key:`: the join schema's belongs_to on that
   key (`relation_key: :category_id, relation: :category`). On a listed
   `:entries` input, keep only options identifiers have: order by identifier
   columns (`%{order: "asc language, asc title"}`) and drop `preload:` (see
   [Related entries](blueprint_forms.md#related-entries)).
8. **Gettext calls in Blueprint labels.** Write them as `t("…")`, which
   translates in the schema's domain; `gettext/1` extracts into `default`.
9. **`use Phoenix.HTML`.** Where the task kept view helpers that are in use,
   add `{:phoenix_html_helpers, "~> 1.0"}` to `mix.exs`. Replace any other
   `use Phoenix.HTML` it lists with `import Phoenix.HTML`.
10. **Video scripts.** A file video's `data-src` is on its
    `[data-smart-video]` wrapper, and the `<video>` carries `src` unless it
    preloads. In each listed script under `assets/`, read
    `el.closest('[data-smart-video]').dataset.src`, or fall back to it.
11. **`list_*` calls with no `order:`.** The migrations rewrite rows, and a
    query without `ORDER BY` returns them in storage order, so a page may
    change order (the first category of a menu, articles with equal
    `sequence`). Give each listed call an order before comparing public pages
    with the old site, and check the site's other queries (`Repo` and
    `Ecto.Query`) by hand.
12. **Identifier persistence.** Set `persist_identifier false` on each
    Blueprint the task could not decide, and on any other Blueprint that should
    not persist identifiers. Persistence defaults to true.
    `mix brando.identifiers.sync` then deletes such a Blueprint's identifiers,
    and any pick that points at them.
13. **Slug inputs in the application's generator template.**
    `priv/templates/brando.gen.blueprint/blueprint.ex` is EEx, so the task only
    lists its lines: change `from:` or `for:` on a slug input to `source:`.
14. **Image sizes.** Where the task wrote `default_srcset:` as
    `srcset: %{default: […]}`, check that the sizes it names are in the asset's
    `sizes`.
15. **Villain parser overrides of blocks Brando no longer renders**, such as
    `slideshow/2`. Delete them: nothing calls them.
16. **`get_entries_from_identifiers` calls** whose preloads the task could not
    read. Pass them as `%{preload: [:cover]}`.
17. **Endpoint plugs.** When the task could not find the endpoint, add
    `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to it, before
    the router ([Markdown alternates](markdown_alternates.md),
    [IndexNow](identity_and_seo.md#indexnow)).
18. **Module aliases in braces** the new name cannot share. Write the new name
    (the table is in `UPGRADE.md`); the old names warn until 0.57.
19. **An edited `scripts/sync_gettext.sh`.** Compare it with Brando's and merge
    by hand.
20. **A dashboard that renders only a header.** The admin's start page is the
    application's own `MyAppAdmin.DashboardLive`. In the one the task listed,
    render the dashboard component, as the installer's template does:

    ```elixir
    def render(assigns) do
      assigns = assign_new(assigns, :authorization, fn -> nil end)

      ~H"""
      <.live_component
        module={BrandoAdmin.Components.Dashboard}
        id="admin-dashboard"
        current_user={@current_user}
        authorization={@authorization}
      />
      """
    end
    ```

**Not found by any task.** Their correct rewrite depends on the application:

- **Legacy video values.** Moving `Brando.Type.Video` embedded values to
  `Brando.Videos.Video` records takes an application-specific schema and data
  migration; renaming the module corrupts storage.
- **Ref paths and galleries in source templates.** Brando's migrations update
  the module and fragment code stored in the database. In Liquid and HEEx
  templates in the source, update ref paths such as
  `refs.name.data.data.path`, and replace `gallery_images` with
  `gallery_objects`.
- **Datasources outside Blueprints.** Move a `use Brando.Datasource` in a
  standalone schema onto the appropriate Blueprint.
- **Custom admin form components.** Call the input primitives
  (`field_base/1`, `input/1`, `label/1`, `error_tag/1`, `submit_button/1`,
  `inputs_for_block/1`, `inputs_for_poly/1`, `array_inputs/1`,
  `array_inputs_from_data/1`, `map_inputs/1`, `map_value_inputs/1`,
  `translate_error/1`) on `BrandoAdmin.Components.Form.Primitives`, and the
  image, file and video drawers and their JS command helpers on
  `Form.ImageDrawer`, `Form.FileDrawer` and `Form.VideoDrawer`, in place of
  `BrandoAdmin.Components.Form`. The assigns are the same;
  `mix compile --warnings-as-errors` reports every old call.
- **Video uploads and the CDN.** Update callers of
  `Brando.Videos.Uploader.initiate_upload/3` for its error tuples and provider
  credential failures. Replace each call to the removed `Brando.CDN`
  key-existence check by hand: `key_available?/2` has inverted truth and
  different error semantics, so a rename is wrong.
- **Function-based `config_target` callbacks** on helper modules. Move them
  onto the relevant Blueprint schema.
- **The frontend.** With Vite 5 or newer, set `manifest: 'manifest.json'` in
  the frontend's Vite config (Vite 3 and 4 manifests work as they are). After
  `mix brando.migrate55` pins `phoenix_live_view` in `assets/**/package.json`,
  refresh the frontend's lockfile and rebuild it, and review a nonstandard
  manifest. Replace custom processing that relied on sharp-cli, and adopt
  `<.head>` (the 0.54.0 section of `CHANGELOG.md`).
- **Direct Hackney calls.** Declare `{:hackney, "~> 4.0"}`: hackney 1.x does not
  resolve next to Brando.
- **`<input name="id">`.** LiveView 1.2 warns at compile time, since it
  overrides the form's `id` property in the browser. Rename the field (to
  `_id`, say) and map it back where the form is handled.
- **Visitor addresses behind the proxy.** Add `:x_headers` to the
  `connect_info` of the endpoint's `/live` socket, so `LiveForm` counts
  visitors by their own address and not the proxy's:
  `websocket: [connect_info: [:peer_data, :x_headers, :user_agent, session: @session_options]]`.
  In a generated `LockdownController`, call `Lockdown.password?(conn, password)`
  so password attempts are limited.

Then validate and commit the source migration:

```shell
mix format
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

`mix format` runs LiveView 1.x's HEEx formatter, which rewrites `<%= expr %>`
in HEEx templates to `{expr}`; expect those changes in the same commit.
Before `mix test`, check the Repo `url:` in `config/runtime.exs`, which
`mix brando.migrate55` warns about: see
[Test and development databases](#test-and-development-databases).

### Admin assets

A 0.54 site's `assets/backend` is usually yarn, Vite 5 and Svelte 4, and the
source tasks leave it alone. Bring it to the current template, review the diff,
then install and build:

```shell
mix brando.gen.backend --upgrade
mix brando.assets.setup --backend-only
```

The first takes the template's package versions and Vite config, moves the
admin's CSS build to native EuropaCSS, and replaces the Dockerfile's
`assets_backend` stage with the template's pnpm stage, keeping the
application's own packages, CSS and other existing files. Its notices name
what it kept and why ([What the source tasks change](#mix-brando-gen-backend-upgrade)
has the details). Check that the frontend builds on the Node of the
`assets_frontend` stage.

The admin moves to pnpm 12: its `packageManager` becomes `pnpm@12.15.0`, and
pnpm's settings move from `package.json`'s `pnpm` field, which pnpm 11 stopped
reading, to `assets/backend/pnpm-workspace.yaml`: the application's own
`overrides`, and its `onlyBuiltDependencies` and `ignoredBuiltDependencies`
as `allowBuilds` (`true` and `false`). Any other setting in that field, or an
existing `pnpm-workspace.yaml` of the application's own, gets a notice naming
what to move. The Dockerfile's `assets_backend` stage copies the file before
`pnpm install`.

`assets/frontend` keeps the pnpm its `packageManager` names; pnpm 12 runs that
version for it. To move the site to pnpm 12 as well, set its `packageManager`
to `pnpm@12.15.0`, move its `pnpm` field to `assets/frontend/pnpm-workspace.yaml`
as above (Brando's site template allows no build scripts and declines
`core-js`'s with `core-js: false`), copy that file in the Dockerfile's
`assets_frontend` stage with `package.json` and `pnpm-lock.yaml`, install
`pnpm@12.15.0` there, and run `pnpm install` to update the lockfile.

`--backend-only` leaves `assets/frontend` alone, for a frontend that still uses
yarn or its own build; without it the task installs and builds both with pnpm.
Commit the `assets/backend/pnpm-lock.yaml` it writes: the Docker build installs
from it.

Port the application's own admin CSS as [Native EuropaCSS](#native-europacss)
describes; the task lists the `@row` and `@container;` it finds. Check it:

```shell
cd assets/backend
pnpm exec europa migrate css/app.css --from 1.0.0-beta.6 --config europa.json5 --check
```

`mix brando.doctor` reports admin assets from an older BrandoJS, or not on the
native EuropaCSS packages at the versions Brando's template pins, with the fix
for where the admin takes BrandoJS from ([BrandoJS](#brandojs)).

The site's own frontend keeps building on the legacy EuropaCSS PostCSS plugin;
moving it is optional ([Site frontend](#site-frontend)).

## 3. Generate and review database migrations

Without named environments, `mix brando.upgrade.database` runs this section and
section 4. Each run works out where the database stands, runs the next steps
below, and stops where they have you review something; it writes the Blueprint
migrations with `--reconcile`. Run it again after each stop until it says the
database phase is done; `--dry-run` shows the plan. With named environments,
run the steps by hand.

An application on a 0.55 development build starts here, after rerunning
`mix brando.migrate55`, to pick up the migrations added since it last upgraded.

1. **Copy Brando's missing migrations**, then review and commit them:

   ```shell
   mix brando.gen.migrations
   ```

   There are no `brando_206` or `brando_208` migrations: both numbers were
   never used. `mix brando.migrations.check`, run against the database you
   will migrate, lists copies made earlier that have not run yet and differ
   from Brando's templates; `mix brando.gen.migrations --refresh` rewrites
   every copy that differs, run or not (see
   [Test and development databases](#test-and-development-databases)).

2. **Fabric deployments: give the application's role the Oban enum.**
   `brando_153` (Oban v14) fails with `must be owner of type oban_job_state`
   when the type belongs to another role, as with the bundled `fabfile.py`.
   Update the `fabfile.py`'s `grant_db` task to Brando's and run
   `fab <env> grant_db` before migrating, or run this once as a superuser:

   ```sql
   ALTER TYPE public.oban_job_state OWNER TO <your_app_db_user>;
   ```

3. **Run Brando's migrations** on the rehearsal copy, then, with Villain
   content, check the conversion:

   ```shell
   mix brando.migrate
   mix brando.check.legacy_conversion
   ```

   The check compares every entry's Villain JSON with the blocks made of it
   and exits with status 1 while anything is missing. When it reports images
   lost in the conversion, run `mix brando.repair.legacy_media --dry-run`,
   then without `--dry-run`, while the Villain columns are still there (see
   [Legacy snapshots](#legacy-snapshots)).

4. **Generate the Blueprint migrations.** They add the columns 0.55's
   `trait :meta`, `trait :creator` and `trait :scheduled_publishing` bring to
   application tables, and anything else a Blueprint changed. Handle each
   Blueprint according to its history:

   - With valid generated migrations and snapshots, run
     `mix brando.gen.blueprint_migration --all` and review the diffs, or plan
     one with `mix brando.gen.blueprint_migration MyApp.Domain.Schema`. `--all`
     also proposes a create-table migration for every Blueprint without a
     snapshot, so rebaseline existing tables first (next point).
   - For an existing table with no generated Blueprint snapshot, do not apply
     the create-table migration that a first normal run would propose.
     Independently verify the live table, columns, indexes, and foreign keys
     against the current Blueprint, then establish the known-good baseline with
     `--rebaseline`.
   - With snapshots older than the blocks conversion (a 0.53 site), generate
     with `mix brando.gen.blueprint_migration --all --reconcile` against the
     migrated copy of production. It fits each migration to the database and
     keeps the Villain columns. With named environments `--reconcile` is
     refused: edit the migrations by hand. [Legacy snapshots](#legacy-snapshots)
     covers both.
   - For a genuinely new table, use the normal generator output.
   - For a table, root primary-key, physical primary-key source, or existing
     column-level primary-key change, write and test a hand-written Ecto
     migration, then rebaseline. The generator refuses to infer these
     operations.

   A migration that adds the Creator trait's `edited_at` to an existing table
   backfills it from `updated_at`. A trait removed from a Blueprint without a migration (Translatable,
   for example) surfaces as a proposal to drop its columns, indexes and tables:
   `language`, its index, `*_alternates`. That is correct but destructive.
   Decide whether the data can go before accepting it, or put the trait back
   for now; `--reconcile` keeps the ones that hold data. See
   [Blueprint migrations](blueprint_migrations.md) for renames, physical Ecto
   sources, relation corrections, type/default conversions, custom paths, and
   fail-closed history recovery.

5. **Review before touching a shared database:**

   1. Read every generated `up/0` and `down/0`.
   2. Resolve data prerequisites such as duplicate unique values and null
      backfills.
   3. Run all migrations forward, backward, and forward again on a disposable
      database.
   4. Commit each Blueprint, Ecto migration, and snapshot together.

6. **Run them:**

   ```shell
   mix brando.migrate
   # With named environments, after public migrations:
   mix brando.migrate --tenants
   ```

   `mix brando.migrate` runs the public migrations. Brando's own migrations
   that work "in every environment" (their notes in the CHANGELOG say so)
   change `public` and every environment schema in that run. `--tenants` then
   runs the tenant migrations in each environment, including the Blueprint
   migrations of content stored there; tenant discovery needs the public
   migrations first.

   Restoring an environment archive taken before such a migration runs the
   migration on the restore. The restore is refused, with nothing restored,
   when the archive cannot be brought up to date or when the application
   changed its copy of the migration (an unchanged copy of an earlier Brando
   version is fine).

## 4. Repair derived data

`mix brando.upgrade.database` runs this section after the migrations, once you
answer yes to "Resave every entry, sync identifiers and rebuild the search
index". Publish the fragments first.

1. **Publish the fragments the site shows.** Public pages render only
   published fragments: a draft, pending or disabled `partials/footer` renders
   empty. An entry that embeds a fragment through `{% fragment %}` or a block
   template stores it as rendered at its save, so it shows a fragment
   published later only on its next save. To list unpublished fragments, run
   this in `iex -S mix` against each environment's database (in a release,
   `bin/<app> remote`):

   ```elixir
   import Ecto.Query

   unpublished = fn prefix ->
     Brando.Repo.all(
       from(f in Brando.Pages.Fragment,
         where: (f.status != :published or is_nil(f.status)) and is_nil(f.deleted_at),
         select: {f.parent_key, f.key, f.language, f.status}
       ),
       prefix: prefix
     )
   end

   # Without named environments:
   unpublished.(nil)

   # With named environments, once for each environment schema:
   for site <- Brando.Tenant.Registry.list_sites(), environment <- site.environments,
       do: {site.key, environment.key, unpublished.(Brando.Tenant.prefix(site, environment))}
   ```

   `get_fragments/1` with `status: :published` can keep or drop the option.

2. **Rebuild persisted block rendering and identifiers**, and record which
   images already match their config:

   ```shell
   mix brando.entries.resave
   mix brando.identifiers.sync
   mix brando.images.adopt --dry-run
   mix brando.images.adopt
   ```

   They mutate application data and `mix ecto.rollback` does not reverse them:
   run them against staging first and inspect counts and representative
   entries. All accept `--yes`, for a script.

   `mix brando.images.adopt` records the config of each image whose files
   already match it, so Utilities → Recreate changed images recreates only the
   ones that differ. It reads the image files, so run it where the media is (a
   copy of the server's `media` folder in a rehearsal checkout). In a checkout
   without the production media every image differs, and `mix brando.doctor`
   and Utilities recommend recreating them all: decide from
   `mix brando.images.adopt --dry-run --verbose` with the real media instead
   ([Media](media.md#images-made-before-fingerprints)).

3. **Restart the server**, or use Configuration → Cache → Empty all caches in
   its admin. The tasks write to the database, and a server that ran meanwhile
   keeps serving the pages it cached before (pages are cached without expiry).

4. **Fix templates that print image texts raw.** Image alt text, title and
   credits are translated maps, and a template that prints them without the
   `i18n` filter (`{{ entry.cover.alt | i18n }}`) shows the raw map. Module,
   container and menu templates live in the database, so the source tasks
   cannot see them; list the ones to fix with:

   ```shell
   mix brando.check.image_texts
   ```

5. **Rebuild the admin search index** once in each environment, from
   Configuration → Utilities → Search index. `brando_212` creates the table
   empty. `mix brando.upgrade.database` rebuilds it for you.

6. **Oban, in an application that sets `config :brando, Oban` itself.** Its
   configuration replaces Brando's whole default, so it needs every queue and
   cron job Brando runs. Without them, webhooks, notifications and the search
   index never update, uploads and orphaned media are never cleaned up, and
   entries whose publish date passed with no job (clones, restores) stay
   unpublished. Brando's default, from `Brando.Supervisor`, with the
   application's own queues and jobs added:

   ```elixir
   config :brando, Oban,
     queues: [
       # …the application's queues
       default: [limit: 1],
       environment_operations: [limit: 1],
       ssg_builds: [limit: 1],
       image_processing: [limit: 1],
       upload_reaping: [limit: 1],
       content_events: [limit: 1],
       webhooks: [limit: 5],
       notifications: [limit: 2],
       search_index: [limit: 2]
     ],
     cron: [
       crontab: [
         # …the application's jobs
         {"0 2 * * *", Brando.Worker.SitemapGenerator},
         {"0 3 * * *", Brando.Worker.SoftDeletePurger},
         {"0 4 * * *", Brando.Worker.RevisionPurger},
         {"15 4 * * *", Brando.Worker.DraftPurger},
         {"20 4 * * *", Brando.Worker.ActivityPurger},
         {"30 4 * * *", Brando.Worker.VideoUploadReaper},
         {"45 4 * * *", Brando.Worker.UploadIntentReaper},
         {"0 5 * * *", Brando.Worker.MediaOrphanCleanup},
         {"15 5 * * *", Brando.Worker.FormSubmissionPurger},
         {"25 5 * * *", Brando.Worker.NotFoundPurger},
         {"35 5 * * *", Brando.Worker.WebhookDeliveryPurger},
         {"*/10 * * * *", Brando.Worker.ScheduledPublishingSweep}
       ],
       timezone: "Etc/UTC"
     ]
   ```

7. **With group authorization, grant the Notifications permission**
   (`brando.notifications.manage`) to the groups that should manage
   notification routes; no existing group has it. See
   [Notifications](notifications.md).

`mix brando.doctor` reports migrations that have not run, in `public` and in
each environment, and Oban queues that are missing. Under Module entry paths it
lists module code that still reads a multi module's entries the 0.53 way
(`{{ link.data.vars.url }}` in `{% for link in entries %}`), which `brando_219`
could not rewrite: each entry is a block, so change `.data.vars.` to `.vars.`
and `.data.refs.` to `.refs.`, then run `mix brando.entries.resave`.

## 5. Reconcile Gettext catalogs

`mix brando.migrate55` has already completed incomplete `Plural-Forms` headers
in existing catalogs, and copied the translations of each Blueprint's 0.53
domains into the one it uses now. 0.53 translated a Blueprint's strings into
`<domain>_<schema>_naming`, `_forms` and `_listings`; since 0.54 they are all
extracted to `<domain>_<schema>`, so `menu_menuitem_naming.po` and
`menu_menuitem_listings.po` became `menu_menuitem.po`. It also copied the
`default` domain's translations of the labels `mix brando.migrate54` moved from
`gettext/1` to `t/1`. The merge keeps a translation only when the new domain's
`.po` already has it, so run the task before extracting. It reports messages
the old domains translated differently.

Then run:

```shell
mix brando.gettext.reconcile --dry-run
mix brando.gettext.reconcile
```

It extracts the messages, merges each Gettext backend's existing locales (and
only those, with the `Plural-Forms` header the locale's catalogs use), fills an
empty single-line translation from the same `msgid` in a sibling catalog, and
deletes the old `_naming`/`_forms`/`_listings` catalogs the merge leaves
empty. It then lists, per Blueprint domain and locale, the translations
carried over and the ones dropped because their `msgid` is no longer in the
source; on a 0.53 site these are mostly the old generator's action labels
("Edit vacancy", "Are you sure?"). Review the catalog diff before committing.
It does not guess multiline, plural, or contextual translations; reconcile
those by hand.

[Gettext by hand](#gettext-by-hand) has the same steps without the task.

## 6. Final deployment gate

Before deploying, run the application unit suite and its full serial E2E suite,
including a clean database reset. Verify at least forms, listings, uploads,
LivePreview, block rendering, identifier-backed selections, rollback, and a
second forward migration. If the application has no meaningful tests, the
public-page comparison below is the gate.

Open an entry of every Blueprint in the admin: on one 0.53 site, two of the
four crashes showed only there. Restart the server after any CLI repair task
(`mix brando.entries.resave`, `mix brando.identifiers.sync`, a repair of your
own) first, since it keeps serving the pages it cached.

Compare the public pages before and after the upgrade with
`mix brando.upgrade.snapshot`, against the old site started in
[Keep the old site running](#keep-the-old-site-running) (on port 4000, say).
In the upgraded application, once its database is migrated:

```shell
mix brando.upgrade.snapshot urls --output urls.txt --base-url http://localhost:4000
mix brando.upgrade.snapshot capture tmp/before --base-url http://localhost:4000 --urls urls.txt
# start the upgraded site on another port
mix brando.upgrade.snapshot capture tmp/after --base-url http://localhost:4001 --urls urls.txt
mix brando.upgrade.snapshot diff tmp/before tmp/after
```

`urls` picks, for each Blueprint other than pages, the entry with the most
blocks in each language. With `--base-url` it asks the old site for each
entry URL, leaves out those it answers with 404 (a language whose routes are
switched off, for instance) and tries the next-heaviest entry instead. Add
entries you know are unusual to the list by hand.

It reports status, visible text, `<head>` tags and element structure
separately, so a moved `data-src` or a reordered list shows even when the
text is the same. Then open a page with a video in a browser: a site's own
video script may read markup 0.55 changed (see the CHANGELOG's Breaking
notes).

If the tasks ran with an earlier Brando revision, also go through
[Check what the tasks may have missed](#check-what-the-tasks-may-have-missed).

If the upgrade must be abandoned, restore both the pre-upgrade application
release and database backup. Code rollback plus `mix ecto.rollback` does not
undo entry resaves, identifier synchronization, or manual Gettext changes.

## Reference

The sections below hold detail the main path links to: situational steps,
by-hand alternatives to the tasks, and what the tasks write.

### Dependencies by hand

`scripts/prepare_055_deps.exs` applies the constraints below to the packages
the application declares, bumps `ex_chimp` to 0.2, drops `only: :test` from
`floki`, removes `timex` once `lib/` no longer calls it, adds Igniter, sets
`elixir: "~> 1.18"` and `listeners: [Phoenix.CodeReloader]` in `project/0`,
and points the Brando dependency at the checkout or commit:

```elixir
# mix.exs
{:brando, path: "/absolute/path/to/brando"},
# or
{:brando, github: "brandocms/brando", ref: "<commit sha>"},
```

By hand, change every one of these the application declares before fetching
(the versions are Brando's own, from its `mix.exs`):

```elixir
# mix.exs
{:phoenix, "~> 1.8.15"},
{:phoenix_live_view, "~> 1.2.0"},
{:phoenix_html, "~> 4.0"},
{:ecto, "~> 3.14"},
{:ecto_sql, "~> 3.14"},
{:postgrex, "~> 0.20"},
{:gettext, "~> 1.0"},
{:floki, "~> 0.32"},
{:swoosh, "~> 1.17"},
{:igniter, "~> 0.8", only: [:dev, :test]},
```

Brando pins `phoenix` 1.8.15 and `phoenix_live_view` 1.2.12 exactly. If the
application also declares `sentry` (`~> 14.0`), `oban` (`~> 2.23`), `cachex`
(`~> 4.0`), `image`, `req` or another of Brando's dependencies, compare it with
Brando's `mix.exs` as well. In particular:

- Gettext 1.0 is required; `~> 0.26` does not resolve.
- Remove `timex`. No Timex release accepts Gettext 1.0 (3.7.13 requires
  `~> 0.26`), and Brando's installer added it to sites until 2021. Replace its
  calls with `Date`, `DateTime` and `Calendar`; Brando makes the `tz`
  package Elixir's time zone database at boot.
- Drop `only: :test` from `floki` (the Phoenix generator default). Brando uses
  Floki at runtime, and `mix deps.get` stops with "Dependencies have diverged"
  while the application restricts it to tests.
- Igniter is an optional Brando dependency the source tasks are built on.
- Sentry 14 removes the `:enable_logs` and `:enable_metrics` options. A
  `config :sentry` that sets `enable_logs: true` instead sets the level to
  send in its `:logs` block (`logs: [level: :info]`); without a `:level`,
  crashes are still reported but structured logs are not. Metrics are always
  sent; drop them in a `:before_send_metric` callback to stop them. See
  Sentry's [13.x to 14.x upgrade guide](https://hexdocs.pm/sentry/upgrade-14.x.html).
- Brando depends on `ex_aws` 2.7, which accepts only hackney 4 whenever
  anything else brings hackney in. Packages still on HTTPoison or hackney 1.x,
  such as `ex_chimp` 0.1, fail with `version solving failed`. Bump `ex_chimp`
  to `{:ex_chimp, "~> 0.2.0"}`, which uses Req with the same API. Upgrade
  other such packages to a release on hackney 4 or Req, or move those calls to
  Req, which Brando already depends on.

The old lock holds packages at versions the new Brando cannot use (`swoosh`
1.14, or `elixir_make` 0.6, which `vix` and `image` cannot use), hence
`mix deps.unlock --all` before `mix deps.get`.

Brando's CI tests Elixir 1.18, 1.19 and 1.20 on OTP 27 and 28, and Brando's
own `.mise.toml` pins the versions it is developed on. The template
Dockerfile's `node:24` stages build the admin, and
[The Docker build](deployment.md#the-docker-build) has the Elixir and OTP of
each fehn 4.2 variant.

### Working against a Brando checkout

[Installing from a Brando checkout](installation.md#installing-from-a-brando-checkout) describes working against a `path:` checkout.
After editing it, run `mix deps.compile brando` and restart the server:
`mix brando.migrate55` takes `:brando` out of the endpoint's `reloadable_apps`,
so the code reloader does not pick up Brando's changes.

### BrandoJS

The admin's JavaScript, BrandoJS, comes from npm at Brando's version once
Brando is released, and from the same Brando source through Yalc for a
development version or while working on Brando. Keep the Elixir and
JavaScript sides on the same Brando revision.

With a Yalc copy, `mix brando.assets.setup --backend-only` publishes the
dependency's `assets` directory to a store under `_build` and updates
`assets/backend/.yalc`. By hand, the steps are `npx yalc publish` in Brando's
`assets`, then `npx yalc update @brandocms/brandojs` and `pnpm install` in the
application's `assets/backend`, and a restart of its Vite. Do not use
`yalc push`: it rewrites every project registered with Yalc on the machine.

`mix brando.gen.backend --upgrade` keeps where the admin takes BrandoJS from:
an npm version moves to Brando's, and a Yalc copy or linked checkout stays.
When Brando is a release and the admin still uses a Yalc copy, a notice
suggests `mix brando.assets.setup --npm`, which pins the npm release and
removes the copy. The Docker image installs BrandoJS from npm, or ships the
local `assets/backend/.yalc` when the admin uses one, so rerun the setup after
updating BrandoJS.

`mix brando.doctor` suggests the fix for each source: `mix brando.assets.setup
--npm` for npm (`--local` while Brando is a `-dev` version, which has no npm
release), `npx yalc update` and `pnpm install` for a Yalc copy. On a yarn-era
`assets/backend` that is not enough: run `mix brando.gen.backend --upgrade`
first, then `mix brando.assets.setup --backend-only`. Its Admin CSS compiler
check warns while `assets/backend` is not on the native EuropaCSS packages at
the versions Brando's template pins (the legacy `@brandocms/europacss`, a Yalc
copy, other versions, or an install older than `package.json`), and
`mix brando.migrate55` names the same in its notice.

### Legacy snapshots

A snapshot written before Brando's blocks conversion describes a table the
Brando migration chain has changed since. Diffed against it, the generator
proposes storage that already exists (`create table(:projects_blocks)`,
`rendered_blocks`) and drops the legacy Villain columns (`data`, `html`,
`*_data`). It warns when a planned table or column already exists in the
database or a planned drop looks like a Villain column. `mix brando.migrate55`
prints the order below when it sees `brando_102` or older as the newest copied
migration, or a snapshot with a Villain field:

1. `mix brando.gen.migrations`
2. `mix brando.migrate` (Brando's own migrations, the blocks conversion among
   them)
3. `mix brando.check.legacy_conversion`
4. `mix brando.gen.blueprint_migration --all --reconcile`, against a migrated
   copy of production
5. Review, with a rollback and forward
6. `mix brando.migrate` again

`mix brando.check.legacy_conversion` compares, for every entry, the Villain
JSON with the blocks the upgrade migrations made of it (blocks at each level,
vars and their values, refs, table rows, fragments) and names what is missing,
such as `pages #12 › block 3 (module "Values") › vars: heading missing`. Run it
straight after `mix brando.migrate`; it exits with status 1 while anything is
missing. Its documentation lists what it leaves out, such as rendered HTML,
which the public-page comparison in section 6 covers.

It also checks that media refs kept their media: a picture whose Villain data
had a `path` has an image, a gallery has as many images as Villain listed, a
video has a video. A `brando_133` copied before Brando fixed it linked a
picture to an image by `path` only, and left it empty when the image had no row
(deleted, or in the trash); galleries lost such images too. The check reports
those as `ref pic: legacy image images/site/posts/1n60vo3o9p06.jpg has no image
now (lost in the conversion, or removed by an editor since)`. Repair them soon
after the upgrade, while the Villain columns are there:

```shell
mix brando.repair.legacy_media --dry-run
mix brando.repair.legacy_media
```

It links the image the Villain data names, or makes its row from that data,
and adds missing gallery images in their places. It writes only where it can
tell the media was lost in the conversion: it skips, with the reason, an entry
whose blocks no longer line up with Villain's, an entry, block or gallery
edited since the conversion, and, once the conversion is more than 30 days
old, any image it would have to make, as emptying the trash leaves no trace of
what an editor deleted. Run the check again afterwards; what it skipped is for
an editor. A site that has resaved its entries since resaves them again.

`--reconcile` reads the database: it guards what exists with
`*_if_not_exists`, turns the `create table` of an existing table into an
`alter`, or records only a baseline when the table already matches, leaves out
existing `references(...)` columns, keeps every Villain column, every column
or table that holds data (with a comment giving the count) and anything the
Blueprint's generated migrations did not create (dropping the `NOT NULL` of a
kept column the schema no longer writes), and keeps pre-existing storage out of
`down/0`. Run it against the production database or a current copy: the data
it reads decides what is kept, and each migration names that database in its
first comment. It prints what it did per file; see
[Reconciling with an existing database](blueprint_migrations.md#reconciling-with-an-existing-database).
Still by hand: step 1 below for types, defaults and nullability
(`--reconcile` compares names only), step 7, a foreign key missing from an
existing column (a comment in the migration names it), and whether to drop the
columns and tables kept for their data, later, in a migration of your own.

With named environments `--reconcile` is refused, so edit each generated
migration by hand:

1. Compare `\d table` in a migrated copy of production with every generated
   operation.
2. For a table or index that already exists, use `create_if_not_exists`, and
   `add_if_not_exists` for an existing column.
3. Rewrite a `create table(...)` of a table that already exists (one that
   predates Blueprint snapshots, so the generator saw no history) as an
   `alter table(...)` that adds only what `\d` lacks, such as the Creator
   trait's `edited_at` and `updated_by_id`. A table that already matches the
   Blueprint needs no migration: establish its baseline with `--rebaseline`.
4. Do not combine `add_if_not_exists` with `references(...)` on a column that
   already exists. PostgreSQL skips the column but still adds the named
   foreign-key constraint, and stops with `constraint ... already exists`.
   Leave the column out, or drop the constraint first with
   `drop_if_exists constraint(...)`.
5. Keep `data`, `html` and the other Villain columns until the converted
   content is verified on production data with
   `mix brando.check.legacy_conversion`. They are the only record of what the
   conversion started from, and repairs need them. Keep any other column the
   plan drops while it still holds data, such as one removed from the
   Blueprint years ago without a migration; count its non-null values before
   deciding.
6. In `down/0`, undo only what `up/0` added: leave out the tables, indexes
   and columns that existed before the migration.
7. Roll back and forward once on a scratch copy. A second
   `mix brando.gen.blueprint_migration --all --dry-run` should then propose
   no changes.

### Test and development databases

A site that copied Brando migrations years ago may not replay them from an empty
database: early copies use modules that no longer exist (such as
`Brando.Sequence.Migration`), and `mix brando.gen.migrations` leaves an
existing copy as it is. Production is unaffected, because it only runs the new
migrations.

Copies of Brando's data migrations made before this release can also stop an
empty database with `relation "…" does not exist`, naming one of the
application's own tables (`brando_53` is the first). They find the
application's tables through its current Blueprints, and on an empty database
those tables are created by later migrations. The current templates skip a
table that is not there yet. Rewrite the copies that differ from them, keeping
their names and timestamps, and review the diff, since a copy may have been
edited on purpose:

```shell
mix brando.gen.migrations --refresh
```

A database that has already run a copy is not affected by rewriting it.

Alternatively, keep the copies as they are and load test and development
databases from a `structure.sql`, so they never replay the chain: migrate a
copy of production, run `mix ecto.dump` (it writes `priv/repo/structure.sql`),
and commit the result. The usual `test` alias runs
`ecto.migrate` on an empty database, which replays every migration, so load the
dump before it:

```elixir
# mix.exs, in aliases/0
test: ["ecto.create --quiet", "ecto.load --skip-if-loaded", "ecto.migrate", "test"]
```

Check `config/runtime.exs` before running the alias. The 0.53 installer's
sets the Repo's `url: System.get_env("BRANDO_DB_URL")` in every environment,
and a `url:` overrides the `database:` in `config/test.exs`. Until it is
guarded with `if config_env() != :test do … end`, `mix test` uses, and its
alias loads and migrates, whatever database the shell names, and
`MIX_ENV=test mix ecto.drop` drops it. `mix brando.migrate55` warns about
such a `url:`, and when `test_paths` names a missing directory;
`mix brando.doctor` checks the same in development.

With the guard in place, `--skip-if-loaded` leaves a database that already
has its migrations table alone, so if the old alias already created the test
database, drop it once (`MIX_ENV=test mix ecto.drop`), or give the test
database a new name instead. Phoenix's generated `config/test.exs` appends
`MIX_TEST_PARTITION` to it (`"myapp_test#{System.get_env("MIX_TEST_PARTITION")}"`),
so `MIX_TEST_PARTITION=_055 mix test` creates and loads `myapp_test_055`; to
keep the new name without the variable, change it in `config/test.exs`.
`ecto.migrate` then runs only the migrations newer than the dump.

### Gettext by hand

`mix brando.gettext.reconcile` is `mix gettext.extract`, then
`mix gettext.merge priv/gettext/<backend> --locale <locale>
--plural-forms-header "nplurals=2; plural=(n != 1);"` per backend and locale,
then `bash scripts/sync_gettext.sh priv/gettext/<backend>/<locale>/LC_MESSAGES`.
Avoid `mix gettext.extract --merge DIR --locale LOCALE` here: it merges every
backend it extracted, whatever directory it is given, and creates `LOCALE` in
each one (a `frontend/en` or `backend/se` the site never had).

### Named environments

Named environments and multi-site tenancy are opt-in. Projects staying in the
default `tenancy_mode: :none` keep their existing content and media in the
classic locations; they apply the ordinary Brando-owned public migrations, but
do not add the tenant plug, create tenant migrations, provision
site/environment records, or copy data with `mix brando.migrate_to_tenant`.

An application choosing tenancy runs, after this source upgrade,
`mix brando.setup.tenancy --mode single --site-key my-site` or
`mix brando.setup.tenancy --mode multi`. That Igniter task makes the
application source changes without running migrations or copying live data;
[Tenancy and environments](tenancy_and_environments.md) has the ordered
conversion workflow.

### Review a generated Florist configuration

When both `deployment.cfg` and `fabfile.py` exist and there is no Florist
configuration yet, `mix brando.migrate55` writes `florist.config.exs` from
their literal settings and adds `plug Brando.Plug.Health` to the endpoint;
[Migrating from Fabric](deployment.md#migrating-from-fabric) says what it
carries over and where it looks. The configuration holds no passwords: before
loading it, export `FLORIST_DB_PASSWORD_PROD` and, when generated,
`FLORIST_DB_PASSWORD_STAGING`.

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
5. Confirm `plug Brando.Plug.Health` sits in the endpoint before the router.
   Florist checks `/health` during deploys; without the plug the check never
   passes.
6. Configure rclone manually if the fabfile used it. Its prompted credentials
   and deployment-specific bucket paths are not migrated.
7. Verify the Docker image contains the standard Mix release tarball at the
   path expected by Florist's `release_builder: :elixir`, then rehearse build,
   copy, upload, unpack, migrate, restart, and rollback on staging.

The legacy files remain available as an audit trail. Remove them only in a later
commit after the Florist deployment has been proven.

### Native EuropaCSS

The admin's CSS builds with the native (Rust) EuropaCSS compiler through its
Vite plugin, `@brandocms/vite-plugin-europacss`, in place of the legacy
`@brandocms/europacss` PostCSS plugin. `mix brando.gen.backend --upgrade` makes
these changes to `assets/backend`, keeping the application's CSS and its own
configuration:

- `package.json` drops `@brandocms/europacss` and `autoprefixer` and adds the
  Vite plugin and `@brandocms/europacss-cli`, both from npm at an exact
  version; `vite.config.js` (replaced) runs the plugin with `europa.json5`.
- `europa.json5` is created. It extends Brando's preset, so the application
  lists only what it changes:

  ```json5
  {
    extends: './node_modules/@brandocms/brandojs/europa.json5',
    theme: { colors: { dark: '#1d2422', blue: '#3a5f8a' } },
  }
  ```

  Objects merge key by key with the preset's; arrays and plain values replace
  them. The preset sets `nesting: 'expanded'`, so nested rules under a
  selector list compile to plain lists, each with its own specificity, as the
  legacy compiler wrote them, and `responsiveOrder: 'generated-last'` (below).
  Its `migration: { mediaPacking: 'none' }` tells `europa migrate` that the
  0.13 build did not pack media queries, so it skips the warnings that assume
  packing; the compiled CSS is unaffected.
- `postcss.config.cjs` and `europa.config.cjs` are removed when they are an
  earlier template's, unchanged. An application's own is kept with a notice:
  move its settings into `europa.json5` (`pnpm exec europa migrate-config
  europa.config.cjs -o converted.json5` converts static ones) and its PostCSS
  plugins into `vite.config.js`, then delete it. The converter warns that
  `theme.typography.paddingDivider` is deprecated: it fed
  `@column-typography`, which EuropaCSS removed in 0.2.0, so it had no effect
  in 0.13 either. Delete it unless the application's CSS reads it with
  `theme()`. `lineHeight` (the default for `vertical-rhythm()`) and `sections`
  (applied with `@unpack`) remain supported.

`@brandocms/europacss-cli` provides the compiler: pnpm installs its
executable for the machine it runs on from the lockfile's optional
dependencies (macOS, Windows, and Linux with glibc or musl, x64 and arm64), so
no Rust toolchain is needed. Install on the machine that builds, as the
template Dockerfile does, rather than copying `node_modules` between
platforms, and never with `--no-optional`. The CLI is `pnpm exec europa` in
`assets/backend`.

The application's admin CSS needs these changes; the upgrade task lists the
`@row` and `@container;` it finds:

- **Cascade layers.** The admin's styles are in the layers `reset, vendor,
  brando, app`, in that order. Put the application's rules in `@layer app { … }`
  and declare the order first, as the template's `css/app.css` does:
  application rules then outrank Brando's whatever their selectors. Unlayered
  rules outrank every layer. `!important` reverses layer order: an
  `!important` in Brando's layer outranks one in `app`.
- **`@row`** is gone. Write out what 0.13 compiled it to; `gap` is not
  equivalent where children set their own margins:

  ```css
  .row {
    display: flex;
    flex-wrap: nowrap;            /* `wrap` for `@row N/wrap` */

    > * {
      @space margin-left 1;

      &:nth-child(2n+1) {         /* `@row N`: Nn+1; bare `@row`: 1 */
        margin-left: 0;
      }
    }
  }
  ```

- **`@container;`** is a CSS container query: use `@space container;`.
- **Suffix nesting** (`&__title`, `&-pin`) is not CSS nesting. Write the full
  class; `pnpm exec europa migrate --fix` rewrites the simple cases.
- **`@keyframes` inside a rule** is an error: move it outside the selector.
- **Responsive order is 0.13's.** The preset sets `responsiveOrder:
  'generated-last'`: a hand-written `@media` stays where it is written, and
  media from Europa's directives (`@space`, `@fontsize`, `@responsive`…)
  comes after the plain rules of the stylesheet, as 0.13 appended it. Keep
  it: the application's `europa.json5` compiles Brando's CSS as well, and
  EuropaCSS's default, `'all-last'`, would move Brando's hand-written `@media`
  after its plain rules too.
- Package imports (`@import 'pkg/file.css'`) and Vite aliases work: the Vite
  plugin resolves them.

Check the stylesheet, then compare the old and new builds in a browser:

```shell
cd assets/backend
pnpm exec europa migrate css/app.css --from 1.0.0-beta.6 --config europa.json5 --check
pnpm exec europa compare http://localhost:4000/admin --before old-admin.css --after new-admin.css \
  --stylesheet /assets/admin/admin-<hash>.css --viewport 1440x900 --viewport 390x844
```

`europa migrate` follows package imports from `node_modules`, as the Vite
plugin does. Keep a copy of the CSS the legacy build wrote before upgrading;
`europa compare` swaps it into a logged-in page (see EuropaCSS's guide to
comparing rendered styles).

### Site frontend

`mix brando.install` writes `assets/frontend` for the native compiler as
well: the same two packages, a `europa.json5` with the site's own tokens (it
does not extend Brando's preset), and no `postcss.config.cjs` or
`europa.config.cjs`. No task changes an existing site's frontend, and moving
it is optional: a frontend on the legacy `@brandocms/europacss` PostCSS plugin
keeps building, in development and in the Docker image, and
`mix brando.doctor` checks only the admin's compiler.

To move a frontend that a 0.55 install wrote (`@brandocms/europacss`
1.0.0-beta.16), work in `assets/frontend`:

1. Keep a copy of the CSS the current build wrote
   (`priv/static/assets/main-<hash>.css`) to compare against.
2. Swap the packages, then convert the config. `migrate-config` converts a
   static `europa.config.cjs` and never overwrites:

   ```shell
   pnpm remove @brandocms/europacss postcss postcss-reporter css-mqgroup
   pnpm add -D --save-exact @brandocms/vite-plugin-europacss@0.1.0-beta.0 @brandocms/europacss-cli@0.1.0-beta.0
   pnpm exec europa migrate-config europa.config.cjs -o europa.json5
   ```

   The plugin needs Node 22.12 or 24 (`engines.node` in `package.json`). Delete
   `europa.config.cjs` and `postcss.config.cjs` once `europa.json5` is
   reviewed.
3. Copy the template's `vite.config.js`, or make the same changes to the
   site's own: add `europa({ config: './europa.json5', targets: ['defaults'] })`
   to `plugins`, set `css.postcss` to `{ plugins: [] }`, and remove the
   `HMREuropa` plugin. The Vite plugin watches `europa.json5` and updates the
   CSS when it changes, with no page reload.
4. Check the stylesheet, review what it reports (below), then build and
   compare the builds in a browser as for the admin above:

   ```shell
   pnpm exec europa migrate css/app.css --from 1.0.0-beta.16 --config europa.json5 --check
   pnpm build
   pnpm exec europa compare http://localhost:4000/ --before old-main.css \
     --after ../../priv/static/assets/main-<hash>.css \
     --stylesheet /assets/main-<hash>.css --ignore-custom-properties --settle 1200 \
     --viewport 390x844 --viewport 1024x900 --viewport 1440x900
   ```

   `--settle 1200` waits out the header's entrance animation, which otherwise
   stops the comparison with "DOM changed during comparison".

The check exits with status 1 for as long as any finding is unresolved, and
some of its findings are correct CSS: it still exits 1 on the 0.55 template's
own native stylesheet. What it reports for a frontend the 0.55 installer
wrote:

- **Fix first: `EU_MIGRATION_INCOMPLETE`.** Two rules stop the analysis, and
  the order findings below appear only once both are fixed:
  - `theme(spacing.radius.regular)` (`EU_FUNCTION`): a breakpoint map is not a
    CSS value. The legacy build wrote `[object Object]`, which browsers
    dropped. Use `@space border-radius radius.regular;`.
  - `@extend .plain` in `cookies.css` (`EU_EXTEND`): `@extend` takes
    `%placeholder`s only, and no `.plain` rule exists, so it never extended
    anything. Delete it.
- **Fix: `EU_MIGRATION_BUNDLE_ORDER`** on `@europa arrows; @europa base;` at
  the end of `app.css`. Bundles expand where they are written, so the reset
  would outrank the site's rules. `@import`s have to come first, so move the
  bundles to a file imported before the others, as the template's
  `css/includes/bundles.css` does. The finding stays after the move: the check
  reports every bundle, wherever it is.
- **Expected: `EU_MIGRATION_BREAKPOINT`** (six related findings). Named
  ranges end at `< next` where the legacy build wrote `<= next - 1px`, which
  closes the one-pixel gap between them. Nothing to change.
- **Review: `EU_MIGRATION_ORDER`** on a plain declaration after a directive in
  the same rule (`line-height` after `@fontsize`), and on a `$sm` override of a
  directive's value (the mobile `gap`s, the ledger's `padding-left: 0`). The
  legacy build never applied them; the native one does. Keep one for the value
  it names, or delete it to keep what the page showed. The 0.55 template keeps
  the line heights and the mobile gaps, writing the gaps as
  `@space gap sm $sm;`. Where a `$sm` rule only undid a desktop treatment, it
  scopes the treatment instead: the ledger's divider is
  `@space padding-left md $lg;` with a `$lg` border. The cards and tips use
  `@space column-gap 1 $lg;` in place of `@space gap 1` with `row-gap: 0`,
  and the cards space their rows with `@space row-gap xl $lg;` rather than a
  bottom margin. The check still reports the order of the template's line
  heights and mobile gaps: they are correct.

The check does not report two order changes, so look for them in the site's
own CSS:

- `@color border-top bone.hair;` followed by `border-top: 1px solid;`. The
  legacy build wrote the directive's colour after the shorthand, so the token
  won; natively the shorthand resets the colour to `currentColor`. Put the
  token in the declaration: `border-top: 1px solid theme(colors.bone.hair);`.
- `@color fg token;` followed by `color: …;` in the same rule: the plain
  `color` lost in the legacy build and wins natively.

### Check what the tasks may have missed

The source tasks and checks find the following. A site that ran
`mix brando.migrate54`, `mix brando.migrate55` or the conversion migrations
with an earlier Brando revision can still have them: each let a 0.53 site
compile and then fail at runtime or lose content. Check each one from the
application's root:

1. **`.html` on fragments and partials.** Fragments have no `html` since the
   blocks conversion, so a read such as `@partials["footer"].html` raises a
   `KeyError` on every page that renders it.

   ```shell
   grep -rnE '(\]|\w)\.html([^.a-zA-Z_"]|$)' lib
   ```

   Read `rendered_blocks` instead, or render the fragment with
   `Brando.Pages.render_fragment/1`.
2. **`:entries` relations mapped to `entry_id`.** An `:entries` relation
   (`relation :related_entries, :entries`) holds join rows that point at an
   identifier, so `Enum.map(entry.related_entries, & &1.entry_id)` raises a
   `KeyError`.

   ```shell
   grep -rnE 'relation :\w+, :entries' lib
   grep -rn '\.entry_id' lib
   ```

   For each relation the first command lists, preload the identifier
   (`preload: [related_entries: :identifier]`) and map
   `& &1.identifier.entry_id`.
3. **`:multi_select` on a `has_many` without `relation:`.** The admin form
   crashes on open with "Multi selects for a :has_many relation needs a
   `relation_key` and a `relation`".

   ```shell
   grep -rn -A6 ':multi_select' lib
   ```

   Give each such input `relation:` as well as `relation_key:`: the
   `belongs_to` in the join schema that `relation_key` points at
   (`relation_key: :category_id, relation: :category`).
4. **`sources:` options on an `:entries` input that mention `sequence` or
   `preload`.** The options load identifiers (`content_identifiers`), which
   have `title`, `language`, `status`, `url`, `schema`, `entry_id`, `cover` and
   `updated_at`, and no associations. An order on `sequence` crashes the form
   with `column c0.sequence does not exist`.

   ```shell
   grep -rn -A4 'sources:' lib | grep -E 'sequence|preload'
   ```

   Order by identifier columns (`%{order: "asc language, asc title"}`) and
   drop `preload:`.
5. **Module code in the database that reads `data.vars` or `data.refs`.** A
   multi-module's children are blocks, so a template that reads
   `{{ link.data.vars.url }}` in `{% for link in entries %}` renders them
   empty. `brando_219` rewrites these paths (see section 4) and leaves a
   variable it cannot follow, such as one assigned an entry and then assigned
   again; `mix brando.doctor` lists what is left under Module entry paths.
   Change `.data.vars.` to `.vars.` and `.data.refs.` to `.refs.` in each
   module it lists, then run `mix brando.entries.resave`.
6. **Refs that lost their image.** A `brando_133` copied before the fix
   emptied a picture ref whose image had no live row, and left such images
   out of galleries. `mix brando.check.legacy_conversion` lists each one, and
   `mix brando.repair.legacy_media` restores those it can tell were lost in
   the conversion (see [Legacy snapshots](#legacy-snapshots)). The legacy
   Villain column is then the only copy of that image data, so run both
   before anyone drops it.

## What the source tasks change

The diffs of `mix brando.migrate54`, `mix brando.migrate55` and
`mix brando.gen.backend --upgrade`, described. Each task lists, with file and
line, what it found and did not rewrite; [Fix what the tasks list](#fix-what-the-tasks-list)
has the fixes.

### mix brando.migrate54

`mix brando.migrate54` covers the 0.53 to 0.54 source changes. It:

- rewrites legacy Blueprint list, single, and selection datasources; trait,
  villain/block, form, input, metadata, and JSON-LD syntax; and listing queries,
  filters, actions, selection actions, and supported exports;
- preserves legacy Meta and JSON-LD path/mutator behavior
  (`meta_field "og:locale", [:language], &encode_locale/1` becomes
  `field "og:locale", fn entry -> encode_locale(get_in(entry, [Access.key(:language)])) end`);
- replaces `use Brando.Datasource`, which imported `Ecto.Query`, with
  `import Ecto.Query` in a Blueprint whose functions call its macros (`from`,
  `where` and the rest). A list and a selection datasource may still share a
  name (`list :all` beside `selection :all`): content modules name a
  datasource by its type and name;
- renames legacy listing `filter:` keys and `list_villains/0` calls on
  `Brando.Villain`;
- rewrites every legacy LivePreview target with its own layout and template
  module;
- replaces `mix phx.digest` in a root Dockerfile, removes `?vsn=d` from font
  URLs in application styles/templates, and adds a missing single-Repo
  `config :brando, repo_module:` setting;
- points Brando at the application's mailer and writes a placeholder sender
  when none is set, as `mix brando.migrate55` does (see below), so Brando's
  configuration changes only once;
- removes `processor_module: Brando.Images.Processor.Sharp` from config. Brando
  refuses to boot with it, and Vix is the default;
- moves Gettext backends to `use Gettext.Backend` and their importers to
  `use Gettext, backend: ...`, leaving the `gettext` requirement alone;
- creates the `scripts/sync_gettext.sh` helper in the application, replacing a
  copy of the 0.54 helper. A copy the application edited is left alone with a
  warning;
- moves a Villain editor (`input :data, :blocks`, inside a tab or fieldset) to
  a form-level `blocks :blocks`, and removes the tab or fieldset it leaves
  empty;
- rewrites reads of a Villain HTML field (`entry.html`, `@entry.html`,
  `hero_html`) in a moved schema's own templates to `rendered_blocks`
  (`rendered_hero_blocks`), and lists, with file and line, the `.html` reads
  it left;
- rewrites a fragment's `html` read out of a fragments map to
  `rendered_blocks` (`@partials["footer"].html`, where
  `plug Brando.Plug.Fragment, as: :partials` or a `get_fragments` call fills
  the map), and lists the other `…].html` map reads with file and line. A
  fragment has no `html` since 0.54, and such a read fails the page with a
  `KeyError`;
- adds `relation:` to a `:multi_select` on a has_many relation that has only
  `relation_key:`, naming the join schema's belongs_to on that key
  (`relation_key: :category_id` gets `relation: :category`). The admin form
  crashes without it, and a Blueprint without it does not compile in 0.55. An
  input whose belongs_to it cannot find is listed;
- drops the options of an `:entries` input's `for:` (in 0.55, `sources:`) that
  the identifiers it lists do not have, such as `preload:` and an order by
  `sequence`, and says what it dropped. The options apply to the identifiers,
  not the source schema (see [Related entries](blueprint_forms.md#related-entries));
  a Blueprint with such options does not compile in 0.55. Options it cannot
  read are listed;
- rewrites 0.53 navigation item reads inside `for item <- @navigation.items`
  (and `:for`) to `Brando.HTML.get_menu_item_url/1`, `get_menu_item_text/1`,
  `get_menu_item_target_blank/1` and `item.children`, and, when templates read
  the page's vars (`@page`, `assigns[:page]`), adds `:vars` to the `preload` of
  the `Pages.get_page/1` calls written with a map, or with a variable the same
  function assigns one (`page_opts = %{…}`). Reads it cannot rewrite, and page
  loads it cannot update, are listed with file and line. When vars are read
  on something other than the page, the `Pages.get_page/1` calls are listed
  beside the reads, for you to give `preload: [:vars]` where their page
  reaches them;
- converts each admin Create/Update LiveView pair the generator made and the
  application did not edit into one `<Name>FormLive`, written beside the
  `UpdateLive` it replaces, deletes the pair and points both routes at the new
  module. A pair that differs from the generator's only in the text of its
  `<:header>` slot counts as unedited, since the 0.55 form shows no header.
  Edited pairs are listed. When two FormLives would share a route
  helper (two `Category` schemas, say) and one is routed in a plain
  `scope "/menu", MyAppAdmin.Menu do` holding only that domain's admin
  LiveViews, the task adds `as: :menu` to the scope and `router_scope: :menu`
  to every Blueprint routed in it. Routes listed flat in `admin_routes`, as the
  0.53 generator wrote them, are wrapped in a new
  `scope "/menu/categories", MyAppAdmin.Menu, as: :menu do` when the domain's
  lines are adjacent. Other shapes are listed with the same fix;
- rewrites a listing's 0.53 `field` and `template` columns into a row
  component when it can convert every column: `component
  &__MODULE__.listing_row/1` in the listing and a `listing_row/1` at the end of
  the module. An `:image` field becomes `<.cover>`, a `:url` field `<.url>`,
  and a Liquid template whose only link goes to the entry's admin update form
  becomes `<.update_link>`, with the markup before the link in its `:before`
  slot and the markup after it in its `:outside` slot (`{{ entry.a.b }}`
  becomes `{@entry.a && @entry.a.b}`, also inside attributes,
  `{% if entry.x %}` an `:if`, and `{% for c in entry.categories %}` a
  `:for={c <- @entry.categories || []}`). Language columns and inline `<svg>`
  icons in badges are dropped. Any other listing is left as it is and listed
  with file and line;
- removes listing actions whose event is `edit_entry`, `duplicate_entry` or
  `delete_entry` from listings that keep `default_actions`, which already
  offers them, and names each one; an action with options beyond `label`,
  `event` and `confirm` is listed instead;
- writes Blueprint labels given as `gettext("…")` as `t("…")` where the admin
  translates them in the schema's domain (tab names, alerts, `label:`,
  `placeholder:` and `instructions:`, listing filter, action, sort and export
  labels, action confirmations, `translate` values), and lists the Gettext
  calls there it cannot rewrite. `gettext/1` extracts into `default`, so such
  a label stayed in English;
- deletes a Phoenix.View-era `ErrorHelpers` module, `view/0` and
  `view_helpers/0` when nothing uses them. Otherwise it replaces their
  `use Phoenix.HTML` with `import Phoenix.HTML`, `import Phoenix.HTML.Form` and
  `use PhoenixHTMLHelpers` and asks you to add `{:phoenix_html_helpers,
  "~> 1.0"}`. It lists any other `use Phoenix.HTML`;
- adds `listeners: [Phoenix.CodeReloader]` to `project/0` (Phoenix 1.8's code
  reloader warns at boot without it), turns `use Mix.Config` into
  `import Config`, and Logger's `:warn` level into `:warning`.

### mix brando.migrate55

`mix brando.migrate55` covers the 0.54 to 0.55 source changes. It:

- points references to the modules renamed in 0.55 at their new names in
  routers, sockets, config and code: a route's `Brando.SEOController, :robots`
  becomes `BrandoWeb.SEOController, :robots`, and so on (the table is in
  `UPGRADE.md`). An alias in braces the new name cannot share is reported
  instead; the old names keep working, with a warning, until 0.57;
- adds the narrow listing component imports used by custom row functions;
- defaults an unconfigured Swoosh API client to `Swoosh.ApiClient.Req` and
  pins declared `phoenix_live_view` dependencies in `assets/**/package.json`
  to the loaded server version;
- points Brando at the application's `Mailer` (`config :brando, mailer:
  MyApp.Mailer`), or, when it has none, creates `MyApp.Mailer` with the local
  adapter in development and the test adapter in test, and writes a
  placeholder sender (`noreply@example.com`) when none is set. After
  `mix brando.migrate54` these are already in place. `mix brando.doctor` warns
  until the placeholder and the production adapter are replaced
  ([Email](email.md));
- gives calls to the application's `list_*` queries that order a Sequenced
  schema only by `sequence` a tiebreak (`"asc sequence, desc inserted_at"`, or
  `"asc sequence, asc id"` without timestamps), and lists the calls with no
  `order:` with file and line;
- lists front-end scripts under `assets/` that read `data-src` from a
  `<video>`;
- warns when `config/runtime.exs` reads the Repo `url:` from the environment
  in `:test` too, and when `test_paths` names a missing directory (see
  [Test and development databases](#test-and-development-databases));
- removes `:brando` and the Hex and git dependencies from the endpoint's
  `reloadable_apps` (usually in `config/dev.exs`), and lists each list it
  changed with file and line. With `:brando` listed, the code reloader checks
  Brando's sources on every development request, and on Elixir 1.19 and later
  each check rebuilds the application's protocols. The application and path
  dependencies you edit alongside it stay; a list left with only the
  application goes, since Phoenix's default reloads the application itself;
- removes a bare `use Phoenix.Component` from a module whose
  `use BrandoWeb, :html` (or a kind of the application's web module that uses
  Phoenix.Component) already does it. Elixir 1.20 warns about the second one,
  which fails `--warnings-as-errors`;
- writes `Brando.Content.get_entries_from_identifiers(ids, [:cover])`, whose
  list of preloads is deprecated, as
  `get_entries_from_identifiers(ids, %{preload: [:cover]})`, and lists a call
  whose preloads it cannot read;
- adds `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to the
  endpoint, before the router (and before `Brando.Plug.Health`), unless it
  already has them. See
  [Markdown alternates](markdown_alternates.md) and
  [IndexNow](identity_and_seo.md#indexnow);
- gives Villain parsers (`use Brando.Villain.Parser`) back what the parser's
  `__using__` does not bring in, where they use it: `use Phoenix.Component`
  for `~H`, `import Brando.HTML` for components such as `<.picture>`,
  `import Phoenix.HTML`, and the `Brando.Cache`, `Content`, `Datasource`,
  `Utils`, `Villain` and `Liquex.Context` aliases. It also warns about
  overrides of blocks Brando does not render, such as `slideshow/2`
  (slideshows became `gallery` in `brando_77`);
- removes the Sharp `processor_module` setting, as `mix brando.migrate54` does;
- writes `identifier false` on an embedded Blueprint (`data_layer :embedded`)
  that declares an identifier, which 0.55 refuses to compile;
- writes `default_srcset:` in an image asset's `cfg` as `srcset: %{default:
  […]}`, or removes it beside a `srcset:`. Brando ignored `default_srcset`
  there, so the asset used its `srcset` or the default config's; 0.55 rejects
  the field;
- writes `from:` or `for:` on a slug input as `source:`, or removes it beside
  a `source:`. The slug input reads only `source:`: under the others the slug
  never filled in, and 0.55 refuses to compile them. The 0.55 development
  `mix brando.gen.blueprint` wrote `from:`; the task reads the application's
  own copy of its template as text and lists the lines that look like a slug
  input naming `from:` or `for:`;
- lists, with file and line, each read of an `:entries` relation
  (`project.related_entries`) that does not go through `.identifier`;
- copies each Blueprint's translations from its 0.53 `*_naming`, `*_forms`
  and `*_listings` catalogs, and the `default` domain's translations of its
  `t/1` labels, into its schema's domain, in every locale of the Gettext
  backend the Blueprint translates through (its `gettext_module`, by default
  `MyAppAdmin.Gettext`). Copies of those catalogs in another backend, such as
  the frontend's, are read by nothing and are left alone (see
  [Reconcile Gettext catalogs](#5-reconcile-gettext-catalogs));
- sets `persist_identifier false` on Blueprints with no admin editor (no
  `:update` form route and no admin LiveView), no `absolute_url`, and nothing
  that could select their entries (no `:selection` or `:single` datasource,
  no `:entries` input whose `sources:` name them, no `:entries` relation
  without an input that lists its `sources:`), and lists the Blueprints it
  could not decide. A join schema such as `ArticleCategory`, which only
  `belongs_to` its two sides, is set too;
- completes `Plural-Forms` headers in `priv/gettext/**/*.po`. Gettext 1.0 warns
  on `nplurals=2;` without a rule and on a rule without its trailing `;`, once
  per catalog per compile, so `--warnings-as-errors` fails until they read
  `nplurals=2; plural=(n != 1);`. Older Poedit releases wrote the line without
  its `\n`, so Gettext reads it joined to the next header
  (`plural=(n != 1);X-Generator: Poedit 3.0.1`) and warns although the rule is
  complete. The task gives such a rule a line of its own, keeps the header that
  followed it, and drops text that is no header of its own (a stray
  `"3.0.1;\n"`) or a header a later line sets again, listing each file;
- refreshes `scripts/sync_gettext.sh` and archives the consumer-owned
  `mix brando.upgrade` task that 0.54 installed, wherever it lives under `lib/`,
  so Brando's own `mix brando.upgrade FROM TO` hook can take over the task name
  (`mix brando.gen.migrations` copies migration files);
- replaces a `MyAppAdmin.DashboardLive` that is exactly the old installer's
  with the current template, and lists one that renders `Content.header` but
  differs;
- creates `florist.config.exs` when both legacy `deployment.cfg` and
  `fabfile.py` exist and no Florist configuration is already present, and adds
  `plug Brando.Plug.Health` to the endpoint, before the router. Florist's
  deploy and nginx templates check `/health`. See
  [Migrating from Fabric](deployment.md#migrating-from-fabric).

It does not connect to the database, generate application Blueprint migrations,
choose identifier persistence beyond the Blueprints above, migrate data, or
resolve production constraints.

### mix brando.gen.backend --upgrade

`mix brando.gen.backend --upgrade` takes the template's package versions,
`engines` and `packageManager` (keeping the application's own packages, scripts
and BrandoJS source), replaces `vite.config.js`, removes `svelte.config.cjs`
and yarn/npm lockfiles, and replaces the Dockerfile's `assets_backend` stage
with the template's pnpm stage. That stage copies `assets/backend/.yalc` only
when it exists, which Dockerfile frontends up to 1.1 can reject, so an older or
missing `# syntax=` line at the top of the Dockerfile moves to the template's
`# syntax=docker/dockerfile:1`; a custom frontend is kept with a notice. An
older `twined/fehn` tag in the `deps` stage's `FROM` is named in a notice and
kept (see [Dependencies and toolchain](#dependencies-and-toolchain)). It moves
the admin's CSS build to native EuropaCSS (see
[Native EuropaCSS](#native-europacss)). Customized CSS and other existing files
are kept. It also moves the `assets_frontend` stage up to the same Node major
when `assets/frontend/package.json` sets no `engines.node`, or one that allows
it; otherwise a notice says why it was kept.
