# Tenancy and named environments

Brando can run in three tenancy modes. The default preserves the traditional
single-site, `public`-schema setup; the other modes introduce named content
environments backed by PostgreSQL schemas.

> #### Implementation status {: .warning}
>
> The tenant registry, schema lifecycle, routing context, archive/copy/rollback
> operations, scheduling and management UI, admin environment switcher, and
> cross-environment local-media cleanup are available. Multi-site roles,
> strict host and admin authorization, compensated site provisioning,
> retention-aware site deletion, per-site media, tenant-scoped caches,
> uploadable frontend asset sets, and the existing-installation migration task
> are also available.
> Before enabling tenancy for an application, you must provide tenant migrations
> for every table the application queries as tenant content.

## Choose a mode

| Mode | Storage and behavior | Intended use |
| --- | --- | --- |
| `:none` | Existing content remains in `public`; no tenant prefix is injected | Traditional Brando installation; default |
| `:single` | One configured site can have any number of schema-backed environments | Standalone site with production, staging, and project environments |
| `:multi` | Multiple isolated sites with per-site roles, media, assets, domains, and environments | Agencies and Brando Master installations |

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

For `:static`, the flag records that the site belongs to the SSG delivery
workflow. The current tenancy phases provide the field and a tenant-aware
manual `mix brando.ssg --site SITE_KEY` command. They do **not** yet enqueue,
version, deploy, or route traffic to static builds automatically. Those build
records, workers, deploy targets, previews, and rollbacks belong to the
versioned SSG phase. Until that phase or an application-owned deploy pipeline
is configured, selecting `:static` does not stop Phoenix from serving the
site's domains and does not itself publish a build.

An asset set and a delivery mode answer different questions:

- the asset set selects which compiled CSS, JavaScript, fonts, and other
  frontend files Brando serves or copies into an SSG build;
- the delivery mode states whether Phoenix responses or a deployed static
  snapshot are intended to be the public site.

Choose `:dynamic` unless the site already has an SSG build-and-deploy pipeline.
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
content migrations. Complete the next two sections before serving requests in
an enabled tenancy mode.

## Tenant migrations

Public and tenant migrations have separate responsibilities:

```text
priv/repo/migrations/          # public registry and shared records
priv/repo/tenant_migrations/   # content repeated in every environment schema
```

Create application-owned tenant migrations with:

```bash
mix brando.gen.tenant_migration create_content_tables
```

For an umbrella or custom repository layout:

```bash
mix brando.gen.tenant_migration create_content_tables \
  --migrations-path apps/my_app/priv/repo/tenant_migrations
```

Tenant migrations should create every table accessed after tenant context is
set. Do not duplicate shared registry and authentication tables such as
`sites`, `environments`, `users`, `users_tokens`, or
`environment_operation_logs`; their schemas are permanently pinned to
`public`.

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

Once tenant migrations exist, provision a complete site from the superuser
screen at `/admin/sites`, or call the same compensated API from setup tooling:

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
or manifests. `mix brando.ssg --site acme` copies Acme's active uploaded set and
media root when present; without an active set it retains the existing local
Vite build flow.

The storage roots can be made explicit; otherwise they are derived alongside
the configured media directory:

```elixir
config :brando,
  media_path: "/srv/my_app/media",
  sites_path: "/srv/my_app/sites",
  site_assets_path: "/srv/my_app/site_assets"
```

Back up `sites/` and `site_assets/` alongside `media/`. Florist remains
responsible for clean builds, upload transport, retention pruning, and
blue/green shared-directory symlinks; Brando owns registration, activation,
serving, manifest selection, and the management UI.

## Migrate an existing installation

After writing and applying tenant migrations, copy an existing public-schema
site with:

```bash
mix brando.migrate_to_tenant --site-key=my-site
```

Use `--name` to override the generated display name and `--creator-email` when
the first active superuser should not own the new site. The task:

1. provisions a migrated, empty Production schema without default seeding;
2. discovers tables present in both `public` and the migrated tenant schema;
3. excludes users, sessions, sites, environments, assignments, Oban jobs,
   operation logs, asset metadata, transient previews/uploads, and migration
   history;
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

## Operational checklist

Before enabling `:single` or `:multi`:

1. Keep a restorable external database backup.
2. Apply public migrations.
3. Provide tenant migrations for every tenant content table.
4. Provision the site or run `mix brando.migrate_to_tenant` for existing data.
5. Add `Brando.Plug.Tenant` before content-loading plugs in existing routers.
6. Verify `pg_dump` and `psql` availability from the release environment.
7. Run tenant migrations for every environment.
8. Exercise copy and recovery on representative production-sized data.
9. Verify each domain resolves to the intended environment and unknown hosts
   return `404`.
10. Verify an editor cannot switch to or query an unassigned site.
11. Verify uploaded assets and media return different bytes for two site hosts.
12. Back up the database, `media/`, `sites/`, and `site_assets/` together.

If a tenant request reports that a relation does not exist, first verify the
resolved prefix and tenant migration history. The most common cause is a table
that still exists only in `public` because it was omitted from the application’s
tenant migrations.
