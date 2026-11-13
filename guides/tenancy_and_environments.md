# Tenancy and named environments

<!-- llms-description: Tenancy modes, sites and named content environments, tenant migrations, routing and static publication. -->

Brando can run in three tenancy modes. The default is a single site in the
`public` schema; the other modes add named content environments backed by
PostgreSQL schemas.

## Choose a mode

| Mode | Storage and behavior | Intended use |
| --- | --- | --- |
| `:none` | Content is in `public`; no tenant prefix is injected | Single-site installation; default |
| `:single` | One configured site can have any number of schema-backed environments | Standalone site with production, staging, and project environments |
| `:multi` | Multiple isolated sites with per-site roles, media, assets, domains, and environments | Agencies and Brando Master installations |

<!-- usage-rules:start topic="tenancy" -->

Tenancy is opt-in. Projects in the default `:none` mode read and write content
in `public`. They apply the ordinary Brando-owned public database migrations,
but do not need tenant migrations, `Brando.Plug.Tenant`, site or environment
records, or `mix brando.migrate_to_tenant`. The public registry tables may
exist unused in this mode.

<!-- usage-rules:end -->

The tenant setup and data-conversion sections in this guide apply only when a
project changes to `:single` or `:multi`.

The registry itself always lives in `public`:

```text
public
├── sites
├── environments
├── users
├── users_tokens
├── user_sites
├── site_asset_sets
├── environment_operation_logs
└── … (see "Which tables are shared")

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
not need to set `delivery_mode`; Phoenix serves them dynamically.

| Mode | Public delivery | Content publication |
| --- | --- | --- |
| `:dynamic` | Phoenix serves each request from the site's current live environment | A live switch takes the site's host to the new live environment, so the change is visible on the next request, on every node (see [Several nodes](#several-nodes)); no static build or deploy is required |
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

`mix brando.install` defaults to `none` without prompting when no tenancy flags
are supplied. Pass `--interactive` to choose interactively:

```text
+ Choose tenancy mode [1]
  1. none   — classic single-site Brando
  2. single — one site with named environments
  3. multi  — multiple sites with named environments
```

Pressing Enter selects `none`. Selecting `single` also asks for a URL-safe site
key, defaulting to the OTP application name with underscores changed to
hyphens.

Guided setup respects choices supplied as flags. For example,
`mix brando.install --interactive --tenancy-mode single` asks only for the site
key. `--tenancy-prompt` is an alias for guided tenancy setup;
`--no-tenancy-prompt` suppresses those questions even with `--interactive`.

For repeatable or CI-driven installation, pass the choices explicitly:

```bash
# Traditional installation (defaults to none without prompting)
mix brando.install

# Standalone site with environments
mix brando.install --tenancy-mode single --site-key acme

# Multi-site registry
mix brando.install --tenancy-mode multi

# Existing scripts can still explicitly suppress the optional prompt
mix brando.install --no-tenancy-prompt
```

Without `--interactive`, all choices must be supplied for `single`/`multi`.
`--site-key` is required only for `single`, and keys must contain lowercase letters, numbers,
and single hyphens.

On reruns, omitted tenancy flags preserve the existing selection. An explicit
mode updates its existing base configuration; changing it does not move data.
New installations write the selection to `config/brando.exs`:

<!-- usage-rules:start topic="tenancy" -->

```elixir
config :brando,
  tenancy_mode: :single,
  site_key: "acme"
```

Configuration is validated when Brando starts. An invalid mode or a missing or
invalid single-site key stops startup with a configuration error.

<!-- usage-rules:end -->

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
mix deps.compile
```

Then run:

```bash
# Asks for anything you do not pass
mix brando.setup.tenancy --interactive

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

<!-- usage-rules:start topic="tenancy" -->

Applications therefore do **not** restate their content schema as tenant
migrations. Neither does Brando. Adding `create table` migrations to
`priv/repo/tenant_migrations` would fork one schema definition into two places
that must then be kept in step by hand.

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="tenancy" -->

Tenant migrations exist to *evolve* environments that already exist. Write them
for column additions, index changes, and backfills, and generate them with:

```bash
mix brando.gen.tenant_migration add_summary_to_pages
```

<!-- usage-rules:end -->

For an umbrella or custom repository layout:

```bash
mix brando.gen.tenant_migration add_summary_to_pages \
  --migrations-path apps/my_app/priv/repo/tenant_migrations
```

<!-- usage-rules:start topic="tenancy" -->

Make them idempotent. They run against freshly cloned structure as well as
against long-lived environments, so guard them the way Brando's own tenant
migration does, with `ADD COLUMN IF NOT EXISTS` and `to_regclass` checks. Note
also that `execute/1` does not receive the migration prefix the way
`create table/2` does — read `prefix()` and interpolate it yourself.

<!-- usage-rules:end -->

### Which tables are shared

`Brando.Tenant.SharedTables` is the single source of truth. Registry,
authentication, session, and migration-history tables stay in `public`
permanently, as do authorization, which shared library items each site
enables, entry drafts, the content assistant's guidance, conversations and
proposals, content transfer receipts, form submissions, Markdown webhook
deliveries and connected AI tools (MCP), along with every `oban_*` table, since
Oban is configured against `public`:

```text
sites  sites_previews  environments  environment_operation_logs
site_asset_sets  ssg_builds  uploads_pending_intents  schema_migrations
site_enabled_modules  site_enabled_containers  site_enabled_palettes
users  users_tokens  user_tokens  user_sites  users_passkeys
users_security  users_recovery_codes  users_security_events  users_security_policy
authorization_groups  authorization_group_permissions  authorization_user_groups
authorization_legacy_mappings  authorization_audit_events  entry_drafts
ai_conversations  ai_messages  ai_runs  ai_guidance_versions
content_proposals  content_proposal_receipts  content_transfer_receipts
forms_submissions  markdown_webhook_deliveries
mcp_settings  mcp_grants  mcp_tokens  mcp_authorization_codes
oban_*
```

Environments provisioned before a table joined this list may hold an empty
copy of it (or, after `mix brando.migrate_to_tenant`, a copy of its rows).
Brando never reads those copies: the schemas for these tables are pinned to
`public`. They can be left, or dropped by hand.

`Brando.Tenant.SharedTables.list/0` returns the current list.

<!-- usage-rules:start topic="tenancy" -->

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

<!-- usage-rules:end -->

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

Individual working environments can also be created with
`Brando.Environments.create_environment/2`. It creates
`tenant_{site}_{environment}`, runs all tenant migrations, writes an operation
log, and compensates a failed schema creation or migration.

In `single` mode, the site key in the registry must match the configured
`site_key`.

## Router and request context

<!-- usage-rules:start topic="tenancy" -->

Generated routers place `Brando.Plug.Tenant` in the browser pipelines
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

A LiveView on the site's pages runs in its own process, which the plug never
reaches. Mount it with `Brando.Tenant.FrontendLiveView`, which does the same
from the page's host, or its queries read the `public` schema:

```elixir
live_session :site, on_mount: [Brando.Tenant.FrontendLiveView] do
  live "/contact", MyAppWeb.ContactLive
end
```

<!-- usage-rules:end -->

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

Which site answers on a host is the installation's decision, so only a superuser
(the Superuser group with group authorization) changes an environment's domain,
on that screen or through `Brando.Tenant.Registry`, whose `create_environment/3`
and `update_environment/3` take the acting user as `actor:` (`:system` for
trusted maintenance code) and refuse a change without one. A domain is a bare
host: no scheme, path, port or trailing dot. It may not be a host the
installation itself uses: the endpoint's, where the admin answers, nor its
static, media or CDN host. With several sites, a site that needs the admin's
host means moving the admin to a host of its own through `PHX_HOST`. In
`:single` the admin's host needs no domain: it answers from the live environment
when no environment holds it. On a `:dynamic` site, setting an environment
live moves the site's host to it (see
[Switch live, rollback, and delete](#switch-live-rollback-and-delete)), which
anyone who may switch live does: the host stays within the site.

<!-- usage-rules:start topic="tenancy" -->

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

In `:multi` mode a query on a site's table with no prefix at all raises
`Brando.Exception.MissingTenantError`: `public`'s copy of a site table is no
site's content. Run background work for a site inside
`Brando.Tenant.with_prefix/2`. Where the `public` copy is meant, as for the
shared library, pass `prefix: "public"` or run the work in
`Brando.Tenant.with_public/1`. Tables listed in `Brando.Tenant.SharedTables`, and schemas with
their own `@schema_prefix`, are not refused.

<!-- usage-rules:end -->

In `:multi`, a suspended, archived, or unknown frontend host receives `404`
before content plugs run. A stale or forged admin site selection is checked
against `public.user_sites`; it can never restore another tenant's schema
prefix. A signed-in user with no site to enter (none assigned, or only
suspended or archived ones) reaches only their own password, signing out and
choosing a site, and is sent to the access-denied page from every other admin
screen and controller. A global superuser with no active site, or with group
authorization a user granted an installation-wide permission, also reaches the
installation's screens for it (sites, users, groups, frontend assets, the
shared library), and is sent to the sites screen from the others.

Losing a site takes effect in views already open. Revoking a user's access,
or suspending or archiving the site, sends that site's open admin views to the
access-denied page, in both authorization modes. Other users, and screens that
do not depend on the site, are left as they are.

### Several nodes

<!-- usage-rules:start topic="tenancy" -->
`Brando.Tenant.Cache` keeps the site and environment registry in memory on
each node. A registry write (a site created, changed, suspended or deleted, a
domain moved, an environment created, copied, restored or set live), once its
transaction has committed, refreshes the node that made it at once and the
other nodes through `Brando.CacheSync`, over the application's
`Phoenix.PubSub`. They follow within a fraction of a second, whichever node
ran the write or the scheduled job. The active and pinned asset sets and each
site's shared-library allowlist are refreshed the same way.

Each node also keeps its own copy of a site's identity, SEO, globals,
palettes and menus, and its own query cache. A save through the context
rebuilds the saving node's copy once it has committed, and the other nodes
rebuild theirs when they hear of it. They evict cached queries of the saved
schema under the same site: every cached entry of it, not only the saved
rows, so that one message covers a whole import. A node sends its evictions
together, a tenth of a second at a time. An entry is rendered on whichever
node runs its render job; a node that runs one before it has heard of a
change made on the node that queued it (to identity, globals or menus, or
to the modules, containers, palettes or fragments entries render with)
refreshes its copy first. **Empty all caches** on the **Cache** screen
empties the node that served it; for a change no node heard of (SQL, a
seed, a mix task), empty each node or restart them.

This needs the nodes to share the application's `Phoenix.PubSub`: connected
as one Erlang cluster (with `libcluster` or `dns_cluster`, for example) for
the default adapter, or through an adapter such as `phoenix_pubsub_redis`.
Nodes that do not share it keep what they read at boot until they restart. A
node cut off when a write happens keeps its copy until the next write or a
restart.
<!-- usage-rules:end -->

## Per-site layouts and templates

<!-- usage-rules:start topic="tenancy" -->

Each site can render in its own root layout and page templates. A site's
layouts and templates are ordinary Phoenix modules compiled into the release,
so changing one takes a deploy. Generate them, with the site's entry in the
registry, for each site key:

```sh
mix brando.gen.site --site acme
```

This writes `MyAppWeb.Sites.Acme`, its `Layouts` and its `PageHTML` under
`lib/my_app_web/sites/`, and gives the CMS page controller the plug and the
page assigns described below while it is as generated. See
[Site frontends](generators.md#site-frontends) for its options and what it
leaves alone. The generator creates no site record, content or assets.

The registry maps a site key to its frontend module in config:

```elixir
# config/brando.exs
config :brando,
  site_frontends: %{
    "acme" => MyAppWeb.Sites.Acme,
    {"acme", "staging"} => MyAppWeb.Sites.AcmeNext
  },
  default_site_frontend: MyAppWeb.CMS
```

A `{site_key, environment_key}` key covers one environment, so Staging can
try a new layout before Production. Several keys may name the same module.

A frontend module names its root layout and its `PageHTML`, and may add
assigns for the layout, per language, and for each page:

```elixir
defmodule MyAppWeb.Sites.Acme do
  use Brando.Site.Frontend,
    root_layout: {MyAppWeb.Sites.Acme.Layouts, :root},
    page_html: MyAppWeb.Sites.Acme.PageHTML

  def layout_assigns(language),
    do: %{footer_menu: Brando.Cache.Navigation.get("footer", language)}

  def page_assigns(page, _assigns),
    do: %{footer_color: Brando.Pages.get_var(page, "footer_color")}

  def admin_brand, do: ~s(<img src="/images/acme-logo.svg" alt="Acme">)
end
```

`admin_brand/0` is optional. It returns the HTML the admin shows at the top of
its navigation while the site is selected, in place of
`config :brando, :client_brand`. Like `client_brand` it is trusted, being code
compiled into the release, so never build it from content. The login screen,
where no site is selected yet, shows `client_brand`.

`Brando.Site.Frontend.current/0` picks the module from the process's tenant
prefix: the `{site_key, environment_key}` entry, then the site key's entry,
then `default_site_frontend`. With neither configured, rendering uses
`:page_html_module` and the application's `PageHTML` as before.

The page controller and resource controllers that `mix brando.gen.site` and
`mix brando.gen` generate already render the site's frontend. For a controller
the generator will not touch, one the application has changed:

1. Add `Brando.Plug.SiteFrontend` to the page controller as its last plug,
   after any `put_view`, `put_layout` or `put_root_layout` it already has:

   ```elixir
   defmodule MyAppWeb.CMS.PageController do
     use BrandoWeb, :controller

     plug :put_view, html: MyAppWeb.CMS.PageHTML
     plug :put_layout, false
     plug :put_root_layout, html: {MyAppWeb.CMS.Layouts, :root}
     plug Brando.Plug.SiteFrontend

     # ...
   end
   ```

   The plug reads the site from `Brando.Plug.Tenant` and the language from
   the locale plug, which run before it in the router pipeline. It sets the
   site's `PageHTML` as the HTML view and its root layout with no inner
   layout, and merges `layout_assigns/1` for `conn.assigns.language` into the
   assigns. With nothing configured it changes nothing, so the controller's
   own view and layouts stand.

2. In both page actions (`index` and `show`), call
   `Brando.Site.Frontend.put_page_assigns(conn, page)` after assigning the
   page and before rendering:

   ```elixir
   conn
   |> assign(:page, page)
   |> Brando.Site.Frontend.put_page_assigns(page)
   |> render(page.template)
   ```

3. In any other controller that should render in the site's layout, add the
   plug with `view: false` as its last plug. It sets the site's root layout
   and layout assigns and leaves the controller's view alone:

   ```elixir
   plug Brando.Plug.SiteFrontend, view: false
   ```

In `:multi`, once `site_frontends` has an entry, a site with no entry (and no
entry for its environment) answers 404, as an unknown host does;
`default_site_frontend` then applies only while `site_frontends` is empty. In
`:none` and `:single`, a site without an entry gets `default_site_frontend`.

Startup fails when a `site_frontends` key is neither a site key nor a
`{site_key, environment_key}` tuple, or when a registered module, or
`default_site_frontend`, does not load or lacks `root_layout/0` and
`page_html/0`.

### What follows the site

Four things that are one value for the whole installation without tenancy
follow the site:

- **`og:site_name`.** In `:multi`, the identity's name for the page's
  language, else the site's name, else `config :brando, :app_name`. A value the
  page or the identity's custom metas set still wins. In `:none` and
  `:single` it is `app_name`.
- **The breadcrumbs' first entry.** `Brando.Pages` stores each page's trail
  when the page is saved, and in `:multi` titles its home entry the same way
  as `og:site_name`, in the page's language. Saving an identity with a new
  name computes the trails of that language's pages again in the environment
  it was saved in. A site renamed in the registry reaches a stored trail when
  the page is next saved, or with `Brando.Pages.update_breadcrumbs/1`, which
  computes a page's trail and those of the pages under it, under the site and
  environment's prefix.
- **The admin's brand.** The navigation shows the selected site's
  `admin_brand/0`, else `client_brand`; a `{site_key, environment_key}`
  entry applies as it does for layouts. Switching site reloads the admin,
  which then shows the new site's brand.
- **Module preview CSS.** The block editor shows modules with the
  application's admin stylesheet, `assets/backend/css/app.css`, keyed on their
  `b-tpl` names. With a site selected, every element that wraps module markup
  in the admin has `data-site="<site key>"`, so rules for one site's modules
  go inside its block; rules outside one apply to every site, as a module
  from the shared library needs. See
  [Admin and site CSS](installation.md#admin-and-site-css).

<!-- usage-rules:end -->

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
with `local`.

Resolution has two paths:

- pickers return all non-deleted local entries plus the enabled shared entries;
- rendering resolves the block's stored origin and may load a shared entry even
  after picker access was revoked.

Disabling a shared entry prevents adding new
references but never breaks published or draft blocks that already use it.
Deleting a shared entry is blocked while it is enabled, customized, or
referenced in any environment. The dashboard shows those sites and
environments before an edit or deletion.

Choosing **Customize** copies the shared entry into the selected environment
and records its source ID and source version. Blocks keep their shared identity,
so they immediately resolve to that environment's customization without a
content rewrite. Other environments and sites are unaffected. **Reset to
shared** removes only the customization. Customizing, resetting and accepting
updates of modules and containers takes a superuser, as any change to their
code does; a site manager does these for palettes.

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
mix brando.gen.migrations
mix brando.migrate
mix brando.migrate --tenants
```

## Per-site roles and lifecycle

Users are global accounts in `public.users`. Multi-site access is explicit:

```text
superuser  global role; bypasses assignments for every active site
admin      per-site role; content plus site/environment lifecycle management
editor     per-site role; content editing without lifecycle mutation
```

The superuser Sites screen at `/admin/sites` provisions sites, shows
environment/page/media/last-edit summaries, changes lifecycle state, grants
or revokes roles, and sets each site's provider library group (see
[Video provider libraries](#video-provider-libraries)). The underlying API is also available to application tooling:

```elixir
{:ok, assignment} = Brando.Tenant.Access.grant(user, site, :editor)
:ok = Brando.Tenant.Access.revoke(user, site)

{:ok, suspended} = Brando.Tenant.Setup.suspend_site(site)
{:ok, active} = Brando.Tenant.Setup.activate_site(suspended)
{:ok, archived} = Brando.Tenant.Setup.archive_site(active)
```

Permanent deletion is a second step. A site must be archived for
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

The target's [webhooks](webhooks.md) are the source's after a copy. They are
paused and the delivery log is empty, so a staging copy never calls the
endpoints production calls. An archive restored with `rollback/2` gets its
webhooks paused the same way. When an environment is set live, by hand or as
scheduled, the webhooks that were paused because it was a copy resume.
Webhooks paused by hand or after failing deliveries stay paused, and the
previous live environment keeps its webhooks as they were.

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
inside `media/{site_key}`. The database stores relative paths such
as `images/hero.jpg`, so the same URL can safely resolve to different bytes on
different site domains.

> #### Deleting an asset must not delete its bytes {: .warning}
>
> Because media is shared, copying an environment duplicates image, file, and
> video rows while leaving one copy of each file on disk. Two environments
> routinely hold different rows pointing at the same `path`.
>
> Brando therefore soft-deletes asset rows and never removes media bytes:
> `Brando.Images.delete_images/2` marks `deleted_at`, and
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
Symlinks, SVGs and dotfiles are skipped. Most importantly, if even one
environment schema cannot be inspected, the entire run fails before deleting
anything. The default
Oban cron invokes `Brando.Worker.MediaOrphanCleanup` at 05:00 UTC; applications
that replace Brando's Oban configuration must re-declare that job if desired.

## Video provider libraries

Video provider credentials (Mux, Bunny Stream, Cloudflare Stream, Vimeo) are
the installation's, so every site uploads to the same provider accounts. The
video picker's "Add from …" button browses those accounts
(`Brando.Videos.ProviderLibrary`, see [Videos](videos.md)). With
`tenancy_mode: :multi`, each site decides whether it shares them, through its
provider library group, a short key such as `agency` that an installation
superuser sets for each site on the Sites screen:

- **A site in no group**, the default, keeps its provider videos to itself.
  Its picker has no "Add from …" button, and no other site lists or adds the
  videos it uploads.
- **A site in a group** lists, and may add, the videos held by the sites with
  the same key, and the videos no site holds, such as those uploaded in the
  provider's own dashboard. A video only sites outside the group hold is not
  listed, and adding it by its id is refused.

A site holds a video while any of its current environments has a record of
it, deleted or not. A Mux upload holds its video from the start, before Mux
reports the asset. Brando reads that from the environments' video rows each
time, so an environment copy or rollback needs nothing more. An environment
whose schema is not there yet, while it is created or copied, holds nothing:
if the copy fails and Brando restores the environment's archive, another site
may meanwhile have deleted, at the provider, a video only that environment
held. If an environment's video table cannot be read, the picker lists
nothing and adds nothing until it can.

Deleting a video at the provider, when its record is deleted or purged
(`delete_remote_on`), is refused while another site holds it: that site's
record keeps playing. Brando does not delete the video later on the first
site's behalf. If the other site's record is one it added from the library,
it is never deleted remotely, and the video stays in the provider account
until someone removes it there. If the record is that site's own upload, for
example in a schema restored from an archive, deleting it deletes the video
at the provider as usual, once no other site holds it. Another site's record
holds the video even when it is deleted, so with `delete_remote_on:
:on_delete`, where a purge never asks the provider, a video both sites have
deleted stays in the provider account until someone removes it there.

A delete is refused too when the video tables cannot be read, or when an add
or another delete of the same video holds it up for more than 30 seconds.
With `delete_remote_on: :on_purge`, the purge then keeps the record and
tries again on its next run. With `delete_remote_on: :on_delete`, nothing
tries again: the record is deleted in Brando, a warning in the log names it,
and the video stays at the provider until someone removes it there.

From code, as the screen does:

```elixir
site = Brando.Tenant.Registry.get_site_by_key("acme")
{:ok, site} = Brando.Tenant.Registry.put_provider_library_group(site, "agency", current_user)
{:ok, site} = Brando.Tenant.Registry.put_provider_library_group(site, nil, current_user)
```

`put_provider_library_group/3` refuses anyone but an installation superuser
(or `:system`). With `:none` or `:single` tenancy there is one site, and the
picker lists the whole account.

### Videos in several environments of a site

Copying an environment copies its video records, so production and the
staging copied from it point at the same video at the provider. With
`:single` or `:multi` tenancy, deleting a video at the provider is refused
while another current environment of the same site has a record of it. The
deleting environment's record is still deleted or purged, and the log names
the environments that kept the video, at info level. When the last
environment holding the video deletes or purges its record, the video is
deleted at the provider. A delete refused because the video tables cannot be
read or are locked behaves as described above.

Whether another environment's deleted record holds the video depends on
`delete_remote_on` ([Videos](videos.md)):

- With `:on_purge` (the default), a deleted record holds the video until it
  is purged, because its purge may still delete the video at the provider. If
  production uploads a Mux video, staging is copied from production, and an
  editor deletes the video in staging, the purge 30 days later removes
  staging's record and leaves the Mux asset, and production's page keeps
  playing it. When both environments' records are purged, the second purge
  deletes the asset, even when the two purges run at the same time.
- With `:on_delete`, a deleted record does not hold the video, because its
  purge does not ask the provider. If staging deletes the video and later
  production does, production's delete deletes it at the provider. Staging's
  deleted record, if it is restored, then points at a video that is no
  longer there.

Another site's record holds the video whether it is deleted or not, as
described under the provider library above.

A record an environment added from the provider's library holds the video
as any other record does, but deleting it never deletes the video at the
provider. If staging adds production's upload from the library, and both
records are later deleted, the video stays in the provider account until
someone removes it there.

Rollback archives do not hold videos. A video whose last current record is
deleted is deleted at the provider even when an archive still has a record
of it, so a rolled-back archive may point at a video that is no longer
there. Check an archive's provider videos before you roll back to it.

Copying over an environment or deleting an environment removes its video
records without asking the provider. If those were the last current records
of a video, Brando never deletes that video at the provider: remove it there
yourself, in the provider's dashboard, once no archive you may roll back to
needs it.

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
constraint remains authoritative, and the routing cache is refreshed on every
node once the switch has committed ([Several nodes](#several-nodes)). On a `:dynamic` site, the site's host goes with the live
pointer, in the same transaction: the environment going live and the previous
live environment swap domains, so `www.example.com` answers from the new live
environment and `staging.example.com` from the one it replaced. A missing
domain swaps too, so switching back puts every host where it was. Setting a
restored archive live moves the host the same way. The hosts were bound by a
superuser and stay within the site, so a switch binds nothing new. On a
`:static` site the domains stay where they are: the deployed build, not the
live environment, decides what a host serves.

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

Some of Brando's upgrade migrations change every environment schema in the run
that migrates `public`, but they leave archives alone: an archive is a snapshot.
An archive taken before such a migration ran therefore lacks what it added.
Rollback brings it up to date as it restores it:

- Before anything is created, it accounts for every public migration that ran
  after the archive was taken (from `schema_migrations` and the timestamp in
  the archive's name), by finding its file under the migrations directory.
  Brando's `brando_2xx` ones that change every environment are run again in the
  restored schema only, and recorded in its `schema_migrations`. What runs is
  Brando's current template, not the application's copy, so the copy must be
  a version of the template Brando shipped: the current one or any earlier
  one, as `mix brando.gen.migrations` copied it. They are compared as code,
  where layout, comments, docs and the module name do not count. Ones that
  only change `public` are left alone. Anything else refuses the restore with
  `{:error, {:archive_behind, reason}}`: a migration that changes the
  environments and cannot be run again (Brando's older ones, or the
  application's own), a copy of a `brando_2xx` template that the application
  changed, such as one with a data backfill added (named
  `"<name> (differs from Brando's template)"`, and logged with both paths), a
  version without a file, or a migrations directory that is not there. To
  restore past a changed copy, compare it with the template, make the copy
  match it for the restore, and then run what the application added in the
  restored environment by hand.

  Brando keeps every version it has shipped of these templates in
  `priv/templates/brando.upgrade/history/<name>/`, the current one included.

  An application that keeps its migrations elsewhere, or in more than one
  directory, sets `config :brando, :public_migrations_path` to a path or a
  list of paths.
- After the tenant migrations, the restored schema must have every table and
  column (with its type, nullability and default), index, foreign key and
  unique constraint the live environment has. If it does not, the restore is
  undone and returns `{:error, {:archive_behind, {:structure, missing}}}`.

Either way, a refused or failed restore, including one where a step raises,
leaves no environment, schema or log entry behind, and the archive is
unchanged. The admin runs a restore in a task of its own, so closing the page
does not stop it halfway.

Only non-live environments can be deleted:

```elixir
{:ok, _deleted} = Brando.Environments.delete_environment(staging)
```

Deleting an environment deletes its rows in the shared tables too: form
submissions, entry drafts, assistant conversations, guidance versions, content
proposals and transfer receipts. Those of an environment that was once live go
with it, so export the submissions you want to keep first. Deleting a site does
the same for all its environments. Conversations, guidance, proposals and receipts
are found by a digest that includes the database's host and port, so those written
before the database moved stay.

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

When the job runs, the creator must still be allowed to carry it out: an active
account that may promote the site's environments (in legacy mode, an admin or
superuser of the site). A job whose creator has since lost that, or whose
account is disabled or deleted, is cancelled and changes nothing: it leaves the
list of scheduled operations, ends in Oban as cancelled with the reason
`:scheduler_not_authorized`, and a warning is logged. The site's operation log
records it with its operation, environment, note and creator, its
`cancelled_reason` set, and the Environments screen shows it there as
Cancelled, with who scheduled it and why. A job scheduled without a creator
runs as the system.

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
the release `Plug.Static`; the installer places it there.

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
`/admin/config/assets`. The first request after an activation caches both
the complete regular-file `MapSet` and optional Vite manifest in
`:persistent_term`. Requests absent from that set fall through to release
assets without a filesystem lookup. Reverting clears the active cache and
immediately restores `priv/static` fallback.
Activating and reverting reach every node ([Several nodes](#several-nodes)).

Vite manifest and critical CSS resolution follow the same active-set-first,
release-fallback order. In multi-site mode caches are keyed by the full tenant
prefix, so Production, Staging, and another site cannot share rendered content
or manifests. Every queued static build snapshots the active asset-set record
and deployment configuration at creation time. A later asset activation or
target edit therefore affects new builds, never an artifact already being
reviewed or deployed.

### Shared previews pin an asset set

A shared preview link (`/__p__/:preview_key`) stores fully rendered HTML, and
that markup links the digested stylesheet and script names of the build it was
rendered with. To keep the link working after a deploy or an activation,
`Brando.LivePreview.share/5` pins the preview to an immutable asset set before
rendering, records it in `sites_previews.asset_set_id`, and renders manifest,
inline critical CSS, and asset URLs from that set even if another set is
activated in the meantime:

- when the active uploaded set is self-contained (every file its Vite manifest
  lists is present), the preview reuses it;
- otherwise Brando captures the effective build into
  `sets/capture-<identity>`: the release's `priv/static` overlaid with the
  active set, if any. Files are copied rather than symlinked, the copy is
  published by an atomic rename from `staging/`, and the identity is derived
  from the file listing and manifest, so sharing the same release twice reuses
  one capture. Set `config :brando, :release_static_path` when the release
  assets live outside the endpoint application's `priv/static`.

`Brando.Plug.SiteAssets` serves a pinned set at the original URLs: after the
active set misses, it looks the path up in every set an unexpired preview of
that site still references. Only the content-addressed files a set's manifest
lists (entries, chunks, CSS, imported fonts and images, plus their source
maps) are served this way, so an old capture never shadows un-hashed files
such as `favicon.ico`, and compiled CSS or JavaScript that uses root-relative
`/assets/...` URLs keeps resolving without any rewriting or build changes.
A preview with no pinned set is served from the active set only; it cannot be
repaired from a later manifest and must be recreated.

A capture failure fails sharing visibly instead of storing a preview tied to
ephemeral release files.

### Pruning contract

`Brando.Assets.SiteAssets.Retention` owns the deletion decision. A set is
protected while it is active, while an unexpired preview references it
(`expires_at` is compared directly, so expired rows the purge worker has not
removed yet never prolong protection), or while a queued or running static
build still needs it as its asset source. Deletion runs under the same
per-scope advisory lock that sharing holds while it captures, renders, and
saves a preview, so a set cannot disappear underneath a preview acquiring it.

```elixir
# Ordinary retention: keep the five newest uploaded sets, skip protected ones
Brando.Assets.SiteAssets.Retention.prune_sets(keep: 5)
Brando.Assets.SiteAssets.Retention.prune_sets(site, keep: 5)

# Inspect without deleting
Brando.Assets.SiteAssets.Retention.prunable_sets(site, keep: 5)

# One set; refused with {:error, :asset_set_protected} while in use
Brando.Assets.SiteAssets.Retention.delete_set(set_id)
```

Captured sets never count against `:keep` and are removed by the preview purge
worker once the last preview that needs them has expired. Deployment tooling
such as Florist must call this API instead of deleting set directories by age
or count; protected sets may temporarily exceed the configured count. The
admin assets screen marks sets that are in use by previews or builds.

## Build and publish static sites

<!-- usage-rules:start topic="tenancy" -->

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

<!-- usage-rules:end -->

URL callbacks execute under the selected environment's tenant prefix. The
renderer sends a short-lived signed context header through the normal endpoint,
so a working environment can be built without assigning it a temporary domain.
Responses outside the 200 range are retained in the build's failed-URL list and
make the build fail without hiding partial logs or counts.

A build requests only its own origin. A listed path that redirects to another
path on that origin is stored with the answer the redirect ends at, and the
signed header goes along. A redirect to another scheme, host or port, or to a
URL carrying credentials, fails that URL: Brando makes no request there, and the
failed-URL list names the target's origin. That includes an absolute URL to the
site's public domain when the build renders through `http://localhost:4000`, so
write a redirect on a listed path as a relative path, or take the path off the
SSG module's list. A custom `:fetcher` gets `redirect: false` and returns a
redirect with its `:headers`.

Open `/admin/config/publishing` while a static site is selected. The deployment
form supports:

- `rsync`, with a target such as `deploy@example.com:/srv/www`;
- `s3`, with `s3://bucket/prefix` or, for a bucket of its own, `s3://bucket`;
- an optional public CDN URL;
- an optional completion webhook, posted after each deploy or rollback. Like
  a [webhook](webhooks.md), it must be `https` to a host with only public
  addresses; Brando checks it when it is set or changed, and again before each
  post, and does not follow redirects. The build log says when the post failed, not the
  answer;
- automatic deployment after successful builds; and
- artifact retention from 1 through 100 builds (10 by default).

An rsync target is a remote destination, `[user@]host:/absolute/path`. The
deploy mirrors the build there with `--delete`, as the server's user and with
its SSH identity, so it must be another server: local paths, `localhost` and
loopback names and addresses (however written), hosts that resolve to one of
this server's addresses, paths with `.`, `..` or empty segments,
`host::module` and `rsync://` targets, and users or hosts beginning with `-`
are refused, both when the settings are saved and when a build deploys. A
name can still reach this server in ways a check cannot see (DNS that
changes after the check, an SSH config alias, a public address behind NAT),
so to limit the destinations anyone who may deploy can choose, list them in
config (below).

An S3 deploy deletes every key under its target before it uploads the build,
with the application's one set of ExAws credentials. Its prefix may not hold
`.`, `..` or empty segments, or `?`, `#`, `%`, `{`, `}`, `\` or spaces, and
its bucket no user or port; `s3://bucket` with no prefix is the whole bucket.

List where each site may deploy in config, which admins cannot change. The
placeholder `{site_key}` stands for the key of the site being saved or
deployed, so an entry binds a destination to that site:

```elixir
config :brando, Brando.Sites.DeployConfig,
  rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}"],
  s3_targets: ["s3://static-bucket/sites/{site_key}"]
```

A target must be an entry, or lie under one that ends in `/` (not the entry
itself, which holds the others). A bucket with no prefix passes only an entry
that names it exactly, such as `s3://{site_key}-static`; `s3://bucket/` allows
every prefix in the bucket but not the bucket itself. Brando checks a target
when the settings are saved and again each time a build deploys, since a build
keeps the configuration it was made with. A refused deploy or rollback says so
in the build's log. If the target is of the right form, fix the list and the
build deploys; change a site's target and it takes a new build. An older build
whose target no longer fits cannot be rolled back until its target is listed
again, and one with a target of the wrong form cannot be deployed at all.

**An entry without `{site_key}` grants every site.** That holds for an exact
destination such as `s3://acme-www` as much as for a parent such as
`deploy@static.example.com:/srv/sites/` or `s3://static-bucket/sites/`: anyone
who may deploy one site can name that destination, or another site's directory
or prefix under that parent, and the deploy replaces what is there. Nothing
ties such an entry to a single site, so use one only if the same people deploy
all the sites. An `rsync_targets` parent without the placeholder keeps working,
and leaves the sites open to each other until it uses `{site_key}`.

When a site's destination is not named by its key, such as a bucket of its
own, give the setting a map from each site's key to that site's entries:

```elixir
config :brando, Brando.Sites.DeployConfig,
  rsync_targets: %{"acme" => ["deploy@acme.example.com:/srv/www"], "beta" => ["deploy@beta.example.com:/srv/www"]},
  s3_targets: %{"acme" => ["s3://acme-www"], "beta" => ["s3://beta-www"]}
```

An entry in the map grants only the site it is listed under, and follows the
same rules as a list entry: an exact destination, or a parent ending in `/`.
A parent grants its site everything under it, so keep each site's entries
apart: with `"acme" => ["s3://shared-bucket/"]` and
`"beta" => ["s3://shared-bucket/beta"]`, acme can deploy over beta's prefix.
A site the map does not name has no destination of that strategy, and neither
does a key that is not a string, such as `%{acme: [...]}`, or a value that is
not a list. The map is checked when the settings are saved and each time a
build deploys, as the list is.

The System check's Configuration line warns when, with `tenancy_mode: :multi`,
a list entry has no `{site_key}` or two sites' map entries reach the same
destination, and when a setting has an entry, key or value of a form no
target can pass (see
[System check](doctor.md)).

**Entries that extend each other collide on hyphenated keys.** With
`s3://b/{site_key}` and `s3://b/{site_key}-staging`, site `a` may name
`s3://b/a-staging`, which site `a-staging` owns through the first entry, so use
one entry per site layout, or separate them with a character keys cannot hold,
such as the `/` in `s3://b/{site_key}/www` and `s3://b/{site_key}/staging`.

With `tenancy_mode: :multi` the list or map of a strategy the sites use is
required: until it is set, no target of that strategy can be saved or deployed. With one
site, an unset list allows any target of the right form, including a whole
bucket; a list set there applies the same way.

Generated output is persistent at
`sites/{site_key}/ssg/builds/{version}`. Old ready, archived, and failed artifact
directories are pruned after the retention window, while their database history
and logs remain. Preview tokens expire after seven days and stop working as soon
as their artifact is pruned. A preview opens only on a host that resolves to
the build's own site (another site's host, or with several sites one of the
installation's own hosts such as the admin's, answers `404`); with several sites
the Publishing screen links it on the build environment's domain, or the live
environment's, so that domain must reach the application, not only the static
host, and with neither it shows no link. Previews are served with a Content-Security-Policy that keeps forms from
posting and the page from being framed elsewhere. The Publishing screen links
to each build's preview every time it opens, so a build keeps its token itself,
where a shared entry preview keeps only its key's hash: anyone who can read the
database can open a build's preview until it expires.

<!-- usage-rules:start topic="tenancy" -->

The command-line task uses the same renderer and is interactive by default:

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

<!-- usage-rules:end -->

Without an uploaded asset set, the task builds the local frontend with Vite and
copies `priv/static`. Pass `--no-compile-assets` to reuse the current release
files. Background builds never compile source assets on the server: they copy
the snapshotted uploaded set or the running release's `priv/static`.

The storage roots can be made explicit; otherwise they are derived alongside
the configured media directory. When the application runs as a release, a
media directory that is a symlink is followed, so with Florist's release
`media` link they sit beside the shared media, outside the release. Outside a
release the link is not followed:

```elixir
config :brando,
  media_path: "/srv/my_app/media",
  sites_path: "/srv/my_app/sites",
  site_assets_path: "/srv/my_app/site_assets"
```

Back up `sites/` and `site_assets/` alongside `media/`. Florist is
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

This section converts the installation in place. To bring another
installation's site onto a multi-site installation, see
[Move a standalone site onto a multi-site installation](#move-a-standalone-site-onto-a-multi-site-installation).

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
7. removes the entire partial site if data, media, or Staging creation fails
   (with `--move`, only when the move itself fails; see below).

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

Once the move has committed, the site's Production schema holds the only
copy of the content. If a later step fails (the media copy, or creating
Staging), the task keeps the site and its schema, says which step failed and
that the content now lives in `tenant_{site_key}_production`, and prints the
commands that finish the remaining steps.

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
created before tenancy do not contain a tenant prefix and are cancelled
rather than allowed to query `public` after tenancy is enabled;
recreate any future publication schedules after migration. Standalone uploaded
asset-set records are also not assigned to the new site automatically. Upload
or register a fresh site-scoped set, verify it, and then activate it from the
asset management screen.

The source `public` data is not deleted. Keep it and a restorable external
backup until the tenant installation has been verified and cut over.

## Move a standalone site onto a multi-site installation

A standalone installation's site moves onto a `tenancy_mode: :multi`
installation as a copy of its database and media. The source installation is
never touched: it is read twice (one `pg_dump`, one copy of its media tree),
nothing writes to it or upgrades it, and the task opens no connection to it. It
keeps serving visitors and editors throughout and stays the way back.

<!-- usage-rules:start topic="tenancy" -->

To bring another installation's site onto a `:multi` installation, restore a
copy of its `public` schema into a schema of this installation's database and
run `mix brando.migrate_to_tenant` with `--source-schema` and
`--source-media`. Never point the task, or a migration, at the source
installation's own database. The task only reads the source schema and media
directory, refuses `--move`, requires `--creator-email`, remaps every user
reference to this installation's users (by email, otherwise the creator),
keeps the new site suspended until the copy is complete, and prints the
`DROP SCHEMA` for the source schema without running it. Content in a
language this installation does not configure stops the task before it
creates anything.

<!-- usage-rules:end -->

The examples move the site of the standalone installation `MyApp` into a new
site `acme`.

1. Take one dump of the source database and one copy of its media tree:

   ```sh
   pg_dump --format=custom --no-owner --no-privileges --file=myapp.dump myapp_prod
   rsync -a myapp-server:/srv/myapp/media/ /srv/import/acme-media/
   ```

   Check: `pg_restore --list myapp.dump` lists the `public` tables, and the
   media copy holds the `images` and `files` directories the source serves.
   These are the only two reads of the source.

2. Restore the dump into a scratch database on a machine of your own:

   ```sh
   createdb myapp_scratch
   pg_restore --no-owner --dbname=myapp_scratch myapp.dump
   ```

   If the source runs an older Brando than this installation, upgrade a copy
   of the source application to the same Brando version and run its
   migrations against `myapp_scratch`, never against the source.

   Check: the restore and the migrations finish without an error. Step 4
   compares the result with this installation and stops if they still
   differ.

3. Rename the scratch database's `public` schema, dump that schema, and
   restore it into this installation's database:

   ```sh
   psql myapp_scratch -c 'ALTER SCHEMA public RENAME TO import_acme'
   pg_dump --format=custom --no-owner --no-privileges --schema=import_acme \
     --file=import_acme.dump myapp_scratch
   pg_restore --no-owner --dbname=brando_multi_prod import_acme.dump
   ```

   Check: `\dn` in this installation's database lists `import_acme`, and
   `SELECT count(*) FROM import_acme.pages` gives the source's page count.

4. Run the task:

   ```sh
   mix brando.migrate_to_tenant --site-key=acme --name="Acme" \
     --source-schema=import_acme --source-media=/srv/import/acme-media \
     --creator-email=admin@example.com
   ```

   The task first compares the source's tenant tables with this
   installation's. When the source has a table this installation does not, a
   table both have lacks a column on either side, or a column's type differs,
   it lists the differences and stops before creating anything: go back to
   step 2 and migrate the copy. A table only this installation has, such as
   an application content type the source never used, is left empty and
   named in the report. The search index and content identifiers, which
   Brando derives from content, are named apart: rebuild each with
   **Rebuild search index** and **Sync identifiers** in Configuration →
   Utilities, in Production and in Staging. The task also stops before creating anything when the
   source has entries in a language this installation does not configure (a
   Blueprint's `language` field loads only a configured language; a plain
   `language` string, such as an activity event's, is copied as it is): add
   the language to `config :brando, languages:`, or remove those entries
   from the copy. It then prints how each source user maps to a user here
   (the same email, ignoring case, or the `--creator-email` user; when two
   source users have the same email here, the first by id takes it and the
   other becomes the `--creator-email` user; no user is created), reports the media size, and asks before copying more than 1 GB
   (`--yes` skips the question).

   The site is created suspended, so no request, editor or background job
   reaches it while the copy is made. The task copies the tenant tables into
   the site's Production schema with every user reference remapped, copies
   the media into `media/acme`, computes the stored page breadcrumbs again
   (their home entry becomes the identity's name instead of `app_name`),
   creates Staging as a copy of Production, and activates the site last. On a
   failure the new site is removed, and the source schema and media are as
   they were. If removing it fails too, the task says so, lists what may be
   left, and prints the commands that remove it.

   Check: the task ends with "Imported import_acme into site acme", a report
   of what it neutralised and what to check by hand (step 8), and a
   `DROP SCHEMA "import_acme" CASCADE;` statement that it did not run. Then
   generate the site's frontend modules and port the source's layouts and
   templates into them ([Per-site layouts and templates](#per-site-layouts-and-templates)):

   ```sh
   mix brando.gen.site --site acme
   ```

5. Build the site's frontend assets and upload and activate them as an asset
   set ([Uploadable frontend asset sets](#uploadable-frontend-asset-sets)).

   Check: the asset management screen shows the set as active for `acme`.

6. Check the site before any DNS change, on a host of its own or on Staging.
   Add the source's hostname to the site only at cutover.

   Check: pages, menus, globals, images and files render as on the source, and
   an editor whose email exists here sees their own name on the entries they
   created.

7. Cut over by changing DNS. Content edited on the source after the dump in
   step 1 is not in the copy: freeze editing on the source for the cutover, or
   run the move again from step 1 under a new site key.

   Check: the source's hostname serves the new site, and the source's admin is
   closed to editors.

8. Go through what the copy does not carry, or carries made inert. The task's
   report gives the count of each:

   * Users and their logins, two-factor settings and group memberships stay
     the source's. Editors who are not here sign in only once you create
     their users and give them access to the site; their content was given
     to the `--creator-email` user. Their personal listing views, listing
     defaults, mention records and notification deliveries were not copied;
     their shared listing views now belong to the `--creator-email` user,
     with the view's id after a name that user already has. In a note, a
     mention of such an editor is plain text with their name and links to
     no one.
   * Webhooks and notification routes are paused. Their secrets were
     encrypted with the source's `Brando.Crypto` secret and do not decrypt
     here unless the two installations share it: rotate a webhook's secret
     and enter a route's URL again, then resume each.
   * Markdown sources are disabled. Check each one's connection, then enable
     it.
   * IndexNow is disabled. Enable it once the site serves its own hostname.
   * Videos at a provider are marked as imported, so deleting one here leaves
     it at the provider, where the source still plays it.
   * Deploy targets belong to the source's site record, which is not copied:
     the site delivers dynamically until you configure a target here.
   * Oban jobs stay with the source. A revision scheduled there is not applied
     here: schedule it again. An entry's `publish_at` and `unpublish_at` are
     carried out by `Brando.Worker.ScheduledPublishingSweep`, in Production
     and in Staging.
   * Forms that email their recipients on a submission start sending from
     here once visitors reach the site. Check the addresses.
   * Images and files stored on a CDN stay in the source's bucket and were
     not copied.
   * Form submissions, AI conversations, content proposals and the other
     shared tables (`Brando.Tenant.SharedTables`) are not copied.

   Check: after verifying the site, remove the source schema with the
   `DROP SCHEMA` statement the task printed, and the media copy from step 1.

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
   return `404`, and that each domain serving LiveView pages or the admin is in
   the endpoint's `check_origin` (`mix brando.install --domain` lists the
   production domain, its `www.` host and the staging host, no other
   subdomain).
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
