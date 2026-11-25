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
| `:static` | A generated HTML build, served by the installation itself (strategy `:local`) or by a static host or CDN (`rsync`, `s3`) | Content becomes public only after an SSG build is generated and deployed; a deploy or rollback served by the installation takes effect on the next request, on every node |

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

Setting the flag still does not move public traffic by itself. With the
`rsync` or `s3` strategy, the public host continues to reach Phoenix until its
web server or CDN is pointed at the configured static target. With the
strategy **Served by this installation** (`:local`), the live environment's
domain keeps answering from Phoenix until the first build is deployed, and
from the published build after that
([Served by this installation](#served-by-this-installation)). Either way a
first static build is safe to preview before anything changes for visitors,
and changing delivery mode stays independent from changing content
environments.

An asset set and a delivery mode answer different questions:

- the asset set selects which compiled CSS, JavaScript, fonts, and other
  frontend files Brando serves or copies into an SSG build;
- the delivery mode states whether Phoenix responses or a deployed static
  snapshot are intended to be the public site.

Choose `:dynamic` when editors should publish directly through Phoenix. Choose
`:static` when publication should create a reviewable, immutable artifact,
served by the installation itself or by rsync- or S3-backed static
infrastructure.

A superuser changes a site's delivery later on its form at `/admin/sites`,
which asks for confirmation and says what the change does for visitors. When
the delivery changes while the confirmation is open (a build deployed from
Publishing, say), the switch is refused and the form shows the site as it is
now. Setup code calls `Brando.Tenant.Setup.update_delivery/4`, which takes a
superuser or `:system` (with groups, the right to update sites, `:update` on
`:sites`), and refuses with `{:error, :delivery_changed}` when the site no
longer matches `expected: Brando.Tenant.Setup.delivery_state(site)`. While a
deploy, rollback or prune of the site runs, the switch is refused with
`{:error, :deploy_running}` (on the form, "A deploy of this site is running"):
try again when it has finished. A deploy that starts after a switch to dynamic
deploys nothing, and a queued one is cancelled with the reason in its build's
log. While the site is being set up, archived or deleted, or a language just
added to it is being seeded in its environments, a change of its delivery,
name or languages waits a few seconds and is then refused with
`{:error, :site_busy}`. The change activates no asset set, and what it does to
traffic depends on where the site's host points:

- **Dynamic to static.** Nothing changes for visitors. Phoenix keeps
  answering the live environment's domain until a build is deployed: with
  **Served by this installation**, the installation serves the build from the
  first deploy; with `rsync` or `s3`, visitors get a build once the domain
  points at the static host. Publishing appears in the site's menu.
- **Static to dynamic, served by this installation with a published build.**
  Visitors stop getting the build at once: the site's domain answers from
  Phoenix, which renders the live environment, so content changed since that
  build becomes public. The site forgets its published build, so switching
  back to static serves nothing from the installation until the next deploy.
- **Static to dynamic otherwise.** Nothing changes for visitors at once: with
  no published build Phoenix already answers, and a domain pointed at a static
  host keeps reaching it until it is pointed at the installation. Forms on
  pages deployed to a static host stop accepting submissions, since the
  backend takes static submissions only for a static site
  (`Brando.Forms.SubmissionController`).

Either way from static, Publishing leaves the site's menu, and a build can no
longer be requested. A build queued or scheduled before the switch ends
without building or deploying when its job runs, and its log says why.

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
rather than a prompt. Igniter also sets it when standard input is a pipe or a
file. Standard input on `/dev/null`, as some CI jobs and agents run commands,
counts as a terminal to Igniter, so pass `--yes` there.

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
deliveries, connected AI tools (MCP), each site's usage and when each static
environment's content last changed, along with every
`oban_*` table, since Oban is configured against `public`:

```text
sites  sites_previews  sites_usage_days  environments  environment_operation_logs
site_asset_sets  ssg_builds  ssg_content_changes  uploads_pending_intents  schema_migrations
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

The environments' domains and redirect hosts are bound last, once Staging is
copied, so a request on them is the unknown host's 404 until the site is
ready. A host that another environment already binds, or that the creator may
not bind, is refused before any schema is created. One that another write
binds while the site is provisioned is refused at the end, with none of the
site's hosts bound, and the site is removed as after any other failed step.

The default seeder, `Brando.Tenant.Seeder`, works in Production and, for each
of the site's languages, creates an identity named after the site, an SEO
record, and what `mix brando.setup` seeds for an installation without tenancy
(see [Seeded content](installation.md#seeded-content)): seven modules, a
published `index` page built from them, the `partials/footer` fragment and a
`main` menu. Staging gets them through the copy, so `/` answers in both
environments as soon as the site exists. `mix brando.setup --no-demo` (with
`single`), and the create form at `/admin/sites` with **Start with demo
content** unticked, provision the site with `demo: false`, which the
seeder's `seed/4` takes: the same content without the modules, so the page
and the footer have no blocks. The box is ticked by default. An
application's own seeder gets that option only when it defines `seed/4`;
without it, the form says that unticking the box changes nothing. `mix brando.seeds.remove_defaults --site KEY`
takes the demo out of a site's environments later (see
[Removing the demo](installation.md#removing-the-demo)). It writes as the system, with the
creating user as the creator of what has one, so it seeds a suspended site
and needs no rights in the site's content from the user (`authorization_mode:
:groups`). Seeding is one of provisioning's steps: when it fails,
the site is removed like any other failed step, and the jobs its content
queued are cancelled.

An application's own seeder, a module that implements `Brando.Tenant.Seeder`,
replaces the default:

```elixir
config :brando, tenant_seeder: MyApp.TenantSeeder
```

It runs in the new site's Production environment, so its queries read and
write there, and outside the admin scope of the user creating the site. Write
as `:system`, as the default does, and set `creator` as the creator where a
schema has one: the user may hold no rights in the new site's content, and a
suspended site admits no one. To keep the default content and add to it, call
the default first:

```elixir
defmodule MyApp.TenantSeeder do
  @behaviour Brando.Tenant.Seeder

  @impl true
  def seed(site, environment, creator) do
    with :ok <- Brando.Tenant.Seeder.seed(site, environment, creator),
         {:ok, _page} <- MyApp.Seeds.contact_page(site, creator) do
      :ok
    end
  end
end
```

A seeder that does not call the default creates the site's identity and SEO
records itself, one of each per language: the site's pages read them.

A language added to the site later is seeded with the optional callback
`seed_language(site, environment, language, creator)`, once in each of the
site's environments, in a job that runs in that environment. It is retried
when it returns an error or raises, so leave alone what already exists in the
language. A seeder without it gets the default's
`Brando.Tenant.Seeder.seed_language/4`, which checks each piece on its own:
the identity, SEO record, footer fragment and main menu are created unless the
language has one, trashed ones included, and the homepage only when the
language has no page at all, so a language that comes back with pages of its
own gets no demo homepage. The modules are every language's: it never adds,
restores or changes one, and the homepage leaves out the blocks of the seed's
modules that are trashed or deleted. To add to it, call it first:

```elixir
@impl true
def seed_language(site, environment, language, creator) do
  with :ok <- Brando.Tenant.Seeder.seed_language(site, environment, language, creator),
       {:ok, _page} <- MyApp.Seeds.contact_page(site, language, creator) do
    :ok
  end
end
```

The seeded content names the user who added the language as its creator,
or the installation's oldest superuser when it was added without one, from
setup code.

Individual working environments can also be created with
`Brando.Environments.create_environment/2`. It creates
`tenant_{site}_{environment}`, runs all tenant migrations, writes an operation
log, and compensates a failed schema creation or migration. The migrations
log their instructions at debug level here; `mix brando.migrate --tenants`
prints them as before. The environment's domain and redirect hosts are bound
as the last step, once its schema is migrated: until then a request on them
is the unknown host's 404, and a create that fails leaves none of them bound.
A host that another environment binds is refused before the schema is
created, and one bound by another write while the migrations ran is refused
at the end and the create undone.

In `single` mode, the site key in the registry must match the configured
`site_key`. `mix brando.setup` provisions that site, with the default
environments and the first account as its creator, when no site has the key
(see [Run setup](installation.md#run-setup)).

<!-- usage-rules:start topic="tenancy" -->

### Languages per site

Two lists of content languages have different jobs:

- **The installation's languages**, `config :brando, languages:` and
  `default_language:`, are what the installation can hold. The `language`
  field accepts these, a site is checked against them, and every language's
  label (`text:`) comes from here. Adding one recompiles Brando: see
  [Configure content and interface languages](i18n.md#configure-content-and-interface-languages).
- **A site's languages**, `languages` and `default_language` on its registry
  row, are what that site uses: a subset of the installation's, in the site's
  own order.

A superuser changes a site's languages and default language on its form at
`/admin/sites`, where the languages are a list and the default a choice among
them, which calls `Brando.Tenant.Setup.update_languages/3`. That takes a
superuser or `:system` (with groups, the right to update sites, `:update` on
`:sites`), and the screen asks for the password again when the session has
not confirmed lately; setup code can call
`Brando.Tenant.Registry.update_site/3`. Both refuse a language the
installation does not configure, and name it. `default_language` must be one
of the site's languages, so removing the default takes a new default in the
same save. A row that already holds a language the installation does not
configure keeps it, but the language is left out of the site's languages, and
loading the site logs a warning.

A language added to an existing site gets the starting content a new site
gets, in each of the site's environments: once the change is saved, a job per
environment (`Brando.Worker.SiteLanguageSeed`) runs the seeder's
`seed_language/4` (see [Provision sites](#provision-sites-and-initial-environments)).
What already exists in that language is left alone. A language added as the
new default in the same save is seeded in every environment before the save
instead, so the site's `/` has a homepage the moment it moves to that
language. If an environment cannot be seeded, the save fails with an error
that names it and the site keeps its languages; what the other environments
got stays, unseen until the language is the site's, and saving again seeds
only what is missing. While one of the site's environments is being copied,
restored or set up, that save fails at once and asks you to try again. The
site's card lists an
environment that is still being seeded; one whose last seeding failed, retried
or given up, with its error; and one that has no identity in one of the site's
languages. A failed seeding is retried, with gaps that grow from 30 seconds to
six hours, for about two and a half days before it is given up. A failed or
missing one has a button that seeds it again at once. The job
does not write into an environment while the site is being provisioned or one
of its environments copied: it waits for that to finish, and the card offers
no button meanwhile. The site's own seeding does not count: while one runs,
its row says so, and another environment can be seeded again, its job waiting
its turn. Removing a language deletes nothing: its entries stay in
each environment, and are used again when the language is added back.

In `:multi`, whatever works for one site uses that site's languages and default
language:

- In the admin, the content-language switch offers the site's languages and is
  hidden on a site with one. Language choices in forms, the language versions a
  listing or form offers to create, the language tabs of `languages: :content`
  inputs, and every fallback to the default language follow the site. An editor
  whose content language the site does not have works in the site's default
  language there; entering the site saves that, whether by switching to it,
  opening the admin, a live navigation or reconnect into it, or a link that
  names the site.
- On the public side, `Brando.Plug.I18n.put_locale/2` parses the path against
  the request's site: a first segment that is not one of the site's languages
  is not a locale, and `/` is in the site's default language. Alternates
  (`Brando.Plug.HTML.put_hreflang/2`), JSON-LD, generated SEO, absolute URLs
  and mail list and default to the site's languages. A sitemap leaves out
  entries in other languages when it pipes them through
  `Brando.Sitemap.in_site_languages/1`, as the one `mix brando.gen.sitemap`
  generates does.

The unprefixed routes belong to the request's site's default language: `/about`
is English on a site whose default is English, and Norwegian on one whose
default is Norwegian. So the router needs a prefixed scope for every language
the installation configures, the installation's default included
(`scope "/en", as: :en`), for `Brando.I18n.Helpers.localized_path/3`,
`route_i18n` and absolute URLs to give each language its own URL on every
site. `mix brando.gen` writes these scopes for a translatable resource on a
multi-site installation, and [Route the requested language](i18n.md#route-the-requested-language)
shows them for your own routes. A route's translated path segments in the
unprefixed scope are the same for every site: a `get "/news"` there is the path
of each site's default language, English or not. Without the scope of a
language that is not the site's default, `localized_path/3` returns the
unprefixed path, which is the default language's, and logs a warning naming the
missing scope, once per helper. CMS pages need no scopes: their paths are
parsed against the site's languages.

Changing a site's default language moves its URLs: the new default's entries
lose their prefix and the old default's gain one, so an English `/about`
becomes `/en/about` when the default changes from English to Norwegian.
`Brando.Tenant.Registry.update_site/3` then queues a job for each of the site's
environments that syncs its identifiers, as `mix brando.identifiers.sync` does,
so the URLs they store follow, and so do links to those entries made with the
link picker in rich text. A link typed in as a plain address keeps the old URL:
check those after changing a site's default language.
An archive taken before the change holds the old URLs, so run
`mix brando.identifiers.sync` in an environment restored from one.

Read the two values in your own code with `Brando.Languages.languages/0` (the
`[value:, text:]` entries) or `Brando.Languages.codes/0`, and
`Brando.Languages.default_language/0`. They answer for the site the process
works for, from `Brando.Tenant.Cache`, with no query. Where there is no site (a
mix task, a job with no tenant, an installation screen) they answer with the
installation's list. `Brando.Languages.installation_languages/0` always does.

The installation's list stays in force for what the `language` field accepts,
for mix tasks such as `mix brando.gen.languages`, for the upgrade snapshot, and
for the check a site moved in with `mix brando.migrate_to_tenant` goes
through. The admin's interface languages (`admin_languages`) are separate from
both lists.

In `:none` and `:single`, the installation's list is the site's, whatever the
site's registry row says.

<!-- usage-rules:end -->

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
prefix in process context without a database query. In `:multi` it answers
404 on a host that resolves to no site, except for a shared preview's link
(`/__p__/:preview_key`), which opens under the site and environment the
preview was shared from ([Where a shared preview link
opens](#where-a-shared-preview-link-opens)). A response for an environment
that is not live carries `X-Robots-Tag: noindex, nofollow`, in `:single` and
`:multi`, so a working environment on a public host such as
`staging.example.com` stays out of search results.

An environment's redirect hosts (`environments.redirect_hosts`) answer
before any of that: a request on one is redirected permanently to the same
path and query on the environment's domain, with the endpoint URL's scheme
and its port when that is not the scheme's default, 301 for GET and HEAD and
308 for other methods, from the cache and with no database query. A Markdown
request (`/about.md`, see `Brando.Plug.Markdown`) keeps its `.md`. List
`www.example.com` and an old domain there, and give the environment
`example.com` as its domain. A suspended or archived site's redirect hosts
answer 404, as its domain does. A static build's requests carry a signed
context and are served on a redirect host too, so a build whose base URL is
now one still renders.

A LiveView on the site's pages runs in its own process, which the plug never
reaches. Mount it with `Brando.Tenant.FrontendLiveView`, which does the same
from the page's host, or its queries read the `public` schema:

```elixir
live_session :site, on_mount: [Brando.Tenant.FrontendLiveView] do
  live "/contact", MyAppWeb.ContactLive
end
```

Its socket connects from the site's host, so the endpoint's `check_origin`
must accept every site's domain, including those added in the admin later.
`mix brando.install --tenancy-mode multi` writes a function for it in
`config/prod.exs`:

```elixir
config :my_app, MyAppWeb.Endpoint,
  check_origin: {Brando.Tenant.Origins, :allowed?, []}
```

`Brando.Tenant.Origins.allowed?/2` accepts the installation's own hosts
(the endpoint's, its static, media and CDN hosts) and the domain of every
active site's environments, read from `Brando.Tenant.Cache`. Redirect hosts
serve nothing, so they are not accepted. Further origins go in the argument,
in the forms a `check_origin` list takes:
`{Brando.Tenant.Origins, :allowed?, [["//*.example.com"]]}`. An entry with
no host, such as `example.com` without `//`, raises `ArgumentError`, as in
Phoenix's list. An existing
multi-site installation switches by replacing its `check_origin` list in
`config/prod.exs` with the tuple, keeping any entry that is not a site's
domain or the endpoint's host in the argument.

<!-- usage-rules:end -->

### A site's absolute URLs

<!-- usage-rules:start topic="tenancy" -->

Every absolute URL Brando writes for a site's content starts with the site's
base URL, `Brando.Utils.hostname/0`: the canonical and alternate links,
`og:url`, the `.md` alternate, JSON-LD `@id`s and URLs, sitemap entries and the
sitemap index, IndexNow submissions, relative meta images, and
`Brando.Blueprint.URL.resolve(entry, :with_host)`. Its host is the domain of the
environment the process works in:

- a request: the environment `Brando.Plug.Tenant` resolved, so Staging's pages
  name Staging's host;
- a static build: the environment being built, whatever origin the build
  requested its pages from;
- a job or other work outside a request: the environment its tenant prefix
  names (`Brando.Tenant.Job`).

An environment without a domain takes its site's live environment's. In
`:single`, a process with no prefix uses the live environment. Scheme and port
are the endpoint URL's, so development hosts work; an installation whose admin
endpoint is on a non-default port gives every site that port. With no domain to
use (`:none`, a site with no domain, a `:multi` process outside every site) it
is the endpoint's URL. It reads `Brando.Tenant.Cache`, not the database.

What is stored or cached names the site's public base URL instead,
`Brando.Utils.public_hostname/0`: the live environment's domain, whichever
environment the process works in, and whatever the site's status, so what a
suspended site stores is right when it is reactivated. An environment's own
host moves (on dynamic delivery, and on static delivery the installation
serves itself, a live switch swaps two environments' domains, a copy moves
content to another environment) and nothing stored is rendered
again then; the live domain moves with the live flag. So JSON-LD a block
renders into `rendered_<field>` (the `json_ld` filter and `<.json_ld>`) and the
sitemap files name the public base URL, the identity cache keeps a service's
URL as a path, and a sitemap is always generated from the live environment, as
the system, whoever starts it: it lists what visitors see, not what the
caller's admin scope may read.

When the public base URL changes, every environment of the site renders again
the entries whose blocks emit JSON-LD, in their modules' code (shared modules
and the environment's overrides of them included) or in their refs. That is a
change of the live environment's domain through `Brando.Tenant.Registry`, and a
live switch on a `:static` site delivered elsewhere, where the domains stay
put and the incoming environment's becomes the public one (on `:dynamic`
delivery, and on a `:static` site the installation serves itself, the domains
swap and the public base URL stays). The renders are queued once the change has
committed, each environment searched as the system; a search that fails is
logged and leaves the change saved. A render job run on a node that has not
heard of the change yet refreshes its registry cache first
([Several nodes](#several-nodes)). The sitemap follows at its next generation.

Build a site's own absolute URLs with `Brando.Utils.hostname/1` too. Phoenix's
`url/1` and `*_url` route helpers name the endpoint's host, which in `:multi`
is the admin's. The installation's own addresses (admin links, account and
notification emails, the MCP server, the static forms' `submit_url`, the
endpoint's `static_url` and CDN hosts) stay on the endpoint's URL.

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
trusted maintenance code) and refuse a change without one. The same goes for
an environment's redirect hosts, which the screen edits in a field under the
domain's, one per line or comma-separated; anyone else sees the hosts as
text. A domain is a bare
host: no scheme, path, port or trailing dot. It may not be a host the
installation itself uses: the endpoint's, where the admin answers, nor its
static, media or CDN host. A redirect host follows the same rules, and an
environment with redirect hosts must have a domain to redirect to, which
cannot also be one of them. A host is
bound once in the whole installation, as one environment's domain or one
redirect host; the database enforces it, for concurrent writes too. A save
from a screen that showed other hosts than the environment has now, after a
live switch or another superuser's change, is refused, and an open screen
shows such a change as it is made. With several sites, a site that needs the admin's
host means moving the admin to a host of its own through `PHX_HOST`. In
`:single` the admin's host needs no domain: it answers from the live environment
when no environment holds it. On a `:dynamic` site, setting an environment
live moves the site's host to it (see
[Switch live, rollback, and delete](#switch-live-rollback-and-delete)), which
anyone who may switch live does: the host stays within the site.

### Hosts and the reverse proxy

Binding a host makes Brando answer on it, but the reverse proxy in front of
the installation (Traefik, nginx) needs a route and a certificate for it too.
Brando does not write proxy configuration. It keeps a plain file of the hosts
the installation serves, and whatever deploys the installation turns that file
into routes:

```elixir
# config/runtime.exs
config :brando, Brando.Tenant.ServedHosts,
  # Unset: nothing is written, and the admin shows nothing about it
  file: "/srv/my_app/shared/served_hosts",
  # Optional. Default: the addresses the endpoint's host resolves to
  addresses: ["203.0.113.10", "2001:db8::10"],
  # Optional. :always admits every bound host without the DNS check,
  # for an installation behind a CDN or another proxy
  admit: :dns,
  # Optional. Brando.Tenant.ServedHosts.SystemResolver for hosts that
  # resolve only through /etc/hosts or the platform's resolver configuration
  resolver: Brando.Tenant.ServedHosts.DNS
```

The file holds every host the registry binds (each environment's domain and
its redirect hosts, on every site, suspended and archived ones included) once
it is admitted. A redirect host needs a route and a certificate as its domain
does, or a request for it never reaches Brando to be redirected. A host
is admitted when it resolves and every address it resolves to, IPv4 and IPv6,
is one of this server's: a proxy asks for a certificate as soon as it gets a
host, and a request for a host whose DNS still points at the old server fails
and counts against the certificate authority's limits. So a launch needs no
step on the server: change the DNS record, and within a minute the host is in
the file and the proxy can certify it. Both families must be read: when the
query of one times out, or its name server fails, the host is not admitted on
the other family's addresses, since the unread one may point at another
server, where a certificate authority that prefers IPv6 would fail the
request. It is looked up again a minute later. Brando removes a host from the
file only once no environment binds it; a failed lookup later never removes
it. The
installation's own hosts (the endpoint's, the static, media and CDN hosts) are
never in it: the deploy tool routes those itself. Nor is a bound domain that
is not a full host name such as `www.example.com`: one without a dot
(`intranet`), an IP address, or a value stored before Brando checked domains.
Brando answers on such a host, but the file holds full host names only,
whatever `admit` says.

With a preview host pattern ([Preview hosts](#preview-hosts)) the file also
holds each active static site's preview host, admitted as a bound host is. One
wildcard DNS record for the pattern (`*.preview.example.com`), made once by
hand and pointing at the installation, lets each one in as its site appears,
and the proxy certifies each over HTTP-01 like any other host: no wildcard
certificate, so no DNS-01 or DNS provider API. A preview host leaves the file
when its site is suspended, archived, deleted or switched to dynamic delivery.
The System check names a preview host the DNS check does not admit. The
pattern answers whether the file is on or not; only the file is skipped. Keep
the session cookie's `Domain` off the pattern's base: a cookie for
`.example.com` reaches `acme.preview.example.com`, where a build's scripts run.

Brando checks at boot, after every registry write (on every node, as
[Several nodes](#several-nodes) describes), once a minute while a bound host
waits for its DNS, and every five minutes otherwise. A host whose lookup
timed out is looked up again once after five to ten seconds
(`:timeout_retry_interval` in milliseconds), before the minute: a local
caching resolver can take longer than a lookup allows to answer its first
query for a name, and a name that does not exist then shows **Does not
resolve** within seconds rather than a minute later. The slow check reads the
file again, so a host another node sharing the path wrote over, during a
blue/green switch, goes back in: without a lookup when this node saw it in the
file or admitted it since it started, after admission otherwise. Nothing is
looked up while the file holds every bound host. Each node keeps its own file,
and nothing is stored in the database: on a new server the file starts empty,
and each host is admitted there when its DNS arrives.

A few seconds after each write (five by default, `:verify_interval` in
milliseconds), the file is read again, and a host this node admitted that is
still bound but missing goes back in without a lookup. Nothing locks the file
between installations, each of which reads, merges and replaces it, so two
installations that share one file path at the same moment, as during a
blue/green switch, can overwrite each other's newest admission. The host is
put back by that verification a few seconds later when the node that admitted
it is still running, and otherwise is admitted again at the next check, since
its DNS still points at the server.

A host a write binds has a state as soon as the write returns; reading and
writing the file and the lookups happen after it, in tasks of their own, so a
slow disk or DNS never holds a registry write back, the next one included. The
file is written by one task at a time: on a disk that stalls, the file and the
hosts' states wait for it, and later writes follow it as one. A host shows
**Served** only once the write that put it in the file has succeeded. Each
host is looked up on its own, at most eight at a time while the rest wait
their turn, and its lookup fails when it does not answer within the lookup
timeout (ten seconds by default, `:lookup_timeout` in milliseconds), counted
from when it starts.

Brando asks the name servers in the system's resolver configuration
(`/etc/resolv.conf`) itself, through Erlang's `:inet_res`: each family's query
waits a second and then two for each name server, and takes at most four
seconds, a `CNAME`'s target included, so a host takes at most eight. That is
how it tells a family with no records from one whose query timed out. Name
servers that do not answer use up those four seconds: each query gives a dead
one a second before asking the next, so with the first two of three dead, a
host behind a `CNAME` with no record of a family, which needs two queries for
it, times out on the second, and is not admitted while those name servers stay
dead. The admin then says the lookup timed out; remove or fix the dead name
servers in `/etc/resolv.conf`. It does
not read `/etc/hosts`, nor platform-specific resolver configuration
(`nsswitch.conf`, the per-domain resolvers of macOS). An installation whose
hosts resolve only through those sets
`resolver: Brando.Tenant.ServedHosts.SystemResolver`, which asks the operating
system as other programs do, but cannot tell the two apart: a family whose
lookup timed out counts as one with no records, and a host is then admitted on
the other family alone. Any module implementing
`Brando.Tenant.ServedHosts.Resolver` can take its place. A host's result shows as soon as it answers; the answers
of many hosts looked up together, as on a new server, are written to the file
in one go. Without `addresses`, this server's are looked up once per check
that looks a host up, and at the first check after a start, so the
**Environments** screen names them before any host needs a lookup; a lookup of them that fails keeps the ones found before, for an hour
after they were found: a server whose own lookup keeps failing, or cannot read
one of the families, then admits no host until it answers again.

The **Environments** screen shows each bound host's state beside the host:
the domain's under its field, naming the saved domain only when it is too
long for the field to show whole or the field holds a domain not saved yet, then one line for each redirect host, led by its
name:
**Served** when it is in the file, **Checking** while its first lookup runs,
**Waiting for DNS** with what the host resolves to now and this server's
addresses, **Does not resolve** when it has no address records, **Could not
look it up** when its latest lookup could not read one family or both, or
**Not a full host name** for a bound host the file leaves out. **Could not
look it up** names the family and why, for example "The IPv6 lookup failed:
the name server reported a failure. It will be tried again." The reasons are:
the query timed out, the name server reported a failure, the name server
refused the query, the answer was cut short, no name server is configured, or
another error. A host in the file stays **Served** whatever a later lookup
finds. A warning is logged, with the host, the family and the reason, when a
host starts failing and when its reason changes, not at each retry. A file
that could not be written is shown above the list (with the reason to
superusers only), logged once, and tried again every minute; the application
keeps running.

A host that shows **Could not look it up** check after check will not be
admitted until the cause is fixed:

- A domain whose name servers fail one family's query every time (an `AAAA`
  query answered with a server failure, say): fix the domain's name servers. A
  certificate authority that looks up both families fails on such a domain
  too, so admitting it on the other family would not get it a certificate.
- No name server is configured on the server (an empty or missing
  `/etc/resolv.conf`): every host ends here. Configure one, or choose
  `SystemResolver`.
- Hosts that resolve only through `/etc/hosts` or the platform's resolver
  configuration: choose `resolver: Brando.Tenant.ServedHosts.SystemResolver`.
- An installation whose proxy need not wait for DNS, behind a CDN or another
  proxy: `admit: :always`.

The file's contract, for anyone writing their own consumer:

- One host per line, lowercase, sorted, each line ending in a newline. No
  comments, ports or schemes. An empty file means no host is admitted.
- Replaced whole: written to a temporary file in the same directory (named
  `.served_hosts.<random>.tmp` beside a file named `served_hosts`), synced to
  disk and renamed over the old one, so a reader never sees half a file.
  Watch the directory, or the file by name rather than by inode, and ignore
  those temporary files.
- Rewritten only when its content changes. A line that is not a bound host,
  added by hand, is dropped on the next write.

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

### Where the admin answers

With `:multi`, the admin answers on the endpoint's host only:
`Brando.endpoint().host()`, which `PHX_HOST` sets. On any other host, every
route `Brando.Router.admin_routes/3` and `Brando.Router.mcp_routes/0` mount
answers as a path that does not exist there, wherever they are mounted, an
enclosing scope included. The request goes to the route it would match
without them, the application's own routes keeping their order, normally the
site's catch-all: a site's host answers with its own 404 page, or with its
own page at `/admin` when it has one, and a host bound to no site answers
with the plain 404. Nothing redirects to the admin's host, and deciding costs
no database query. With `:none` and `:single` the admin answers on every
host. A static site's [preview host](#preview-hosts) is such a host too: the
admin's routes, and an admin LiveView joined from it, refuse there.

Nothing else on a site's host names the admin either: its default
`robots.txt` has no `Disallow: /admin/`, `Brando.MCP.BodyLimit` and
`Brando.Plug.Markdown` treat `/mcp` and `/admin` as any other path, and a new
site's seeded homepage, menu and footer have no admin links.

The admin socket takes connections from the endpoint's host only, whatever
the endpoint's own `check_origin` accepts for the sites' pages.
`mix brando.install --tenancy-mode multi` writes the endpoint's socket line
with its origin check; an existing installation adds it to that line:

```elixir
socket "/admin/socket", BrandoAdmin.AdminSocket,
  websocket: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}],
  longpoll: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]
```

Live previews (`/__livepreview`) and shared previews' links (`/__p__/:key`)
are not admin routes, and open on the hosts they opened on before.
[Frontend edit mode](frontend_edit.md) frames an admin view from the page's
own host, so with several sites it adds nothing to the sites' pages.

The router leaves the admin's routes out wherever it matches a route, so
`Phoenix.Router.route_info/4` on a site's host finds the site's own route, as
the request did. A LiveView's websocket join looks its route up by the host in
the URL the client sends, not the host the socket connected to, so an admin
LiveView refuses a connected mount on a host that does not serve the admin,
as it refuses one without a signed-in user. It can tell only when the
endpoint's `/live` socket gives the socket's URI, with `:uri` in each
transport's `connect_info` list; without it, the join goes by the host the
client names. `mix brando.install --tenancy-mode multi` adds `:uri` to the
lists it can read as literals, and prints a notice for a socket line it
cannot edit (a transport set to `true`, options from a module attribute). An
existing installation adds it by hand, keeping whatever else the lists hold:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:uri, session: @session_options]],
  longpoll: [connect_info: [:uri, session: @session_options]]
```

One known limit: the endpoint answers the admin socket's transport paths
(`/admin/socket/websocket`, `/admin/socket/longpoll`) before the router, so on
a site's host they answer as a socket refusing the connection, not with the
site's 404.

### Several nodes

<!-- usage-rules:start topic="tenancy" -->
`Brando.Tenant.Cache` keeps the site and environment registry in memory on
each node. A registry write (a site created, changed, suspended or deleted, a
domain or redirect host moved, an environment created, copied, restored or set live), once its
transaction has committed, refreshes the node that made it at once and the
other nodes through `Brando.CacheSync`, over the application's
`Phoenix.PubSub`. They follow within a fraction of a second, whichever node
ran the write or the scheduled job. A static build's deploy or rollback served
by the installation is such a write: every node answers from the newly
published build once it has heard of it, so every node needs the same
`sites/` directory, on shared storage as media is. The active and pinned asset sets, each
environment's own set, and each site's shared-library allowlist are
refreshed the same way.

Each node also keeps its own copy of a site's identity, SEO, globals,
palettes and menus, and its own query cache. A save through the context
rebuilds the saving node's copy once it has committed, and the other nodes
rebuild theirs when they hear of it. They evict cached queries of the saved
schema under the same site: every cached entry of it, not only the saved
rows, so that one message covers a whole import. A node sends its evictions
together, a tenth of a second at a time. An entry is rendered on whichever
node runs its render job; a node that runs one before it has heard of a
change made on the node that queued it (to identity, globals or menus, or
to the modules, containers, palettes or fragments entries render with, or
to the site and environment registry) refreshes its copy first. For a change
no node heard of (SQL, a seed, a mix task), a superuser clears every node's
caches under **Configuration → Utilities → Clear caches**: every site's
query cache, identity, SEO, globals, palettes and menus, the site and
environment registry, and each site's shared-library allowlists. Restarting
the nodes does the same.

This needs the nodes to share the application's `Phoenix.PubSub`: connected
as one Erlang cluster (with `libcluster` or `dns_cluster`, for example) for
the default adapter, or through an adapter such as `phoenix_pubsub_redis`.
Nodes that do not share it keep what they read at boot until they restart. A
node cut off when a write happens keeps its copy until the next write or a
restart.
<!-- usage-rules:end -->

Nodes do not answer a refresh. Where a step must wait for every node, as
dropping the schema of an environment whose hosts were just released does,
Brando waits for the time the other nodes take to hear and run it:
`config :brando, :cache_sync_settle_ms`, 500 milliseconds by default. Raise it
when a busy node takes longer to refresh.

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

The frontend asset set, the compiled CSS and JavaScript the layout links,
resolves for the environment in the same order:

1. the environment's own set, when it has one;
2. else the site's active set (in `:single`, the installation's active set);
3. else the release's `priv/static`.

Whatever reads a set resolves it this way for the environment at hand: the
files `Brando.Plug.SiteAssets` serves on the environment's host, the script
and style tags, Vite manifest and critical CSS a page renders with, a live
preview of the environment being edited, a shared preview (which pins the
set of the environment it was shared from), and a static build of the
environment. See [A set per environment](#a-set-per-environment).

A path the host's own sets miss (the set its environment uses, and the
sets its site's shared previews pin) answers from the own set of another
environment of the same site, sent with `cache-control: no-cache`. A live
preview of Staging is shown on a host that resolves to another environment
(the admin's host, which in `:single` resolves to the live environment, or
in `:multi` the site's own host when the admin is opened there), and so is a
shared preview from Staging; their pages name Staging's files host-relative,
those of its build's `public/` directory included. The host's own file wins
when both hold a path. A path two other environments hold with different
content stays unanswered, a path the release's `priv/static` holds is left
to the release, and another site's sets never answer.

To try a new layout on Staging together with its CSS and JavaScript, then
put both live, on a `:dynamic` site:

1. Add `{"acme", "staging"} => MyAppWeb.Sites.AcmeNext` to `site_frontends`
   and deploy. Production keeps rendering with `MyAppWeb.Sites.Acme`.
2. Build the new frontend, upload it to the site's `sets` root and register
   it, as in [Uploading a site's build by hand](#uploading-a-sites-build-by-hand).
3. With Staging selected, open `/admin/config/assets` and choose
   "Activate for Staging" on the new build. Staging's host now serves it
   and Staging's pages, previews and builds render with it; Production
   keeps the site's active set.
4. When Staging is approved, switch it live
   (`Brando.Environments.set_live/2`, or the environments screen). The
   production host moves to Staging, and the layout and set go with it: both
   belong to the environment, so the host serves the set Staging was tested
   with. Nothing is copied or swapped.
5. To make the new build the site's own, activate it for the site, and
   choose "Use the site's build" on the environment.

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

### Each site's frontend source

A site's layouts are compiled into the release, but its scripts and styles
need not be. In `:multi`, each site's frontend source can be a Vite project
of its own in `assets/sites/<key>/`, whose build is uploaded as that site's
[asset set](#uploadable-frontend-asset-sets). `assets/frontend` stays the
release's default frontend, which a site without an active set gets.
`mix brando.gen.site --site acme` creates `assets/sites/acme/` from the
templates that give a new installation `assets/frontend`. Its Vite config
reads `BRANDO_VITE_FRONTEND_HOST` and `BRANDO_VITE_FRONTEND_PORT` as the
default frontend's does and builds into the project's `dist/`, and its
`package.json` is named `acme`. `.gitignore`, and `.dockerignore` when the
application has one, get the lines that keep every site project's
`node_modules` and `dist` out of Git and out of the Docker build context.
An existing `assets/sites/acme/` is left as it is: to complete one left
half-written, or to start it over, delete it and run the task again. The
task installs and builds nothing: run `pnpm install` and `pnpm build` in the project.

In development, one Vite dev server runs one site's project. Say which
with `dev_site`, beside `hmr`, and point the `vite_site` watcher at the same
project:

```elixir
# config/dev.exs
dev_site = "acme"

config :my_app, hmr: true, dev_site: dev_site

config :my_app, MyAppWeb.Endpoint,
  watchers: [
    vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
    vite_site: {Brando.Vite, :watch, [Path.expand("../assets/sites/#{dev_site}", __DIR__)]}
  ]
```

With `tenancy_mode: :multi` and HMR on:

- A request for the dev site loads its frontend from the Vite dev server. It
  reads nothing from the site's active asset set: not the script and style
  tags, the Vite manifest, the critical CSS (which comes from the release's
  `priv/static`, as in any development setup), nor a file
  `Brando.Plug.SiteAssets` would serve from the set. While an unexpired
  shared preview pins the site's active set or an environment's own set,
  that set answers any of its files, its `public/` fonts and images
  included, on the site's hosts and the admin's, as the preview renders
  from it; another pinned set answers the files its Vite manifest lists.
  At a path the release's `priv/static` also holds, the release's file
  wins. A file of the project's `public/` folder
  (`assets/sites/<key>/public/`), such as the favicon the layout links or
  a font the site's CSS names, is served from that folder on the site's
  hosts and on the admin's, for the live preview, where neither the
  release nor a pinned set holds the path: the page names it
  host-relative, while the Vite dev server serves it only on its own
  origin. On the admin's host the folder answers only where no site's set
  holds the path, so another site's live preview keeps its set's file; a
  host that resolves to no site but is not the admin's never reads the
  folder. When the `vite_site`
  watcher could not start Vite, the dev site renders the release's build
  with a notice saying why.
- A request for any other site renders as in production: from its active
  set, or without one from the release's `priv/static`, read afresh on each
  request so a new build shows without a restart. A site with neither
  shows a notice saying so. Give the other sites a build with the steps
  under
  [Uploading a site's build by hand](#uploading-a-sites-build-by-hand).
- Live preview follows the same rule for the site it renders. A shared
  preview never loads from the dev server, as its link outlives it: one of
  the dev site renders from the set it pins, as any site's does. That is
  the environment's own set or the site's active set; without either, a
  capture of the release's `priv/static`, when the site has no Vite project
  of its own in `assets/sites/<key>/` (with no Vite manifest in
  `priv/static` the admin says to run `pnpm build` in `assets/frontend`). A dev site with a project
  of its own and no set cannot be shared: the admin says to build and
  upload a set first
  ([Uploading a site's build by hand](#uploading-a-sites-build-by-hand)).

The admin answers on the endpoint's host: with the endpoint on `localhost`,
`localhost:4000/admin` opens it and `acme.localhost:4000/admin` is a 404
([Where the admin answers](#where-the-admin-answers)).

Without `dev_site`, every site loads from the dev server, as on a
single-site installation. Set in `:none` or `:single`, or naming a site that
does not exist, `dev_site` is ignored, with a warning at boot. Production,
`:e2e`, `:test` and static builds never read it.

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
shared** removes only the customization, and Brando queues the environment's
entries that use it for rendering with the shared version. When the
environment's customization is in the trash, **Customize** restores it with
its edits, as a restore from the trash does, so it takes the restore
permission too; **Accept update** refuses a customization in the trash.
Customizing, resetting and accepting
updates of modules and containers takes a superuser, as any change to their
code does; a site manager does these for palettes.

Publishing a shared edit increments its version and records a changelog note.
Sites without a customization use the new version immediately, and Brando
queues affected entries for rendering in each environment. A customization
continues using its local version and receives an **Update available** badge.
The administrator can inspect a field-level diff, replace the customization
with the current shared version, which queues the environment's entries that
use it for rendering, or dismiss that version's notification.

A site's palette CSS holds its own palettes and the shared palettes its
content can use: those enabled for the site, and those its blocks still use
after they were disabled. A customized palette takes the place of its shared
one, and the site's own palette wins over a shared one with the same namespace
and key. Enabling, disabling, customizing, resetting, accepting an update and
editing a shared palette rebuild the CSS in the environments that use it.

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

The superuser Sites screen at `/admin/sites` lists the sites and shows one
at a time, named in the URL (`?site=acme`, or `?new` for the create form;
without one, the admin's current site). It provisions sites, shows
environment/page/last-edit summaries and each site's usage
([Usage per site](#usage-per-site)), renames a site (its key, which
names its schemas and folders, stays), changes lifecycle state and
delivery ([Choose a delivery mode](#choose-a-delivery-mode)), grants or
revokes roles, and sets each site's provider library group (see
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

## Usage per site

With `tenancy_mode: :multi`, the Sites screen shows a superuser what each
site uses: in the list, each site's total storage as last measured and its
requests in the last 30 days; on a site, a Usage section with its media, its
kept static builds, each environment's database with its archives under it,
the change in storage over the 30 days, its requests and bytes per day with a
small trend, and the installation's total next to the free space on the media
volume. "Measure now" measures one site at once, as for a site just imported,
and the screen shows it when it lands. Oban retries a failed manual measurement
up to a total of three attempts. Nobody else sees any of it: in groups
mode, reading the screen takes only the Sites read permission, so a delegated
reader sees the screen without usage, and "Measure now" is refused for them.
In `:none` and `:single` nothing is counted, measured or shown.

Rows live in `public.sites_usage_days`, one per site per UTC day, and are kept
13 months:

```elixir
config :brando, Brando.Sites.Usage,
  retention_months: 13,
  flush_interval: :timer.seconds(60)
```

**Storage** comes from `Brando.Worker.SiteUsage`, once a day at 05:45 UTC on
its own `site_usage` queue: it measures every site and stores the snapshot on
the day's row, then deletes rows past the retention period. The daily job
lists tenant schemas once at the start. Open Sites screens refresh when the
sweep finishes. A site whose measuring fails keeps its last snapshot, and
the screen says which day a figure is from. A day with traffic and no
measurement shows storage as unknown, never as zero, and no change is shown without two measurements in
the 30 days. Folders are walked without following links inside them, and kept
builds are measured whatever the site's delivery is today; the builds are
reached from the site's folder only through folders that are no links. A
file that disappears during the walk is skipped. If a file's metadata cannot
be read or a sizing query fails, the site keeps its last complete snapshot.
Brando's default Oban configuration has the queue and the cron entry with
`tenancy_mode: :multi` only. An application
with its own `config :brando, Oban` adds both itself on a `:multi`
installation; the System check names them when they are missing there:

```elixir
queues: [site_usage: [limit: 1], ...],
cron: [crontab: [{"45 5 * * *", Brando.Worker.SiteUsage, args: %{"all" => true}}, ...]]
```

**Traffic** is counted by `Brando.Plug.Usage`, first in the endpoint:

```elixir
plug Brando.Plug.Usage
plug Brando.Plug.SiteAssets
plug Plug.Static, ...
```

A request counts for a site when its host is one of an active site's
environment domains or redirect hosts, whatever answers it: a page, a static
file, a media file, a redirect or a 404. The admin's host and the
installation's other hosts (its static, media and CDN hosts), a shared preview
on them, an inactive site's host and a host no site has count for nobody, also
when a site was bound to one of the installation's hosts before that was
refused. Nothing
is stored but the site, the UTC day the request arrived, one request and the
bytes of the response body as the application sent it: a file's length, or a
range response's range, and 0 for HEAD and 304. A file is sized by the file
the serving code names (`Brando.Plug.Usage.put_file/2`, as Brando's media,
site assets, static delivery, preview and sitemap do) or, for the release's
`Plug.Static`, by the file it serves; a file response nobody named counts as a
request with 0 bytes. Counts are kept in memory on each node and added to the
day's row every minute and when the node stops. The endpoint starts before
the counters and stops after them, so the requests a node answers in its
first moments and after that last write are not counted.

Limits:

- These are operating figures, not invoices. A node that dies loses the counts
  since its last flush; while the database is away, counts wait in memory, and
  a write that committed while its answer was lost is counted twice.
- A chunked response counts as a request with 0 bytes, and WebSocket and
  long-poll connections (LiveView on a site's pages) are not counted: Phoenix
  dispatches them before the endpoint's plugs.
- An error raised by a plug before the router, such as `Plug.Parsers`
  answering 400 or 413 to a body it cannot read, is not counted: Phoenix
  renders it from the request as the endpoint received it, before the plug saw
  it. A path no route matches and an error in a controller are counted.
- Archives of a site whose key is very long are cut short when named. Those of
  its current environments, and those the environment log records, are
  counted; one of an environment deleted before the log recorded archives may
  be missing from the figure.
- A site published to another host (`rsync`, `s3`) shows what still reaches
  this installation; the screen says where it is published to.
- The installation's total is the sum of the measured sites. Databases on
  another volume count in it but not in the free space, which is that of the
  volume holding the media folder.
- CPU and memory per site are not shown: every site runs in one VM.

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
  listed, and adding it by its id is refused. Its collection dropdown names
  every Bunny collection or Vimeo folder of the account, without the number
  of videos in each, which would count the videos it may not see.

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
domain swaps too, so switching back puts every host where it was. Each
environment's redirect hosts move with its domain, so `www.example.com` keeps
redirecting to `example.com` wherever that host now answers. Setting a
restored archive live moves the hosts the same way. The hosts were bound by a
superuser and stay within the site, so a switch binds nothing new. A
`:static` site the installation serves itself (strategy `:local`, see
[Served by this installation](#served-by-this-installation)) swaps its hosts
the same way, since the installation answers its public host: the domain goes
to the incoming environment and keeps answering from the published build until
the next deploy. On any other `:static` site the domains stay where they are:
the deployed build, not the live environment, decides what a host serves. Each environment keeps its own
frontend asset set and frontend module, so the host serves those of the
environment that went live ([A set per environment](#a-set-per-environment)).

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

The environment's domain and redirect hosts are released first. Brando waits
for every node to refresh its registry cache (see [Several nodes](#several-nodes))
before it drops the schema, so a request on them from then on is the unknown
host's 404. In `multi` mode it waits also for an environment that binds no
host, as one released just before may still be routed by another node. When
this node's cache still resolves one of the environment's hosts, Brando
refreshes it once more; if the host still resolves, the delete returns
`{:error, {:hosts_still_resolve, hosts}}` and the schema stays. When the
schema cannot be dropped, the hosts are bound to the environment again. When
one of them cannot be, because another environment took it meanwhile, the
delete returns
`{:error, {:schema_not_dropped, reason, {:hosts_released, domain, redirect_hosts}}}`:
the schema is still there and those hosts are bound to no environment.

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
release-fallback order, after an environment's own set
([A set per environment](#a-set-per-environment)). In multi-site mode caches are keyed by the full tenant
prefix, so Production, Staging, and another site cannot share rendered content
or manifests. Every queued static build snapshots the asset set its
environment uses and the deployment configuration at creation time. A later
asset activation or target edit therefore affects new builds, never an
artifact already being reviewed or deployed, nor a build still waiting to
run: it copies the set it recorded and renders every page with it (with the
release's `priv/static` when it recorded none). A build whose recorded set
was deleted before it ran fails, saying so in its log, and publishes nothing.

### A set per environment

In `:multi` and `:single`, an environment may use a registered set of its
own (`environments.asset_set_id`) in place of its site's active set; its
host, pages, previews and static builds then use that set, and the site's
other environments keep the site's active set. The set's `active` flag keeps
meaning the site's set, so an environment without a set of its own follows
it. In `:none` there are no environments.

At `/admin/config/assets`, the Environments section shows which build each
environment of the selected site uses, and whether it is its own or the
site's. "Activate for <environment>" on a build makes it the own set of the
environment being edited; "Use the site's build" clears it. Activating a set
for the site works as before. The screen needs the same permission as
before.

Deploy tooling calls the same by RPC, next to `register_set/3` and
`activate_set/1`. The environment is a struct, its id or
`{site_key, environment_key}`:

```elixir
{:ok, set} =
  Brando.Assets.SiteAssets.register_set(
    "acme",
    "/srv/my_app/sites/acme/assets/sets/20261114_def456",
    %{revision: "def456"}
  )

{:ok, _staging} = Brando.Assets.SiteAssets.activate_environment_set(set.id, {"acme", "staging"})

# Follow the site's active set again; the set stays registered
{:ok, _staging} = Brando.Assets.SiteAssets.clear_environment_set({"acme", "staging"})
```

`activate_environment_set/2` refuses a set of another site with
`{:error, :asset_set_belongs_to_another_site}`; in `:single` the set must
be one of the installation's. Both reach every node
([Several nodes](#several-nodes)).

What happens to an environment's set:

- **A live switch** leaves each set with its environment. On a `:dynamic`
  site, and a `:static` one the installation serves itself, the host moves to
  the incoming environment, so it serves the set that environment had.
- **A new environment** has no set of its own and follows the site's set, as
  it follows the site's frontend module.
- **A copy of content into an environment**
  (`Brando.Environments.copy_environment/3`) replaces its content and keeps
  its set, as it keeps its frontend module, which is chosen by its key in
  `site_frontends`.
- **Deleting an environment** drops its reference; the set stays registered.
- **Pruning** leaves a set an environment uses alone, as it does the active
  set ([Pruning contract](#pruning-contract)).
- **In development**, `dev_site` names a site: with HMR on, every
  environment of the dev site loads from the Vite dev server and reads none
  of its sets, except for a shared preview, which pins one.

### Uploading a site's build by hand

Until Florist uploads a site's own build, put a build of
`assets/sites/<key>/` in front of the site's visitors by hand. The same
steps on a development machine give the sites other than `dev_site` their
last built set. For `acme`:

1. Build the project into its `dist/`, never into `priv/static`, which is
   the release's default frontend. A project the generator created already
   builds there; the options also cover one copied from `assets/frontend`,
   whose own `outDir` would write to `assets/priv/static`:

   ```sh
   cd assets/sites/acme
   pnpm build --outDir dist --emptyOutDir
   ```

   Then delete the source maps. The Vite config builds them hidden (no
   `sourceMappingURL` comment), and `mix brando.digest` deletes them from a
   release (see [Source maps](deployment.md#source-maps)), but a set serves
   every file it holds, so a map left in it is public at its script's path
   plus `.map`:

   ```sh
   find dist -name '*.map' -delete
   ```

2. Copy the output into the site's `sets` root, in a directory named for
   the build. The root is `sites/acme/assets/sets/` beside the media
   directory, or under `config :brando, :sites_path` when set
   (`Brando.Assets.SiteAssets.sets_root("acme")` gives it). A site that never had
   a set has no `sets` directory yet:

   ```sh
   mkdir -p /srv/my_app/sites/acme/assets/sets
   cp -R dist /srv/my_app/sites/acme/assets/sets/20261113_abc123
   ```

3. Register it, from a remote console (`bin/my_app remote`) or `iex -S mix`.
   Registering writes a database row from the files it finds, and nothing a
   running server holds in memory, so in development an `iex -S mix` beside
   a running `mix phx.server` registers a set that server then lists:

   ```elixir
   Brando.Assets.SiteAssets.register_set(
     "acme",
     "/srv/my_app/sites/acme/assets/sets/20261113_abc123",
     %{revision: "abc123"}
   )
   ```

4. Activate it at `/admin/config/assets`, with `acme` selected: for the
   site, or for the environment being edited. Activate it there, in the
   running server, rather than with `activate_set/1` from the second node:
   that changes the database, but not the caches of a server it is not
   clustered with, which keeps serving what it served before.

The build directory must contain, at its top level:

- `manifest.json`, the Vite manifest (`build.manifest: 'manifest.json'`, as
  the installer's Vite config sets; Vite's default, `.vite/manifest.json`,
  is not read). Its `isEntry` entries give the page its script and style
  tags, and the entry named `critical` (`js/critical.js`) its inlined
  critical CSS.
- Every file the manifest lists, at the path it lists it under, relative
  to the directory: `assets/…` for Vite's output. The page links them as
  `/assets/…`, which `Brando.Plug.SiteAssets` serves from the set.
- Anything else the site requests from its own root, such as the files
  Vite copies from the project's `public/` (`favicon.ico`, fonts, images),
  at the path it is requested under. A path the set lacks falls through to
  the release's `priv/static`.

Only regular files and directories: registration refuses a symlink or other
special file.

### Shared previews pin an asset set

A shared preview link (`/__p__/:preview_key`) stores fully rendered HTML, and
that markup links the digested stylesheet and script names of the build it was
rendered with. To keep the link working after a deploy or an activation,
`Brando.LivePreview.share/5` pins the preview to an immutable asset set before
rendering, records it in `sites_previews.asset_set_id`, and renders manifest,
inline critical CSS, and asset URLs from that set even if another set is
activated in the meantime:

- when the set the environment shared from uses (its own, else the site's
  active set) is self-contained (every file its Vite manifest lists is
  present), the preview reuses it;
- otherwise Brando captures the effective build into
  `sets/capture-<identity>`: the release's `priv/static` overlaid with that
  set, if any. Files are copied rather than symlinked, the copy is
  published by an atomic rename from `staging/`, and the identity is derived
  from the file listing and manifest, so sharing the same release twice reuses
  one capture. Set `config :brando, :release_static_path` when the release
  assets live outside the endpoint application's `priv/static`.

`Brando.Plug.SiteAssets` serves a pinned set at the original URLs: after the
set the host's environment uses misses, it looks the path up in every set an unexpired preview of
that site still references. Only the content-addressed files a set's manifest
lists (entries, chunks, CSS, imported fonts and images, plus their source
maps) are served this way, so an old capture never shadows un-hashed files
such as `favicon.ico`, and compiled CSS or JavaScript that uses root-relative
`/assets/...` URLs keeps resolving without any rewriting or build changes.
A preview with no pinned set is served from the active set only; it cannot be
repaired from a later manifest and must be recreated.

A capture failure fails sharing visibly instead of storing a preview tied to
ephemeral release files.

### Where a shared preview link opens

`Brando.LivePreview.share/5` records the site and environment the preview is
shared from in `sites_previews.site_id` and `environment_id`; without tenancy
both stay empty. The link is built with the endpoint's URL, so it is on the
admin's host, and it works before the site has a domain.

In `:multi`, a preview opens only under its own site:

- On a host that resolves to no site, such as the admin's,
  `Brando.Plug.Tenant` lets `/__p__/:preview_key` through, and no other path.
  It looks the key up, one query on that path only, and for an unexpired
  preview of an active site sets the request's tenant context to the site and
  environment the preview was shared from. An unknown or expired key answers
  404, as every other path on that host does.
- On a site's own hosts, the link opens that site's previews only. Another
  site's preview answers 404, with the site's 404 page.
- A suspended or archived site's preview opens on no host, and its own
  hosts open no preview at all.
- A preview whose environment is deleted before it expires opens under the
  site's live environment.
- A preview shared before previews recorded their site has the site of its
  pinned asset set (the upgrade migration fills it in) and opens under that
  site's live environment. A preview with neither opens on any site's host,
  and not on a host with no site.

With one site, or without tenancy, the link opens on any host the application
answers.

### Where a preview's assets are served from

A live preview (`/__livepreview`) is served on the admin's host, and a shared
preview link is built with the endpoint's URL, on the same host. Both pages
name the site's assets host-relative (`/assets/…`), as the site's own pages
do, so the admin's host answers them:

- On a host that resolves to a site, `Brando.Plug.SiteAssets` serves the set
  its environment uses and the site's pinned sets, as described above. A
  path those miss answers from the own set of another environment of the
  same site, with `cache-control: no-cache`, so a preview of Staging shown on
  a host that resolves to Production (the admin's host in `:single`, the
  site's own host in `:multi`) loads Staging's files, those outside its
  manifest included. Production's own file wins over Staging's; when two
  other environments hold a path with different content, it stays
  unanswered; a path the release holds is left to it. Another site's sets
  never answer there. That listing is cached with the others below, and
  dropped also when an environment's own set is set or cleared, or the
  environment is deleted.
- In `:multi`, on a host that resolves to no site, such as the admin's, it
  answers a path with the file a site's own host would send: any file of the
  site's active set, scripts and styles as well as the fonts and images of
  the build's `public/` directory, else a file that a set pinned by an
  unexpired shared preview lists in its Vite manifest. The active set wins
  over a pinned one. A site with no domain yet previews the same way. An
  environment with a set of its own answers any file of that set beside its
  site.
- When several sites hold a path, it answers only if they all hold the same
  content. An environment's own set counts as a holder of its own beside its
  site's active set, so a path two environments of one site hold with
  different content stays unanswered too. When their contents differ (`favicon.ico`, a font or logo with
  the same name in two sites' builds, a build with unhashed names), the path
  stays unanswered on that host: the request does not say which site's
  preview asked, and one site's file is never sent to another's preview.
  Give such files hashed or site-specific names to have them in previews.
- The release's `priv/static` wins: a path it holds is left to the release's
  `Plug.Static`.
- Its answers there carry `cache-control: no-cache`, since which file a path
  gets can change when another site's set does. On a site's own host the
  files stay cacheable for a year.
- Sets of a suspended or archived site do not answer there, and do not
  count when contents are compared, as the admin lets no one preview such a
  site. The site's status is read on each request.

A miss is rejected from a cached listing of every set's files, without
touching the filesystem; the contents of a path several sites hold are
compared when the listing is built. The listing is dropped whenever a set is
activated, deactivated, pinned, released or pruned, on every node
([Several nodes](#several-nodes)), and is built again on the next request.

### Pruning contract

`Brando.Assets.SiteAssets.Retention` owns the deletion decision. A set is
protected while it is active, while an environment uses it as its own set,
while an unexpired preview references it
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
admin assets screen marks sets that are in use by environments, previews or
builds.

## Build and publish static sites

<!-- usage-rules:start topic="tenancy" -->

A static build requests and stores the paths your application's web SSG
module lists. `mix brando.gen.ssg` writes one that lists each site's published
pages:

```elixir
defmodule MyAppWeb.SSG do
  import Brando.SSG

  alias Brando.Pages
  alias Brando.Pages.Page

  # Published pages with a URL, in the site's languages
  urls :pages do
    {:ok, pages} =
      Pages.list_pages(%{
        filter: Page.__url_filter__(),
        status: :published,
        select: {:struct, [:uri, :language, :has_url]}
      })

    pages
    |> Brando.Sitemap.in_site_languages()
    |> Enum.map(&Page.__absolute_url__/1)
  end
end
```

Add a `urls` block for each other content type with pages, listing its
published entries' `__absolute_url__/1` the same way.

<!-- usage-rules:end -->

URL callbacks execute under the selected environment's tenant prefix. The
renderer requests each path from the application's own endpoint, over `http`
on the port its HTTP listener is bound to, read when the build starts. It
connects to the loopback address of the listener's family when the listener
is bound to a wildcard (`127.0.0.1` for `{0, 0, 0, 0}`, `::1` for an IPv6
wildcard such as phx.new's `ip: {0, 0, 0, 0, 0, 0, 0, 0}`), and to the address
otherwise. Every request says `Host: localhost:<port>`, and
`x-forwarded-proto: https` when the endpoint's URL is `https`. It also sends a
short-lived signed context header: the tenant plug takes the site and
environment from that header, not from the host, so a working environment can
be built without assigning it a temporary domain. A build therefore needs the
endpoint running as a server with an `:http` listener, as a release behind a
proxy does on whatever port it listens: without one, the build fails before it
requests anything, and its log says so. A background build runs on whichever
node takes its job, so every node that runs jobs must serve the endpoint.
`Brando.SSG.build/3` takes `:base_url` to request another origin instead, as
it is.

An endpoint with `force_ssl` lets the build's requests through as phx.new
writes it (`rewrite_on: [:x_forwarded_proto]`, with `localhost` among the
excluded hosts), and as `Plug.SSL` does by default, which excludes
`localhost` in every version. An application with its own `:exclude` list
needs `localhost` in it, or `rewrite_on: [:x_forwarded_proto]` and an `https`
endpoint URL. Otherwise `Plug.SSL` redirects every page to `https`, and each
URL fails naming `force_ssl` as the likely cause: a redirect to the same path
on `https`, under `localhost` or the endpoint's host, on a build that requests
the listener.

The pages' absolute URLs name the built environment's domain, or the live
environment's when it has none, never the origin the build requested
([A site's absolute URLs](#a-sites-absolute-urls)).

Responses outside the 200 range are retained in the build's failed-URL list and
make the build fail without hiding partial logs or counts.

A build requests only its own origin: the listener's, or
`http://localhost:<port>`, which it requests on the listener's address. When
the build sends `x-forwarded-proto: https`, `https://localhost:<port>` is its
origin too, as `Plug.Conn.request_url/1` writes it after `rewrite_on`, and it
is requested the same way, over `http`. A
listed path that redirects to another path on that origin is stored with the answer the redirect ends at, and the
signed header goes along; the build's redirect list names it too (below). A redirect to another scheme, host or port, or to a
URL carrying credentials, fails that URL: Brando makes no request there, and the
failed-URL list names the target's origin. That includes an absolute URL to the
site's public domain, since the build renders through the endpoint's listener, so
write a redirect on a listed path as a relative path, or take the path off the
SSG module's list. A custom `:fetcher` gets `redirect: false` and returns a
redirect with its `:headers`.

Open `/admin/config/publishing` while a static site is selected. Who may do
what there, with capabilities on: **Build**, **Schedule** and **Deploy** on
Builds & deployments make builds, schedule them, and deploy and roll them back;
**Configure** saves the deployment settings below, makes and rotates the SSH
key, accepts host keys and reviews the target's files (see
[Groups and authorization](authorization.md#scopes-and-defaults)). Without
Configure the screen shows the builds, the strategy and whether builds deploy
automatically, but not the target, its URLs or a build's log; a deploy that
waits for a key, a host key or a review says that someone who may configure
publishing has to set it up. Without capabilities, whoever manages the site
(an admin, a site's manager with several sites, a superuser) does all of it.

The deployment form supports:

- **Served by this installation** (`local`), with no target: the live
  environment's domain answers from the published build
  ([Served by this installation](#served-by-this-installation));
- `rsync`, with a target such as `deploy@example.com:/srv/www` and its SSH
  port (22 by default; see
  [SSH for rsync targets](#ssh-for-rsync-targets));
- `s3`, with `s3://bucket/prefix` or, for a bucket of its own, `s3://bucket`;
- an optional public CDN URL;
- an optional completion webhook, posted after each deploy or rollback. Like
  a [webhook](webhooks.md), it must be `https` to a host with only public
  addresses; Brando checks it when it is set or changed, and again before each
  post, and does not follow redirects. The build log says when the post failed, not the
  answer;
- automatic deployment after successful builds, offered once the site has a
  strategy and a target (a build never deploys without one); and
- artifact retention from 1 through 100 builds (10 by default).

An rsync target is a remote destination, `[user@]host:/absolute/path`. The
deploy mirrors the build there with `--delete`, over SSH with the site's own
key, deleting only what Brando uploaded or an admin confirmed (see
[What an rsync deploy deletes](#what-an-rsync-deploy-deletes)), so it must be
another server: local paths, `localhost` and
loopback names and addresses (however written), hosts that resolve to one of
this server's addresses, paths with `.`, `..` or empty segments,
`host::module` and `rsync://` targets, and users or hosts beginning with `-`
are refused, both when the settings are saved and when a build deploys. A
name can still reach this server in ways a check cannot see (DNS that
changes after the check, a public address behind NAT),
so to limit the destinations anyone who may deploy can choose, list them in
config (below).

The host is looked up when a save sets the strategy or the target, not
while the form is filled in, nor for a save that changes only other
settings. Its IPv4 and IPv6 addresses are taken from the hosts file
(`/etc/hosts`), and for a family the hosts file does not list, asked of the
name servers in the system's resolver configuration through Erlang's
`:inet_res`, with one limit of 3 seconds for both families together
(`config :brando, Brando.Sites.DeployConfig, lookup_timeout:` in
milliseconds). A name the name servers say does not exist, or that has no
address records, passes, and so does a name only the operating system's
own resolver knows (mDNS, per-domain resolvers): a deploy to a name nothing
knows fails to connect. A name server that fails or refuses the query, a query that
times out, no name server to ask, or a lookup the limit cuts short refuses
the save: the target says its host could not be looked up, and to try
again. The answer is kept on that node for a minute, so saving again does
not ask again; a failed lookup is not kept. Each deploy looks the host up
again; when that lookup fails, the deploy fails and says so in the build's
log, and a deploy or rollback started from the publishing screen is tried
again.

An S3 deploy deletes every key under its target before it uploads the build,
with the application's one set of ExAws credentials. Its prefix may not hold
`.`, `..` or empty segments, or `?`, `#`, `%`, `{`, `}`, `\` or spaces, and
its bucket no user or port; `s3://bucket` with no prefix is the whole bucket.

Where each site may deploy is listed in one of two places no site
administrator can change: in config, or on the site itself, where a
superuser sets it under **Sites** (see
[A site's allowed deploy targets](#a-site-s-allowed-deploy-targets)). A target
passes when either allows it.

In config, the placeholder `{site_key}` stands for the key of the site being
saved or deployed, so an entry binds a destination to that site:

```elixir
config :brando, Brando.Sites.DeployConfig,
  rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}"],
  s3_targets: ["s3://static-bucket/sites/{site_key}"]
```

A target must be an entry, or lie under one that ends in `/` (not the entry
itself, which holds the others), in config or in the site's own list. A bucket with no prefix passes only an entry
that names it exactly, such as `s3://{site_key}-static`; `s3://bucket/` allows
every prefix in the bucket but not the bucket itself. Brando checks a target
when the settings are saved and again each time a build deploys, since a build
keeps the configuration it was made with. A refused deploy or rollback says so
in the build's log, and a refused target on the Publishing screen says a
superuser sets the site's allowed targets under Sites. If the target is of the
right form, fix the list and the build deploys; change a site's target and it takes a new build. An older build
whose target no longer fits cannot be rolled back until its target is listed
again, and one with a target of the wrong form cannot be deployed at all.
A build made for another delivery than the site uses now is refused too, in
both directions: one made for a static host on a site the installation serves
itself, and one made to be served by the installation on a site that is not.
Its log says it must be built again.

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
a list entry has no `{site_key}`, or two sites' entries reach the same
destination: entries of config's map, a list entry with `{site_key}` as it
reads for each site, and the sites' own allowed targets, such as one site's
own `deploy@static.example.com:/srv/sites/` holding the directory
`deploy@static.example.com:/srv/sites/{site_key}` gives another. Two sites'
destinations from one list entry that differ only in the `rsync` user, as
`{site_key}@static.example.com:/www` gives them, are not reported as pairs:
the line names the entry once, saying it gives every site the same path under
its own account. Each site deploys with `--delete` into that one directory,
so the entry is safe only when each account is confined to its own directory
(a chroot); otherwise put `{site_key}` in the path as well. The same place
reached from two different entries warns as an overlap, whatever the users.
The warning says where each entry is set, from the terminal and to a
superuser; on Utilities, anyone else sees how many entries every site may
use, how many are told apart only by account and how many pairs overlap, not
which, as the entries are other sites' destinations too. It also warns
when a setting has an entry, key or value of a form no
target can pass (see
[System check](doctor.md)).

**Entries that extend each other collide on hyphenated keys.** With
`s3://b/{site_key}` and `s3://b/{site_key}-staging`, site `a` may name
`s3://b/a-staging`, which site `a-staging` owns through the first entry, so use
one entry per site layout, or separate them with a character keys cannot hold,
such as the `/` in `s3://b/{site_key}/www` and `s3://b/{site_key}/staging`.

With `tenancy_mode: :multi` a target of `rsync` or `s3` needs config's list or
map, or the site's own allowed targets, to allow it: until one does, no target
of that strategy can be saved or deployed. With one
site, an unset list allows any target of the right form, including a whole
bucket; a list set there applies the same way. Serving a build from the
installation writes nowhere outside the site's own directory, so it needs no
list and is allowed for every site; an operator turns it off for all of them
with `config :brando, Brando.Sites.DeployConfig, local_delivery: false`, which
refuses it when the settings are saved and when a build deploys.

Generated output is persistent at
`sites/{site_key}/ssg/builds/{version}`. Old ready, archived, and failed artifact
directories are pruned after the retention window, while their database history
and logs remain; the build the installation serves for a site is never pruned.
A build finished while a deploy or rollback of the site is running prunes
nothing and says so in its log; the next build prunes. Preview tokens expire after seven days and stop working as soon
as their artifact is pruned. A preview opens only on a host that resolves to
the build's own site (another site's host, or with several sites one of the
installation's own hosts such as the admin's, answers `404`). With several sites
the Publishing screen links it on the site's preview host when the installation
sets a preview host pattern ([Preview hosts](#preview-hosts)), and otherwise on
the build environment's domain, or the live environment's, so that domain must
reach the application, not only the static host. With no such host it says
that the site has no host for previews, in the place of the link. A preview shows the build as it was
built: its pages' root-relative URLs, and absolute ones on the site's own
hosts, load the build's assets and media and link to its pages under the
preview's path, and a path the build has no file for answers its `404.html`.
URLs a script builds as it runs are not rewritten. Previews are served with a Content-Security-Policy that keeps forms from
posting and the page from being framed elsewhere. The Publishing screen links
to each build's preview every time it opens, so a build keeps its token itself,
where a shared entry preview keeps only its key's hash: anyone who can read the
database can open a build's preview until it expires.

### Preview hosts

A build's preview runs the build's scripts with the page's origin, so it opens
only on a host of the build's own site. A site deployed with `rsync` or `s3`
points its public domain at the static host, not at the installation, so
without more it has no host for previews. One pattern gives every static site
a preview host of its own:

```elixir
config :brando, Brando.SSG, preview_host: "{site_key}.preview.example.com"
```

The pattern is a string that names `{site_key}` once, as the whole first
label, followed by a host name of at least two labels. A value that is no
string, or a string of any other form, is refused at boot, and so is a pattern
one of the installation's own hosts matches (the admin at
`admin.example.com` under `{site_key}.example.com`); the System check reports
each. It applies with `tenancy_mode: :multi`; with `:single` or `:none` a
preview link is a path on any host, and the setting has no effect.

Each active static site, whatever its deploy strategy, then has the preview
host `<site key>.preview.example.com`, and the Publishing screen links every
build's preview there, for every environment of the site, also when an
environment has a domain of its own: Brando cannot tell whether that domain
reaches the installation, and the public domain of a site deployed elsewhere
would take the token in the link to the static host. Nothing is uploaded: the
host answers from the build the installation keeps.

A preview host answers a build preview of its own site
(`/__ssg_preview__/<token>/…`) and none of the installation's pages: every
other path that reaches the router, the site's pages, shared previews
(`/__p__/…`), the lockdown page, the admin and its sockets included, answers
`404` there. The installation's public files (compiled assets, media) answer
as on any host. Every response carries `X-Robots-Tag: noindex`. The token in
the link is the access, so a locked site's previews open there. A
build whose environment has been deleted, a suspended or archived site, and a
site switched to dynamic delivery have no preview there, and the Publishing
screen links none.

An environment domain or redirect host that matches the pattern is refused
when it is saved. One saved before the pattern was set keeps answering as it
did, also when other hosts are added to its redirect list or removed from it,
and the site whose key it carries has no preview host while it is bound; the
System check names both sites. A site key longer than 63 bytes, or a host
longer than 253, gets no preview host either.

Setup, once: a wildcard DNS record for the pattern (`*.preview.example.com`)
pointing at the installation. With the [served hosts file](#hosts-and-the-reverse-proxy)
each site's preview host is admitted and written as a bound host is, so the
proxy gets an ordinary certificate for it over HTTP-01. Choose a pattern no
session cookie's `Domain` covers: a cookie set for `.example.com` is sent to
`acme.preview.example.com`, where a build's scripts run.

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

The task starts the endpoint on the port the project configures for it, without
its watchers, and builds from that listener. With several sites it writes to
the site's own `sites/<key>/ssg/manual` unless given `--output`; the Publishing
screen's builds go to `sites/<key>/ssg/builds/`, which the task leaves alone.
Otherwise it writes to `./ssg`, or to the SSG module's `render_path`.

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

### SSH for rsync targets

Each site deploys with its own SSH key, to a host whose key an admin accepted
for it on the Publishing screen. The server user's SSH config, keys, agent and
known hosts play no part, so the target names the real host, and a port other
than 22 goes in the **SSH port** field beside it: an alias from
`~/.ssh/config` does not resolve.

When rsync settings are first saved, Brando makes the site an ed25519 key
pair. **SSH access** on the Publishing screen shows its public key, one line
with the comment `brando-<site key>`, with a copy button: add it to
`~/.ssh/authorized_keys` of the target's user on the host. A site saved with
rsync before it had a key shows **Make key** instead, which keeps a key made
meanwhile from another screen. **Rotate key**, after a confirmation, replaces
the key, and deploys use the new one at once. The old public key stays
authorized on the host until someone removes it from `authorized_keys` there.
With capabilities on, SSH access takes Configure on publishing, as saving the
deployment settings does.

**Test connection** checks the target as a deploy does, then fetches the host's
keys with `ssh-keyscan` on the target's port and shows their SHA256
fingerprints. Compare them with the host's own (`ssh-keygen -lf` on its host
key files, or what the hosting provider lists) and press **Accept host key**:
the keys shown are stored, replacing any accepted before for that host and
port, unless other keys were accepted after the test, which then asks for a
new one. A host that answers with some of the accepted keys and no other is
accepted (`ssh-keyscan` may lose one of its connections). When the host
offers a key that is not among those accepted, the test shows both, and
accepting the new ones is for a host you know was rebuilt or replaced; it
waits for a running deploy, and asks to try again when that takes more than a
few seconds. A test's answer is not shown when the settings were saved or the key rotated
while it ran. With accepted keys, the test runs `rsync -an` from an empty
directory to the target, which sends and deletes nothing, and says whether
ssh, the key and rsync on the host work, or what the host answered; for a
target not reviewed yet, it then lists what the target holds (see
[What an rsync deploy deletes](#what-an-rsync-deploy-deletes)). The test
runs beside the screen, with a time limit on each step. `ssh-keyscan` opens
one connection for each type of host key without logging in, which OpenSSH
9.8 and later counts against the source (`PerSourcePenalties`): pressed many
times in a row, the test can be turned away by the host for a while.

Every rsync to the target runs with these ssh options and a five-minute limit
on silence (`--timeout=300`):

```text
ssh -i <site>/ssg/deploy/id_ed25519 -p <port> -F none -o IdentitiesOnly=yes
    -o IdentityAgent=none -o BatchMode=yes -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile=<site>/ssg/deploy/known_hosts
    -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10
```

A build keeps the port it was made with, as it keeps its target: change the
port and it takes a new build. The key and the accepted host keys are read
when the deploy runs. A deploy for a site with no key, to a host and port with
no accepted key, or to a host whose key is not the accepted one, is refused:
the build's log names the step on the Publishing screen (for a build made for
another target or port than the site's settings, a new build), the deploy is not
tried again, and after an automatic deploy the build stays ready.

The key and the accepted host keys are files in the site's
`sites/{site_key}/ssg/deploy/` (`id_ed25519` and `known_hosts`), beside its
builds and deleted with the site. The directory is readable by the server's
user alone, and only the private key is kept: the public key shown is derived
from it. No key is made, and **SSH access** says why, when that directory is
inside the media directory or the endpoint's `priv/static` (links followed),
which the installation serves, or when its path holds characters other than
letters, digits and `. _ + @ - /`, which ssh or rsync read specially: set
`:sites_path` outside them.

The server needs `rsync`, `ssh` and `ssh-keyscan` (OpenSSH); a missing one is
named in the test's result and the build's log. Brando reads and writes the
keys with Erlang's `:ssh` application, which a release includes; an Erlang
installed from a distribution's split packages needs its `ssh` package
(`erlang-ssh` on Debian and Ubuntu) where the release is built.

Making, rotating, testing and accepting are for those who may save the deploy
settings (Configure); rotating and accepting ask for the password, a code or a passkey
when the session has not confirmed lately.

### What an rsync deploy deletes

A deploy deletes a path on the target only when Brando uploaded it or an admin
confirmed it, and never a path on the site's keep list. The receiving rsync
enforces this: the deploy hands it filter rules that let it delete exactly
those paths and protect every other one, so a file the host puts there at any
moment, also while the deploy runs, stays. A shared host's document root
keeps what the host put there: certificate validation files under
`.well-known/`, `cgi-bin/`, a `.htaccess`.

The **keep list**, under **Files on the target** on the Publishing screen,
holds paths relative to the target, a directory's ending in `/`:
`.well-known/` and `cgi-bin/` unless changed, at most 100, of letters, digits,
`. _ ~ + @ , -` and spaces inside a name, with no `.` or `..` segment. A kept
path is never deleted, whatever else says it may be, and an entry keeps its
path and everything under it, with or without the `/`; a file of the same name
in the build is still uploaded. The list stays when the target changes.

**Before the first deploy to a target**, review it. Once **Test connection**
connects, it lists everything the target holds (a dry run with `--delete`
from an empty directory, which deletes nothing) and fetches a `.htaccess` at
its root to show (up to 256 KB). The screen shows the top-level entries with
the number of files in each, those the keep list covers and a `.htaccess`
ticked: tick what else to keep, add deeper paths to the keep list, and press
**Confirm**. Ticked
entries go on the keep list (a ticked name with characters the list does not
take is not confirmed, so it stays, but it shows again among the unknown
files); the first deploy deletes the rest.
Confirm names the listing the screen showed, with the keep list that marked
it: when another admin's test has listed the target again since, or the keep
list changed, it is refused and the screen shows the current listing. A
listing that failed, or found more than 100,000 paths, cannot be confirmed.

A deploy to a target that is not the reviewed one is refused, the automatic
deploy after a build too, with a build-log line that names the review and the
build left ready. A review is for one target, port and set of accepted host
keys: changing the target or port, or accepting other host keys (a rebuilt or
replaced server), makes the target unreviewed, and a build made for an
earlier target or port must be built again.

Each deploy, holding the site's deploy lock:

1. lists the target, and refuses a path where the build has a directory and
   the target a file Brando may not delete, or the build a file and the target
   a directory holding one: rsync would clear the way for the directory
   whatever the rules say, and fails on the file. The build log names the
   path;
2. adds the build's paths to those Brando may have uploaded, so a run that
   fails halfway leaves nothing Brando put there unknown (when the list cannot
   be written, nothing is copied);
3. runs rsync with the rules; once it succeeds, the build's paths are what
   Brando uploaded and the confirmed paths are spent;
4. lists what the target holds beyond the build and the keep list, the files
   Brando did not put there, for the screen. The build log says how many; a
   failure here does not fail the deploy.

**Unknown files** show under **Files on the target**, top-level entries with
their counts. Deploys leave them. **Keep ticked** puts the ticked ones on the
keep list. **Delete the rest** confirms the others, as Confirm does for the
listing it names, and queues a deploy of whichever build is deployed when the
job runs: a newer deploy in between stays live, and deletes them itself. A
rollback goes through the same steps.

The target's state (which target, port and host keys it is for, the paths
Brando uploaded and those confirmed, and the last listing) is the file
`sites/{site_key}/ssg/deploy/target_state`, written whole. Names on the target
come from the host and are shown escaped and cut; a name rsync prints in a way
that cannot be read back is shown, but never confirmed. Reviewing, keeping,
deleting and the keep list are for those who may save the deploy settings
(Configure); **Delete the rest** deploys, so it also takes Deploy, and is
refused before it confirms anything without it. A deploy keeps the list of
what it uploaded itself, whoever runs it. Confirming, deleting and taking a path off the keep list ask for a recent
confirmation. A file the host puts at a path where the build has a directory
in the moment between the listing and the run is the one thing a deploy can
still replace. A target that holds more than 100,000 paths cannot be deployed
to: each deploy lists the whole target first, and refuses with a build-log line
that says how many paths it found.

### Apache and LiteSpeed targets

Apache and LiteSpeed serve files and nothing else: without help, the build's
redirects answer 404, a missing path gets the server's own 404 page instead of
the build's `404.html`, and `_redirects.json` is served to anyone who asks.
Tick **The host is Apache or LiteSpeed** beside the rsync target, and save:
each deploy then writes what the installation would answer for the build into
Brando's block in the `.htaccess` at the target's root, and leaves
`_redirects.json` out. The option is read from the site when the deploy runs,
so the same build deploys with it or without it, and the build itself is not
changed.

The file is the host's, the block is Brando's. As the last step before the
real run, the deploy fetches the target's `.htaccess` (none is fine, up to
256 KB) and replaces what is between `# BEGIN Brando` and `# END Brando`, or
adds the block after the host's lines when there is none. Every other line
is written back byte for byte, and the file keeps its mode (0644 when it is
new). The deploy stops, with nothing copied, when the fetch fails for
another reason than there being no file, when the file is larger than 256 KB,
a link or a directory, when the file with Brando's block would be larger than
256 KB (a later deploy could not fetch it again; the block takes about 90
bytes a redirect, so that is some 2,800 redirects with no host lines), or when a `# BEGIN Brando`
line has no `# END Brando` after it. A build with a `.htaccess` of its own has the merged file uploaded
instead, or nothing when the target's file is the merge already, and its log
says so. The merged file is never among the files
Brando uploaded, so no deploy deletes it, and it is not listed among the
unknown files. A `_redirects.json` an earlier deploy uploaded is deleted.

The block holds:

- `ErrorDocument 404 /404.html`, when the build has a 404 page;
- the redirect list as rewrite rules, in its order: `:name` segments, rules
  that are not exact, a page of the build winning over such a rule, 410 for
  a gone path, each rule only for paths in its language, and the request's
  query dropped unless the target has its own, as the installation answers
  them. A redirect that cannot be written safely is left out, with a line in
  the build's log: a relative target, a target or pattern with characters
  `.htaccess` cannot hold, a pattern Apache's regular expressions would read
  otherwise;
- `Cache-Control: no-cache` for every answer, and a year's immutable caching
  for the files the build's Vite manifest lists.

The rules are inside `<IfModule mod_rewrite.c>` and the headers inside
`<IfModule mod_headers.c>`, so a host without one of the modules serves the
site without that part instead of answering 500.

Turn the option off, and the next deploy removes the block and leaves the
host's lines (the target's state remembers that a block was written, or that
the review found one); a file left with nothing else in it is deleted, or
left empty when the keep list holds `.htaccess`. A build with a `.htaccess` of its own then replaces the
host's file, as any other file of the build.

Where the host answers differently from the installation:

- a host that forbids these directives in `.htaccess` (`AllowOverride`)
  answers 500 for every path: open the site after the first deploy with the
  option on;
- a rewrite in the host's own lines that answers every request, such as a
  CMS's front controller, answers before Brando's redirects;
- an edit the host makes to `.htaccess` in the seconds between the fetch and
  the upload is lost;
- the block takes the target directory to be the document root: the 404
  page is `/404.html`, and the check that a page of the build wins over a
  rule looks under the document root;
- the check that a page wins over a rule that is not exact asks whether the
  file exists on the host, so a file only the host has, such as a kept
  `legacy/index.html`, wins too where the installation would redirect;
- an encoded slash (`%2F`) in a path is a 404 before any rule runs, and a
  directory's path without its trailing slash is first redirected to the
  path with one;
- immutable caching matches by file name, so a file of the same name in
  another directory gets it too, and `?vsn=` in a request does not make a
  file immutable.

The block was checked against Apache 2.4; LiteSpeed reads the same
directives, but was not checked.

### A site's allowed deploy targets

A superuser sets, under **Allowed deploy targets** in the Delivery section of
a site's form under **Sites**, the `rsync` and `s3` targets that site may use
besides those config lists; with `tenancy_mode: :multi` and nothing in
config, they are enough on their own. The lists show for a static site, and
for a dynamic one while it still has entries, and only to a superuser: in
groups mode, a user who may read Sites without being a superuser sees the
Delivery section without them. Beside each list are the
entries config already allows the site, as they read for it, and when the
target the site has saved is allowed by neither, the section says its next
deploy will be refused.

The form saves both lists at once, from the lists it was drawn from: when
they were changed elsewhere since, by another superuser or in another tab, the
save is refused, the form shows the lists as they are saved now, and a note
beside them repeats what was typed, to make the change again on them.
They are stored on the site, and only a superuser, or trusted code acting as
`:system`, can change them (`Brando.Tenant.Registry.update_site_deploy_targets/4`).
The Publishing screen, and anything else a site administrator can reach,
cannot.

Each entry is an exact destination or a parent ending in `/`, held to the
rules a target is held to: a remote `[user@]host:/absolute/path` on another
server for `rsync`, `s3://bucket/optional-prefix` for `s3`, with no `.` or `..`
segment. An entry grants only its own site, so it names no `{site_key}`; one
that does is refused when it is saved. As with config, a parent grants the
site everything under it, other sites' directories included.

A site's entries are read afresh at each save of its deploy settings, and at
each deploy and rollback: remove an entry, and a build made for that target
can no longer be deployed or rolled back to, as when a config entry is
removed.

### What a build holds

A build holds what a static host needs to serve the site on its own, each file
as the application answered it, byte for byte:

- `index.html` and `<path>/index.html`: the listed pages; a listed path with
  an extension (`feed.xml`) keeps its name.
- `<path>.md` and `index.md`: the Markdown alternate each page names with
  `<link rel="alternate" type="text/markdown">` on the site's own host. A page
  names it whenever its entry has a Markdown version, whether or not the
  application serves Markdown there (`Brando.Plug.Markdown`), so an alternate
  the application answers with 404 is left out and the build's log says so.
- `404.html`: the site's error page, as the application answers a path no page
  has (`Brando.SSG.not_found_path/0`; no redirect rule answers it on a build's
  request, and the 404 log leaves a build's requests out). A site whose
  catch-all answers that path with a page has no `404.html`, and the build's
  log says the site answers a missing path with 200. Any other status but 404
  there fails the build.
- `robots.txt`: what the application answers for the site on its public host
  (`Brando.Utils.public_hostname/0`), naming the build's sitemap when it has one.
- `sitemaps/sitemap.xml.gz` and the files it lists: the sitemap of the
  environment built, not the live one's, with its entries on the site's public
  base URL, at the paths `robots.txt` names. A build without one (the
  application has no sitemap module, or it produced no entries) says so in
  its log.
- `_redirects.json`: the site's redirects (below).
- `assets/` and `media/`: the build's asset set and the site's media.

The build requests every one of these from the application the way it
requests the pages, with the same signed header, which it sends in every
tenancy mode. A file the application cannot answer is a failed URL under its
path. A build fails before it requests
anything when the application writes HEEx debug comments or `data-phx-loc`
attributes into its pages (`debug_heex_annotations` or `debug_attributes` in
`config :phoenix_live_view`, which development configs turn on): turn them off
where the build runs.

`_redirects.json` lists what the application answers with a redirect:

```json
{
  "version": 1,
  "languages": ["en", "no"],
  "default_language": "en",
  "redirects": [
    {"kind": "listed", "source": "/old", "target": "/about", "status": 301, "exact": true,
     "pattern": "/old$", "language": null},
    {"kind": "rule", "source": "/news/:slug", "target": "/articles/:slug", "status": 302, "exact": false,
     "pattern": "/news/:slug", "language": "en"},
    {"kind": "rule", "source": "/gone", "target": null, "status": 410, "exact": true,
     "pattern": "/gone$", "language": "en"}
  ]
}
```

For whoever serves the file:

- The entries are in the order Brando checks them, and the first entry that
  matches a path wins.
- `kind` `"listed"`: a listed path that answered a redirect, to a page the
  build has (`language` null). The build keeps that page under the listed
  path as well, for a host that serves files before it checks redirects. A
  listed path whose redirect ends anywhere else keeps only the stored page.
- `kind` `"rule"`: the redirect rules from Configuration → SEO, language by
  language, which Brando checks for a path no page answers in that language.
- Rules are matched against the decoded request path, which carries the
  language prefix when the site forces one: `/en/old` is English, `/old` the
  default language's. `languages` and `default_language` are the site's when
  the build was made: a path is in the language its first segment names when
  that is one of `languages`, else in `default_language`. A list from a build
  made before they were added has neither; read the site's languages then.
- A page the build has wins over a rule that is not exact, as in the
  application; an exact rule for such a page is left out, since Brando never
  answers it.
- `source` is a path a host can match: `:name` segments match one segment and
  stand for it in `target`, and `exact: false` matches every longer path that
  begins with `source` as well. A `.` in a rule with no other
  regular-expression character stands for itself. A rule written as a regular
  expression, or one whose segment begins with an escaped `:` (a redirect made
  from a logged 404 for `/:id`), has `source` null and only `pattern`, Brando's
  own rule, which a host without regular expressions cannot follow.
- Status 410 has a null target, and the build has no page of its own for it.
- `$timestamp` in a rule's target is replaced with the build's time.
- A redirect whose target differs from its source only by the query
  (`/about` to `/about?lang=en`) is left out, since a host matching on the
  path would answer it in a loop; the build's log names it.
Brando follows these facts itself when it serves the build
([Served by this installation](#served-by-this-installation)), and writes them
into `.htaccess` for an Apache or LiteSpeed host
([Apache and LiteSpeed targets](#apache-and-litespeed-targets)). Feed the list
to any other host as its redirect rules. For a host that reads
Netlify's `_redirects` format, write one line per entry with a `source`, as
`source target status`; an entry that is not exact also gets a line for
`source/*`, and on a host that serves a file before its rules, an entry from a
listed path gets `!` after its status so it wins over the page the build kept.
On S3 behind CloudFront, a viewer-request function that reads the list does
the same. An entry without a `source` needs a server that runs regular
expressions, such as the application itself.

### Served by this installation

With the strategy **Served by this installation** (`:local`), a deploy copies
nothing: it records the build as the site's published build
(`sites.published_build`), in the transaction that marks it deployed, and a
rollback records an older one. Every node's registry cache hears of it once it
commits ([Several nodes](#several-nodes)), so the site's host answers from that
build on the next request, without a restart. Until the first deploy, the host
answers from Phoenix as before.

`Brando.Plug.SiteAssets` answers first (`Brando.SSG.LocalDelivery`), in the
endpoint before the router, for a request that `Brando.Plug.Tenant` would
resolve to the live environment of an active `:static` site with this strategy
and a published build: with `:multi`, on that environment's domain; with
`:single`, on every host but another environment's domain, so the endpoint's
own host, a bare IP and a host no environment names answer from the build too,
as they would resolve to the live environment. A redirect host still redirects
to the domain first. There, a `GET` or `HEAD`:

- for a path the build has a file for answers that file: `/about` and
  `/about/` answer `about/index.html`, and `/about.md`, `robots.txt` and the
  sitemap answer the build's own. A page asked for with
  `Accept: text/markdown` answers the build's Markdown file for it
  (`about.md`, `index.md` for the root, `contact.html.md` for
  `/contact.html`), as `Brando.Plug.Markdown` answers for
  the application, when the build has one; both answers then carry
  `Vary: Accept`;
- for a path `_redirects.json` answers, as the facts above say, answers the
  redirect, or `410 Gone` for an entry without a target;
- for a file the build lacks that the endpoint's asset pipeline has, leaves
  it to the pipeline: the asset sets `Brando.Plug.SiteAssets` serves, and the
  release's static files under the web module's `static_paths/0`
  (`Brando.Plug.SiteAssets.static_file?/1`). That covers the admin's bundles
  with `:single`, a preview's newer assets and those of a page Phoenix renders
  there. These are files, not content: a request let through this way that
  no plug before the router answers gets the build's 404 page from
  `Brando.Plug.Tenant`, never a page Phoenix renders. Keep the web module's
  `static_paths/0` the same as the `only:` of the endpoint's `Plug.Static`
  (the System check warns when they differ): a release file under a prefix
  `static_paths/0` leaves out is answered with the build's 404 page;
- for any other path answers the build's `404.html` with status 404, or a
  plain 404 for a build without one. A page the environment has but the
  published build does not is never reached, so unpublished content stays
  unpublished.

Paths resolve inside the build's directory only: a path with `..`, an encoded
slash or a NUL, or a file reached through a symbolic link, is a path the build
does not have. `_redirects.json` itself is not served.

HTML and the other files are sent with an `ETag`, which names the build's
version, and `Cache-Control: no-cache`, so a browser or CDN asks again and gets
`304 Not Modified` while the build is unchanged, and the new file after a
deploy. The files the build's Vite manifest lists, which are named by their
content, and a request with a `vsn` query, as `Plug.Static` reads it, for a
file other than a page (HTML, or a page's Markdown) under `assets/` or a
directory the web module's `static_paths/0` names, are sent with
`Cache-Control: public, max-age=31536000, immutable`. Every other file, such
as `robots.txt`, the sitemaps, feeds and JSON at the build's root, which the
next deploy rewrites under the same URL, is sent with `no-cache` and its
`ETag` whatever the query. Markdown is
`text/markdown`, and the gzipped sitemap is sent as `/sitemaps/` sends it from
Phoenix, a download.

The router's browser pipeline never runs for a file sent from the build, so
pages (HTML, the 404 page included) get the headers
`Phoenix.Controller.put_secure_browser_headers/2` sets by default, among them
a Content-Security-Policy of `base-uri 'self'; frame-ancestors 'self';`. An
application with a policy of its own, such as the one its router sets with
`Brando.Router.put_extra_secure_browser_headers/2`, sets it here, as headers
applied to every page after the defaults:

```elixir
config :brando, Brando.SSG.LocalDelivery,
  headers: %{"content-security-policy" => "default-src 'self'; img-src * data:"}
```

Other files of the build are sent with `Access-Control-Allow-Origin: *`, as
`Brando.Plug.SiteAssets` sends its own, for sandboxed live and shared previews.

A request answered from the build never reaches `Plug.Telemetry` or the
request log. It emits the telemetry event
`[:brando, :ssg, :local_delivery, :stop]` instead, with the measurement
`:duration` (native time units) and the metadata `:site_key`, `:path` and
`:status`, for an application's metrics.

What still reaches Phoenix on that host:

- other methods than `GET` and `HEAD`, such as a contact form's `POST`;
- the paths below the media path, shared previews (`/__p__/`), build previews
  (`/__ssg_preview__/`) and Brando's `/__brando/` paths, live preview
  (`/__livepreview`), and the endpoint's sockets, which answer before any
  plug. The media path itself, `/__p__`, `/__ssg_preview__` and `/__brando`
  answer from the build as any other path: no route answers them;
- `/health`, for `Brando.Plug.Health`, which a blue/green deploy polls from
  the server before it switches; without that plug in the endpoint it is the
  build's `health/index.html` when the build has that page, else its 404
  page. A path in the application's own list below comes first, `/health`
  included;
- with `:single`, where the admin answers on every host, the admin's paths,
  and MCP's when the router mounts them (`Brando.Router.mcp_routes/0`);
- the IndexNow key file (`/<key>.txt`) while IndexNow is on
  (`Brando.Plug.IndexNow`);
- a request carrying a build's signed context (`Brando.SSG.Context`), so a new
  build is rendered by Phoenix, never copied from the published one;
- an application's own paths, listed in config:

```elixir
config :brando, Brando.SSG.LocalDelivery, dynamic_paths: ["/api", "/coming-soon"]
```

On that host every 404 is the build's: a request that reaches Phoenix and that
no route answers, such as `/__brando/x` or a shared preview's unknown key,
falls to the page catch-all, and where Brando answers a page that is missing
(`BrandoWeb.FallbackController`) it answers the build's `404.html`, or a plain
404 for a build without one (`Brando.SSG.LocalDelivery.answer_not_found/1`).
A route that answers is untouched, such as a valid shared preview or the
forms' token. That safety net, and the one for a file let through to the
asset pipeline that no plug before the router answers, is Brando's code in
the router: `Brando.Plug.Tenant` and the fallback controller. A route in a
pipeline without `Brando.Plug.Tenant`, a page controller without
`BrandoWeb.FallbackController`, or a router with no catch-all answers such a
request itself, with the application's own error page. The routers and page
controllers Brando generates are covered.

Environments that are not live answer from Phoenix on their own domains, as
working copies, with `X-Robots-Tag: noindex, nofollow`. Setting another
environment live takes the live domain and its redirect hosts with it, as on a
`:dynamic` site ([Switch live, rollback, and delete](#switch-live-rollback-and-delete)), so the public domain keeps
answering from the published build until the next deploy, which builds from
the environment now live. Switching the site to
`:dynamic`, to another strategy, suspending, archiving or deleting it stops
serving at once; switching back serves nothing until the next deploy. The
strategy needs a site in the registry, so it applies with `:single` and
`:multi`, not `:none`.

Each node reads a published build's file list and redirects once and keeps
them in memory until another build is published. A node that cannot find the
build's directory, or one of its files, answers `503` (a file the asset
pipeline has, such as the admin's bundles, still loads, though the build
listed it too, so the Publishing screen can deploy again), looks for the
directory
again every few seconds and logs it each time it does not find it: with
several nodes, `sites/` must be on storage they all share
([Several nodes](#several-nodes)). The reverse proxy needs nothing new: the
site's domain already reaches the application.

Two limits. A file sent from the build ignores a `Range` header and is sent
whole, so a video to be streamed belongs in media, which the build does not
answer. And
`config :brando, Brando.Sites.DeployConfig, local_delivery: false` refuses
the strategy on save and refuses each deploy, but a site already published
keeps answering from its build until its strategy is changed (a save that
keeps `:local` is refused) or it is suspended, archived or deleted.

### A CDN in front

A CDN in front of the installation caches the build as it would any origin.
Point the site's domain at the CDN and the CDN at the installation, keeping
the `Host` header (or sending the site's domain as the origin's host), since
the domain selects the site. HTML, `robots.txt`, the sitemap and other files
not named by their content carry `Cache-Control: no-cache` and an `ETag`, so
the CDN revalidates them with the installation on each request and a deploy or
rollback shows at once; content-addressed assets are cached for a year. To let
the CDN keep pages longer, purge its cache from the deployment webhook, which
is posted after each deploy and rollback. Let `POST` and the paths that still
reach Phoenix through uncached. Set the CDN's URL as the public CDN URL, so the
Publishing screen's **Open site** links to it.

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
commands that finish the remaining steps. It does the same when the move
itself reports an error and the schema holds rows all the same, as when the
connection is lost while the move commits.

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
9. Verify each domain resolves to the intended environment, each redirect
   host redirects to its domain, and unknown hosts return `404`, and that each
   domain serving LiveView pages or the admin is accepted by the endpoint's
   `check_origin` (with `:single`, `mix brando.install --domain` lists the
   production domain, its `www.` host and the staging host, no other
   subdomain; with `:multi` it writes `Brando.Tenant.Origins`).
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
