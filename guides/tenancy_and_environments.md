# Tenancy and named environments

Brando can run in three tenancy modes. The default preserves the traditional
single-site, `public`-schema setup; the other modes introduce named content
environments backed by PostgreSQL schemas.

> #### Implementation status {: .warning}
>
> The tenant registry, schema lifecycle, routing context, archive/copy/rollback
> operations, scheduling and management UI, admin environment switcher, and
> cross-environment local-media cleanup are available.
> Before enabling tenancy for an application, you must provide tenant migrations
> for every table the application queries as tenant content.
>
> Existing-installation data migration, multi-site roles, per-site upload paths,
> and strict multi-site authorization are not complete. Keep existing
> installations on `:none`, and do not deploy `:multi` as a tenant-security
> boundary yet.

## Choose a mode

| Mode | Storage and behavior | Intended use |
| --- | --- | --- |
| `:none` | Existing content remains in `public`; no tenant prefix is injected | Traditional Brando installation; default |
| `:single` | One configured site can have any number of schema-backed environments | Standalone site with production, staging, and project environments |
| `:multi` | The registry can contain multiple sites, each with named environments | Brando Master; requires the unfinished multi-site authorization phase |

The registry itself always lives in `public`:

```text
public
├── sites
├── environments
├── users
├── users_tokens
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

# Multi-site registry; not yet a production authorization boundary
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

## Create the registry and initial environments

Once tenant migrations exist, create the site record and its initial
environments. The following can be placed in an application seed/setup task or
run in a controlled IEx session:

```elixir
alias Brando.Environments
alias Brando.Tenant.Registry

{:ok, site} =
  Registry.create_site(%{
    name: "Acme",
    key: "acme",
    languages: ["en"],
    default_language: "en",
    status: :active,
    delivery_mode: :dynamic
  })

{:ok, production} =
  Environments.create_environment(site, %{
    name: "Production",
    key: "production",
    domain: "www.acme.test",
    live: true
  })

{:ok, staging} =
  Environments.create_environment(site, %{
    name: "Staging",
    key: "staging",
    domain: "staging.acme.test",
    live: false
  })
```

`create_environment/2` creates `tenant_{site}_{environment}`, runs all tenant
migrations in that prefix, writes an operation-log entry, and warms the routing
cache. If schema creation or migration fails, it removes both the partial schema
and registry row.

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

Administrators and superusers can open `/admin/config/environments` to create
and delete working environments, queue or schedule copies and live switches,
cancel pending jobs, restore the newest archive, and prune old archives. Editors
can inspect the same state without lifecycle mutation controls.

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

In `:multi`, an unknown frontend host currently clears tenant context and lets
the application continue. Until strict unknown-host rejection and per-site user
authorization land, do not treat this mode as a production isolation boundary.

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
configured media root. `:multi` reserves `media/{site_key}` roots; wiring upload
paths into those roots belongs to the multi-site isolation phase.

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

Before enabling `:single` or experimenting with `:multi`:

1. Keep a restorable external database backup.
2. Apply public migrations.
3. Provide tenant migrations for every tenant content table.
4. Create matching site and environment registry records.
5. Add `Brando.Plug.Tenant` before content-loading plugs in existing routers.
6. Verify `pg_dump` and `psql` availability from the release environment.
7. Run tenant migrations for every environment.
8. Exercise copy and recovery on representative production-sized data.
9. Verify each domain resolves to the intended environment.
10. Keep `:multi` disabled in production until site roles and strict isolation
    are complete.

If a tenant request reports that a relation does not exist, first verify the
resolved prefix and tenant migration history. The most common cause is a table
that still exists only in `public` because it was omitted from the application’s
tenant migrations.
