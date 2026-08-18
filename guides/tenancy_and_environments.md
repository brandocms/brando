# Tenancy and named environments

Brando can run in three tenancy modes. The default preserves the traditional
single-site, `public`-schema setup; the other modes introduce named content
environments backed by PostgreSQL schemas.

## Choose a mode

| Mode | Storage and behavior | Intended use |
| --- | --- | --- |
| `:none` | Existing content remains in `public`; no tenant prefix is injected | Traditional Brando installation; default |
| `:single` | One configured site can have any number of schema-backed environments | Standalone site with production, staging, and project environments |
| `:multi` | Multiple isolated sites with per-site roles, media, assets, domains, and environments | Agencies and Brando Master installations |

Upgrading Brando does **not** require an existing project to adopt tenancy.
Projects that keep the default `:none` mode continue to read and write content
in `public` as before. They should apply the ordinary Brando-owned public
database migrations during an upgrade, but they do not need tenant migrations,
`Brando.Plug.Tenant`, site or environment records, or
`mix brando.migrate_to_tenant`. The new public registry tables may exist unused
in this mode.

The tenant setup and data-conversion sections in this guide apply only when a
project deliberately changes to `:single` or `:multi`. Existing projects may
adopt those modes later; there is no requirement to convert every Brando
project as part of the framework upgrade.

The registry itself always lives in `public`:

```text
public
├── sites
├── environments
├── users
├── users_tokens
├── user_sites
├── site_asset_sets
└── environment_operation_logs

tenant_acme_production
├── pages
├── navigation_menus
├── content_blocks
└── ... application content

tenant_acme_staging
└── ... an isolated copy of application content
```

Environment names are ordinary data. `production` and `staging` are useful
defaults, not reserved keys. A site can have any number of environments, while
a partial database index guarantees that no more than one is marked live.

## Choose a delivery mode

`delivery_mode` describes how a site's public frontend is published. It is
independent of `tenancy_mode`: a site in a multi-tenant installation can be
dynamic or static, and uploadable frontend asset sets can be used by either.
Classic projects in `tenancy_mode: :none` have no site registry record and do
not need to set `delivery_mode`; Phoenix continues to serve them dynamically as
it did before tenancy support was introduced.

| Mode | Public delivery | Content publication |
| --- | --- | --- |
| `:dynamic` | Phoenix serves each request from the site's current live environment | A live-environment change is visible on the next request; no static build or deploy is required |
| `:static` | A generated HTML build is intended to be served by a static host or CDN | Content becomes public only after an SSG build is generated and deployed |

For `:dynamic`, the request host resolves the site and live environment,
`Brando.Plug.Tenant` installs that environment's database prefix, and the
normal Phoenix router renders the response. `Brando.Plug.SiteAssets` may serve
an activated uploaded CSS/JS set first, but a miss still falls through to the
assets packaged in `priv/static`. Activating an asset set therefore changes
frontend files without changing the site's content environment or requiring a
full application release.

For `:static`, Brando exposes **Publishing** under the selected site's admin
configuration. Site administrators can build the live environment or any
working environment, schedule a build, inspect progress and failed URLs,
preview a completed artifact, deploy it, or roll back by redeploying an older
artifact. Builds receive monotonic versions (`v1`, `v2`, …) per site and run on
the serial `ssg_builds` Oban queue.

Setting the flag still does not move public traffic by itself. The public host
continues to reach Phoenix until its web server or CDN is pointed at the
configured static target. This separation makes a first static build safe to
preview before the infrastructure cutover and keeps changing delivery mode
independent from changing content environments.

An asset set and a delivery mode answer different questions:

- the asset set selects which compiled CSS, JavaScript, fonts, and other
  frontend files Brando serves or copies into an SSG build;
- the delivery mode states whether Phoenix responses or a deployed static
  snapshot are intended to be the public site.

Choose `:dynamic` when editors should publish directly through Phoenix. Choose
`:static` when publication should create a reviewable, immutable artifact and
the public site can be served by rsync- or S3-backed static infrastructure.
Changing the field later does not move traffic or activate an asset set; treat
that change and the corresponding infrastructure cutover as separate
operations.

## New installations

`mix brando.install` starts a guided setup when no tenancy flags are supplied:

```text
+ Choose tenancy mode [1]
  1. none   — classic single-site Brando
  2. single — one site with named environments
  3. multi  — multiple sites with named environments
```

Pressing Enter selects `none`. Selecting `single` also asks for a URL-safe site
key, defaulting to the OTP application name with underscores changed to
hyphens.

For repeatable or CI-driven installation, pass the choices explicitly:

```bash
# Traditional installation
mix brando.install --tenancy-mode none

# Standalone site with environments
mix brando.install --tenancy-mode single --site-key acme

# Multi-site registry
mix brando.install --tenancy-mode multi

# Preserve the default without prompting
mix brando.install --no-tenancy-prompt
```

Passing any tenancy flag makes the command non-interactive. `--site-key` is
required only for `single`, and keys must contain lowercase letters, numbers,
and single hyphens.

The installer writes the selection to `config/brando.exs`:

```elixir
config :brando,
  tenancy_mode: :single,
  site_key: "acme"
```

Configuration is validated when Brando starts. An invalid mode or a missing or
invalid single-site key stops startup with a configuration error.

The installer does **not** create registry records or generate application
content migrations. Complete the tenant migration and provisioning steps below
before serving requests in an enabled tenancy mode.

## Optionally enable tenancy for an existing installation

Existing applications can apply the deterministic source changes with the
opt-in Igniter task. Igniter is an optional Brando dependency, so add it to the
application's own deps first:

```elixir
# mix.exs
{:igniter, "~> 0.8", only: [:dev, :test]},
```

```bash
mix deps.get
mix deps.compile brando --force
```

The forced recompile matters: Brando only defines its Igniter-backed tasks if
`igniter` is loadable when Brando itself compiles, so a stale Brando build keeps
reporting `The task "brando.setup.tenancy" could not be found`. Then run:

```bash
# Asks for anything you do not pass
mix brando.setup.tenancy

# One site with named environments
mix brando.setup.tenancy --mode single --site-key my-site

# Multiple isolated sites
mix brando.setup.tenancy --mode multi
```

Pass `--yes` for a non-interactive run, where a missing option is an error
rather than a prompt. Igniter also sets that automatically when there is no
TTY, so piped and CI runs never block on a question.

The task prints an ordered next-steps notice when it finishes, naming the exact
commands for each remaining step.

The task updates `config/brando.exs`, adds `Brando.Plug.Tenant` to recognized
`:browser` and `:browser_api` pipelines before Brando content-loading plugs,
and installs Brando's tenant migration support under
`priv/repo/tenant_migrations`. It is idempotent and warns when it cannot find a
standard Phoenix router or `:browser` pipeline.

Do not run this task merely to upgrade a classic single-site project. Leave
`tenancy_mode` as `:none` if named environments and site isolation are not
needed.

Review the complete Igniter diff before applying it. The task changes source
only: it never runs database migrations, provisions sites, or copies production
data. Apply the public migrations and read the next section before running the
separate data conversion task.

## Tenant migrations

Public and tenant migrations have separate responsibilities:

```text
priv/repo/migrations/          # public registry and shared records
priv/repo/tenant_migrations/   # content repeated in every environment schema
```

### Structure comes from `public`, not from tenant migrations

Ordinary migrations create the application's content tables in `public` in every
tenancy mode, so `public` is the canonical structural template. Provisioning
clones it: creating an environment runs `CREATE SCHEMA`, copies the structure of
every tenant table out of `public` without its data, and only then runs tenant
migrations.

Applications therefore do **not** restate their content schema as tenant
migrations. Neither does Brando. Adding `create table` migrations to
`priv/repo/tenant_migrations` would fork one schema definition into two places
that must then be kept in step by hand.

> #### Table names may not contain a double quote {: .warning}
>
> Mixed-case, hyphenated, dotted, non-ASCII, and wildcard-looking table names are
> all cloned and migrated correctly. A name containing `"` is refused, because it
> cannot be expressed unambiguously in a `pg_dump` object pattern. Provisioning
> then fails with `{:structure_clone_failed, {:unsafe_source_table_name, names}}`
> and conversion with `{:unsafe_public_table_name, names}`, listing the offenders.
>
> The operation aborts rather than skipping the table, because silently omitting
> one would leave an environment missing part of its schema. To find any:
>
> ```sql
> SELECT tablename FROM pg_tables
> WHERE schemaname = 'public' AND tablename LIKE '%"%';
> ```
>
> Rename anything that turns up, or add it to `:shared_tables` if it is genuinely
> a cross-site table that should stay in `public`.

Tenant migrations exist to *evolve* environments that already exist. Write them
for column additions, index changes, and backfills, and generate them with:

```bash
mix brando.gen.tenant_migration add_summary_to_pages
```

For an umbrella or custom repository layout:

```bash
mix brando.gen.tenant_migration add_summary_to_pages \
  --migrations-path apps/my_app/priv/repo/tenant_migrations
```

Make them idempotent. They run against freshly cloned structure as well as
against long-lived environments, so guard them the way Brando's own tenant
migration does, with `ADD COLUMN IF NOT EXISTS` and `to_regclass` checks. Note
also that `execute/1` does not receive the migration prefix the way
`create table/2` does — read `prefix()` and interpolate it yourself.

### Which tables are shared

`Brando.Tenant.SharedTables` is the single source of truth. Registry,
authentication, session, and migration-history tables stay in `public`
permanently, along with every `oban_*` table, since Oban is configured against
`public`:

```text
environments  environment_operation_logs  schema_migrations
site_asset_sets  ssg_builds  sites  sites_previews
uploads_pending_intents  user_sites  user_tokens  users  users_tokens
oban_*
```

Everything else in `public` is treated as tenant content, so an application with
its own cross-site tables must say so, or they will be cloned into every
environment and their rows copied with the content:

```elixir
config :brando, :shared_tables, ["billing_accounts", "feature_flags"]
```

Foreign keys from tenant tables
to shared tables keep their `public` qualifier through cloning, so a
`creator_id` in a tenant schema still resolves to `public.users`. When a
hand-written tenant migration adds such a reference, spell that out:

```elixir
add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)
```

A bare `references(:users)` inside a prefixed migration resolves to
`tenant_{site}_{environment}.users`, which does not exist.

Run public migrations first because tenant discovery reads the public registry:

```bash
# Public migrations
mix brando.migrate

# Every environment of every site
mix brando.migrate --tenants

# Every environment belonging to one site
mix brando.migrate --site acme
```

Generated release tasks expose the same ordering for releases:

```elixir
MyApp.ReleaseTasks.migrate()
MyApp.ReleaseTasks.migrate_tenants()
```

Deploy code that can work with both the old and new tenant schema version when
rolling releases across multiple nodes. Run public migrations before tenant
migrations, and tenant migrations before routing traffic to code that requires
the new columns.

## Provision sites and initial environments

Provision a complete site from the superuser screen at `/admin/sites`, or call
the same compensated API from setup tooling:

```elixir
{:ok, site} =
  Brando.Tenant.Setup.create_site(
    %{
      name: "Acme",
      key: "acme",
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    },
    current_user
  )
```

Provisioning creates live Production and non-live Staging environments, runs
tenant migrations, seeds Production, copies it to Staging, creates
`media/{site_key}` and `sites/{site_key}/assets`, and grants the creator the
site admin role. A PostgreSQL advisory lock serializes creation for the key. If
any database, seed, copy, assignment, or filesystem step fails, Brando removes
the partial schemas, registry rows, and directories.

The default seeder creates identity and SEO records for every site language.
Applications normally provide a home page and application-specific initial
content by configuring a module that implements `Brando.Tenant.Seeder`:

```elixir
config :brando, tenant_seeder: MyApp.TenantSeeder
```

Individual working environments can still be created with
`Brando.Environments.create_environment/2`. It creates
`tenant_{site}_{environment}`, runs all tenant migrations, writes an operation
log, and compensates a failed schema creation or migration.

In `single` mode, the site key in the registry must match the configured
`site_key`.

## Router and request context

Newly generated routers place `Brando.Plug.Tenant` in the browser pipelines
before plugs that load content:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  # ...
  plug Brando.Plug.Tenant
  plug Brando.Plug.Identity
  plug Brando.Plug.Navigation, key: "main", as: :navigation
end

pipeline :browser_api do
  plug :accepts, ["html"]
  plug :fetch_session
  # ...
  plug Brando.Plug.Tenant
end
```

Existing applications opting into tenancy must add the tenant plug in the same
position. It resolves domains from `Brando.Tenant.Cache`, assigns
`current_site`, `current_environment`, and `tenant_prefix`, and stores the
prefix in process context without a database query.

The Brando admin routes also restore the environment selected in the signed
session:

- ordinary controller requests use `Brando.Plug.AdminTenant`;
- LiveViews use `Brando.Tenant.LiveView` and restore context before events and
  messages;
- the sidebar switcher marks the live environment and warns while editing a
  non-live environment.

Per-site administrators and global superusers can open
`/admin/config/environments` to create and delete working environments, queue
or schedule copies and live switches, cancel pending jobs, restore the newest
archive, and prune old archives. Editors can inspect the same state without
lifecycle mutation controls. In multi-site mode the sidebar contains only sites
assigned to the current user; global superusers see every active site.

`Brando.Repo` applies the current prefix to reads, writes, preloads, bulk
updates, and bulk soft deletion. An explicit prefix always wins:

```elixir
# Current environment
Brando.Repo.all(MyApp.Pages.Page)

# Deliberately query shared data
Brando.Repo.all(Brando.Sites.Site, prefix: "public")
```

Shared schemas should set `@schema_prefix "public"`. The wrapper recognizes
that metadata and keeps shared models in `public` even when an admin is working
inside a tenant environment.

In `:multi`, a suspended, archived, or unknown frontend host receives `404`
before content plugs run. A stale or forged admin site selection is checked
against `public.user_sites`; it can never restore another tenant's schema
prefix.

## Shared modules, containers, and palettes

In `:multi` mode, global superusers can manage reusable block building blocks
at `/admin/config/content/shared_library`. Shared modules, containers, and
palettes live in `public`; custom entries and customizations live in the
selected environment schema.

Access is opt-in and site-wide. Enabling an entry makes it available in every
environment's picker for that site. It does not copy the entry into those
schemas. A site can therefore use only custom entries, only an approved subset
of the shared library, or a mixture of both. The dashboard supports saving an
exact allowlist as well as enabling or disabling all entries of one kind.

Blocks store both an integer ID and an explicit `local` or `shared` origin for
their module, container, and palette references. The origin is significant:
`local:42` and `shared:42` are different references even when PostgreSQL has
assigned the same integer in both schemas. Existing local blocks are migrated
with `local`, preserving pre-tenancy behavior.

Resolution has two paths:

- pickers return all non-deleted local entries plus the enabled shared entries;
- rendering resolves the block's stored origin and may load a shared entry even
  after picker access was revoked.

The second rule is deliberate. Disabling a shared entry prevents adding new
references but never breaks published or draft blocks that already use it.
Deleting a shared entry is blocked while it is enabled, customized, or
referenced in any environment. The dashboard shows those sites and
environments before an edit or deletion.

Choosing **Customize** copies the shared entry into the selected environment
and records its source ID and source version. Blocks keep their shared identity,
so they immediately resolve to that environment's customization without a
content rewrite. Other environments and sites are unaffected. **Reset to
shared** removes only the customization.

Publishing a shared edit increments its version and records a changelog note.
Sites without a customization use the new version immediately, and Brando
queues affected entries for rendering in each environment. A customization
continues using its local version and receives an **Update available** badge.
The administrator can inspect a field-level diff, replace the customization
with the current shared version, or dismiss that version's notification.

The allowlist is cached per site. Mutations update the cache immediately; no
application restart is required. When upgrading an existing application, run
both public and tenant migrations so the public access tables, source/version
columns, and origin-qualified block fields are present:

```bash
mix brando.upgrade
mix brando.migrate
mix brando.migrate --tenants
```

## Per-site roles and lifecycle

Users remain global accounts in `public.users`. Multi-site access is explicit:

```text
superuser  global role; bypasses assignments for every active site
admin      per-site role; content plus site/environment lifecycle management
editor     per-site role; content editing without lifecycle mutation
```

The superuser Sites screen at `/admin/sites` provisions sites, shows
environment/page/media/last-edit summaries, changes lifecycle state, and grants
or revokes roles. The underlying API is also available to application tooling:

```elixir
{:ok, assignment} = Brando.Tenant.Access.grant(user, site, :editor)
:ok = Brando.Tenant.Access.revoke(user, site)

{:ok, suspended} = Brando.Tenant.Setup.suspend_site(site)
{:ok, active} = Brando.Tenant.Setup.activate_site(suspended)
{:ok, archived} = Brando.Tenant.Setup.archive_site(active)
```

Permanent deletion is deliberately a second step. A site must be archived for
30 days by default, after which deletion removes every current/archive schema,
registry row, assignment, media directory, and uploaded asset directory:

```elixir
{:ok, _deleted} = Brando.Tenant.Setup.delete_site(archived)
```

Configure `site_delete_retention_days` to change the window. `force: true` is
available to controlled recovery/migration code, but the admin UI never uses
it.

## Copy content safely

Copy replaces all database content in the target environment. The operation
first archives the target, then clones the source into the target prefix:

```elixir
site = Brando.Tenant.Registry.get_site_by_key("acme")
source = Brando.Tenant.Registry.get_environment_by_key(site, "production")
target = Brando.Tenant.Registry.get_environment_by_key(site, "staging")

{:ok, result} =
  Brando.Environments.copy_environment(source, target,
    creator: current_user,
    note: "Refresh staging before redesign work"
  )

result.archive_schema
#=> "tenant_acme_staging_archive_20260816143000"
```

Copying requires `pg_dump` and `psql` compatible with the target PostgreSQL
server. Brando finds them on `PATH`; explicit locations can be configured when
needed:

```elixir
config :brando,
  pg_dump_path: "/usr/local/bin/pg_dump",
  psql_path: "/usr/local/bin/psql"
```

Passwords are passed through `PGPASSWORD`, not command arguments. Schema dumps
are written to a temporary file with restricted permissions and removed after
restore.

Environment operations acquire an advisory lock per site. A copy on `acme`
therefore cannot overlap another copy, promotion, rollback, or deletion on the
same site. If source-to-target restore fails, Brando drops the partial target
and restores its archive.

Media bytes are not copied. In `:single`, every environment shares the existing
configured media root. In `:multi`, local uploads, processing, crops, exports,
sitemaps, downloads, frontend media serving, and orphan cleanup all resolve
inside `media/{site_key}`. The database continues storing relative paths such
as `images/hero.jpg`, so the same URL can safely resolve to different bytes on
different site domains.

> #### Deleting an asset must not delete its bytes {: .warning}
>
> Because media is shared, copying an environment duplicates image, file, and
> video rows while leaving one copy of each file on disk. Two environments
> routinely hold different rows pointing at the same `path`.
>
> Brando therefore soft-deletes asset rows and never removes media bytes:
> `Brando.Images.delete_images/1` marks `deleted_at`, and
> `Brando.Images.Utils.delete_original_and_sized_images/1` has no callers. The
> upload reapers only clear abandoned direct-upload objects that never became
> assets.
>
> The consequence is that deleted assets leave their files behind, and media
> grows monotonically. Prune it with a job that first confirms no row in **any**
> of the site's environment schemas still references the path — deleting on the
> strength of one environment's rows alone would break the others.

Local orphan cleanup unions image and file records from **every** environment
schema before deleting a byte:

```elixir
# Inspect what would be removed
{:ok, report} =
  Brando.Media.OrphanCleanup.run(site, dry_run: true)

# Delete local files older than the default 24-hour grace period
{:ok, report} = Brando.Media.OrphanCleanup.run(site)
```

Only regular files below `images`, `videos`, and `files` are candidates.
Symlinks and SVGs are skipped. Most importantly, if even one environment schema
cannot be inspected, the entire run fails before deleting anything. The default
Oban cron invokes `Brando.Worker.MediaOrphanCleanup` at 05:00 UTC; applications
that replace Brando's Oban configuration must re-declare that job if desired.

## Switch live, rollback, and delete

Any environment can become the live environment:

```elixir
{:ok, live_environment} =
  Brando.Environments.set_live(staging,
    creator: current_user,
    note: "Approved release"
  )
```

Before changing the live pointer, Brando archives the previous live schema.
The registry update is transactional, the one-live-environment database
constraint remains authoritative, and the routing cache is refreshed after a
successful switch.

Inspect and prune archives:

```elixir
Brando.Environments.list_archives(site)

# Keep the three newest archives (the default after copy and set_live)
Brando.Environments.prune_archives(site, 3)
```

Rollback never overwrites a current environment. It restores the newest archive
as a new, non-live environment, runs current tenant migrations on it, and leaves
promotion as a separate decision:

```elixir
{:ok, restored} =
  Brando.Environments.rollback(site,
    creator: current_user,
    note: "Recover pre-release content"
  )

{:ok, _live} = Brando.Environments.set_live(restored, creator: current_user)
```

Only non-live environments can be deleted:

```elixir
{:ok, _deleted} = Brando.Environments.delete_environment(staging)
```

Archives are schemas in the same database. They protect destructive environment
operations, but they are not a substitute for an external database backup.

## Schedule operations

Copy and live-switch operations can be scheduled through Oban:

```elixir
scheduled_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

{:ok, copy_job} =
  Brando.Environments.schedule_copy(production, staging, scheduled_at,
    creator: current_user,
    note: "Refresh staging at 02:00"
  )

{:ok, live_job} =
  Brando.Environments.schedule_set_live(staging, scheduled_at,
    creator: current_user,
    note: "Scheduled release"
  )
```

The dedicated `environment_operations` queue runs one expensive schema
operation at a time. Per-site advisory locks remain the final concurrency
guard.

List or cancel pending operations for a site:

```elixir
jobs = Brando.Environments.list_scheduled_operations(site)
:ok = Brando.Environments.cancel_scheduled_operation(site, copy_job.id)
```

The environment management panel shows these jobs with their scheduled time and
state, and exposes the same site-ownership-checked cancellation path.

## Uploadable frontend asset sets

Uploaded frontend builds persist outside releases. Standalone installations use
`site_assets/sets/{set}`; multi-site installations use
`sites/{site_key}/assets/sets/{set}`. `Brando.Plug.SiteAssets` must run before
the release `Plug.Static`; new installers and the E2E application already have
this order.

Florist uploads a clean `priv/static` build and registers it by RPC without
activating it:

```elixir
# tenancy_mode :none or :single
Brando.Assets.SiteAssets.register_set(
  "/srv/my_app/site_assets/sets/20260816_abc123",
  %{revision: "abc123", uploaded_at: DateTime.utc_now()}
)

# tenancy_mode :multi
Brando.Assets.SiteAssets.register_set(
  "acme",
  "/srv/my_app/sites/acme/assets/sets/20260816_abc123",
  %{revision: "abc123"}
)
```

Registration validates that the directory is an immediate child of the
managed `sets` root, rejects symlinks and special files, and records the actual
byte size and file count. A superuser activates or rolls back sets at
`/admin/config/assets`. Activation caches both the complete regular-file
`MapSet` and optional Vite manifest in `:persistent_term`. Requests absent from
that set fall through to release assets without a filesystem lookup. Reverting
clears the active cache and immediately restores `priv/static` fallback.

Vite manifest and critical CSS resolution follow the same active-set-first,
release-fallback order. In multi-site mode caches are keyed by the full tenant
prefix, so Production, Staging, and another site cannot share rendered content
or manifests. Every queued static build snapshots the active asset-set record
and deployment configuration at creation time. A later asset activation or
target edit therefore affects new builds, never an artifact already being
reviewed or deployed.

## Build and publish static sites

Declare public paths in your application's web SSG module:

```elixir
defmodule MyAppWeb.SSG do
  import Brando.SSG

  urls :pages do
    ["/", "/about", "/contact"]
  end

  urls :projects do
    MyApp.Projects.list_projects!(%{status: :published})
    |> Enum.map(&MyApp.Projects.Project.__absolute_url__/1)
  end
end
```

URL callbacks execute under the selected environment's tenant prefix. The
renderer sends a short-lived signed context header through the normal endpoint,
so a working environment can be built without assigning it a temporary domain.
Responses outside the 200 range are retained in the build's failed-URL list and
make the build fail without hiding partial logs or counts.

Open `/admin/config/publishing` while a static site is selected. The deployment
form supports:

- `rsync`, with a target such as `deploy@example.com:/srv/www`;
- `s3`, with `s3://bucket` or `s3://bucket/prefix`;
- an optional public CDN URL and completion webhook;
- automatic deployment after successful builds; and
- artifact retention from 1 through 100 builds (10 by default).

Generated output is persistent at
`sites/{site_key}/ssg/builds/{version}`. Old ready, archived, and failed artifact
directories are pruned after the retention window, while their database history
and logs remain. Preview tokens expire after seven days and stop working as soon
as their artifact is pruned.

The command-line task uses the same renderer and remains interactive by default:

```bash
# Standalone application
mix brando.ssg

# Any environment in a multi-site application
mix brando.ssg --site acme --environment staging

# Inspect the plan without requests or filesystem writes
mix brando.ssg --site acme --environment production --dry-run

# Non-interactive build to an explicit directory
mix brando.ssg --site acme --force --output /tmp/acme-static
```

Without an uploaded asset set, the task builds the local frontend with Vite and
copies `priv/static`. Pass `--no-compile-assets` to reuse the current release
files. Background builds never compile source assets on the server: they copy
the snapshotted uploaded set or the running release's `priv/static`.

The storage roots can be made explicit; otherwise they are derived alongside
the configured media directory:

```elixir
config :brando,
  media_path: "/srv/my_app/media",
  sites_path: "/srv/my_app/sites",
  site_assets_path: "/srv/my_app/site_assets"
```

Back up `sites/` and `site_assets/` alongside `media/`. Florist remains
responsible for clean frontend builds and blue/green shared-directory symlinks;
Brando owns asset registration/activation and the versioned static artifact
lifecycle. If the application overrides `config :brando, Oban`, re-declare a
serial `ssg_builds` queue because an application-level Oban configuration
replaces, rather than merges with, Brando's defaults.

## Copy an existing installation into tenancy

This conversion is optional and applies only after deciding to move an existing
project from `:none` to `:single` or `:multi`. A project remaining in `:none`
must not run this task and can leave its existing content and media in their
classic locations.

First prepare the application's source and review the Igniter diff:

```bash
mix brando.setup.tenancy --mode single --site-key my-site
```

Then convert the existing public-schema site with:

```bash
mix brando.migrate_to_tenant --site-key=my-site
```

Use `--name` to override the generated display name and `--creator-email` when
the first active superuser should not own the new site. The task:

1. provisions a Production schema without default seeding, cloning its structure
   from `public`;
2. discovers tables present in both `public` and the provisioned tenant schema;
3. excludes everything in `Brando.Tenant.SharedTables`;
4. copies only matching table data with `pg_dump` and `psql`;
5. copies classic local media into `media/{site_key}` without deleting the
   legacy media tree;
6. creates Staging as a complete copy of Production; and
7. removes the entire partial site if data, media, or Staging creation fails.

The media copy rejects symlinks and special files so it cannot cross a tenant
storage boundary. Provisioning also refuses to reuse an existing
`media/{site_key}` or `sites/{site_key}` directory; a failed setup never removes
storage it did not create. Keep the original public data and legacy media until
the migrated site has been verified and the rollback window has closed.

### Moving instead of copying

Copying leaves the original rows in `public`, which is the rollback window the
paragraph above depends on. Large installations can relocate the tables instead:

```bash
mix brando.migrate_to_tenant --site-key=my-site --move
```

`ALTER TABLE ... SET SCHEMA` is a catalog operation, so no table data is
rewritten and the conversion takes the same time whatever the database weighs.
Indexes, constraints, and column-owned sequences travel with their table, so
foreign keys keep resolving to `public.users` and sequences arrive at their
current position rather than needing a reset.

Brando builds an empty template from `public` first, then drops the target's
cloned tables, moves the populated tables in, and moves the template tables back
into `public` — all in one transaction, so a failure leaves both schemas as they
were. `public` is left with the same tables, empty, still serving as the
structural template for the next site or environment.

`--move` also sidesteps circular foreign keys. A Brando schema has several —
`pages` and `media_folders` reference themselves, and `images` and `users`
reference each other — so `pg_dump --data-only` warns that the copy may not
restore. In practice the `images`/`users` cycle is harmless, because `users`
stays in `public` and is never copied, but a self-referential table can still
fail if a child row is copied before its parent. Moving performs no data
restore at all, so the question does not arise.

Two trades come with it. There is no rollback window, because no legacy rows are
left in `public` — take a restorable external backup first. And the tables that
arrive from `public` are never re-migrated, so `public` must already carry every
structural change; a change that exists only in tenant schemas would be lost.
That follows from `public` being the structural template, but it is worth
checking before a production cutover.

Run the conversion in a maintenance window after draining tenant-owned Oban
work such as publishing, rendering, image processing, and CDN uploads. Jobs
created before tenancy do not contain a tenant prefix and are deliberately
cancelled rather than allowed to query `public` after tenancy is enabled;
recreate any future publication schedules after migration. Standalone uploaded
asset-set records are also not assigned to the new site automatically. Upload
or register a fresh site-scoped set, verify it, and then activate it from the
asset management screen.

The source `public` data is not deleted. Keep it and a restorable external
backup until the tenant installation has been verified and cut over.

## Operation log

Lifecycle operations write immutable records to
`public.environment_operation_logs`. The log captures the site, source and
target environments, creator, operation type, archive schema, note, and
timestamp. Environment references are nilified when an environment is deleted,
so historical records remain available.

Supported operations are:

```text
create  copy  set_live  rollback  delete
```

## Operational checklist for enabled tenancy

Before enabling `:single` or `:multi`:

1. Keep a restorable external database backup.
2. Run `mix brando.setup.tenancy` for an existing application and review its
   source diff.
3. Apply public migrations, which is what gives `public` the content tables
   provisioning clones from.
4. Provide tenant migrations for any change that must reach existing
   environments. Content tables themselves need none.
5. Provision the site or run `mix brando.migrate_to_tenant` for existing data.
6. Verify `pg_dump` and `psql` availability from the release environment.
7. Run tenant migrations for every environment.
8. Exercise copy and recovery on representative production-sized data.
9. Verify each domain resolves to the intended environment and unknown hosts
   return `404`.
10. Verify an editor cannot switch to or query an unassigned site.
11. Verify uploaded assets and media return different bytes for two site hosts.
12. Back up the database, `media/`, `sites/`, and `site_assets/` together.

If a tenant request reports that a relation does not exist, first verify the
resolved prefix. Because structure is cloned from `public` at provisioning time,
the usual cause is that the table did not exist in `public` yet when the
environment was created — a public migration applied afterwards reaches `public`
only. Add a tenant migration that creates the table for existing environments,
or recreate the environment.

`Brando.Environments.StructureCloner.Postgres.tenant_tables/1` lists what a
schema is expected to hold, and comparing it against a tenant prefix shows what
is missing:

```elixir
{:ok, expected} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
{:ok, actual} = Brando.Environments.StructureCloner.Postgres.tenant_tables("tenant_acme_production")
expected -- actual
```
