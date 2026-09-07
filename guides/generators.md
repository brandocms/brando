# Installation and generators

Install Brando into a standalone Phoenix application through Igniter, review the
source diff, then build assets and initialize the database. Existing Phoenix
routes, templates, tests, configuration, secrets and dependency choices are
preserved. Conflicting generated files stop the plan, including with `--yes`.

The developing branch uses Yalc for BrandoJS. Keep the Elixir and JavaScript
sources on the same revision; npm publication belongs to release preparation.
The working consumer combination is Phoenix/phx_new 1.8.13, LiveView 1.2.11,
Elixir 1.20.3 and OTP 28.4.1. Install Node.js, pnpm, Yalc, PostgreSQL, the matching
Phoenix generator and an Image/Vix-supported build environment first.

The old `install.sh` entry point is retired and prints these instructions without
changing the application. Use the commands below for a reviewed installation.

## Create or select a Phoenix application

```sh
mix phx.new studio --no-install --no-assets --no-dashboard --no-mailer
cd studio
```

Use a Phoenix generator compatible with Brando's dependency constraints. For
example, older generators selecting LiveView `~> 1.1.0` cannot resolve Brando's
current LiveView 1.2 dependency.

Add these dependencies to the consumer's `mix.exs`, using your actual checkout:

```elixir
{:brando, path: "/absolute/path/to/brando"},
{:igniter, "~> 0.8.0", only: [:dev, :test]}
```

Then run:

```sh
mix deps.get
mix brando.install
```

Or use Igniter's package installer with the same development source:

```sh
mix igniter.install brando@path:/absolute/path/to/brando
```

The package installer calls the same `brando.install` task. Preserve your selected
Git/path source while testing unreleased work; a bare `igniter.install brando`
selects the package source according to Igniter's own dependency rules. Brando's
installer does not replace your dependency with a hardcoded relative path.

The generated changes configure Brando, extend supervision/endpoint/router,
create the admin support modules and Vite projects, and add missing migrations.
The current default preserves your public homepage. It does not scaffold a CMS
public site, deployment configuration, or sample content.

## Choose configuration

A new install defaults to `none` without a prompt. Omitted flags on a rerun keep
the existing mode and site key. Other choices are:

```sh
mix brando.install --tenancy-mode single --site-key studio
mix brando.install --tenancy-mode multi
mix brando.install --interactive
```

`--interactive --tenancy-mode single` asks only for the missing site key.
`--yes` accepts the diff; it neither enables guided questions nor permits replacing
conflicting files. `--dry-run` previews source without applying it. Igniter 0.8 auto-accepts when
stdin is redirected; use `--dry-run --yes` for unattended previews (including large diffs).
`--no-tenancy-prompt` remains supported.

Review `config/brando.exs` and your existing Phoenix database/endpoint settings.
The default language is English. Add languages deliberately before initializing
content. Follow [Sites and environments](tenancy_and_environments.md) when using
`single` or `multi`; changing the source setting does not migrate existing data.

The installer discovers custom namespaces and allows `--module`, `--web-module`,
`--admin-module`, `--repo`, `--router` and `--endpoint` selection. Ambiguous modules
and unsupported application layouts produce instructions before files are written.
Umbrella roots are not currently supported.

## Build assets

```sh
mix compile --warnings-as-errors
mix brando.assets.setup
```

Asset setup finds `assets/` inside the selected Brando checkout, publishes it to
a consumer-local Yalc store under `_build`, adds BrandoJS to the admin consumer,
and runs `pnpm install` and `pnpm build` in both consumer asset directories.
It does not build the framework's root asset project. For an Elixir package that
omits the developing JavaScript sources, pass
`--source /path/to/matching/brando/assets`. Use `--no-build` to install only.

Vite writes `admin_manifest.json`, `manifest.json` and assets to the consumer's
`priv/static`. The default uses compiled assets (`config :studio, hmr: false`).
For HMR, explicitly enable it and start the relevant Vite servers: frontend on
3000 and backend on 3333. After framework JS changes, rerun asset setup.

## Initialize and sign in

Review migrations and point the consumer at its intended development database:

```sh
mix ecto.create
mix ecto.migrate
mix brando.gen.languages
mix brando.gen.admin
mix phx.server
```

The language task creates identity/SEO defaults and prints language configuration;
choose English (`en`) for the initial defaults. The admin task prompts for account
details. Open `/admin/login` and sign in. Account creation and database operations
are separate from the Igniter source plan. Existing Phoenix seeds are preserved;
no Brando sample seeds run automatically.

For `single`/`multi`, provision the site/environment after public migrations and
initialize content inside that environment as described in the tenancy guide.
Group authorization remains an explicit setup in [Authorization](authorization.md).

## Generate a content type

```sh
mix brando.gen.blueprint Catalog Product
mix compile --warnings-as-errors
mix brando.gen Studio.Catalog.Product
mix brando.gen.blueprint_migration Studio.Catalog.Product
mix ecto.migrate
```

The Blueprint starts with title/slug fields, a listing, a form, and creator,
status and timestamp traits. Review and adapt it before generating storage.
`--plural people` handles irregular names; `--singular` also overrides query names.
The default plural appends `s`. `--interactive` asks for missing domain/schema or
Blueprint arguments. Without it, missing arguments produce actionable errors.

Accept and compile the Blueprint before generating the resource. The resource
command reads compiled metadata, extends its context using AST edits, and adds
admin list/form modules and routes. Multiple resources can share a context.
Existing custom queries remain in place; conflicting functions and owned files
are reported. Add a navigation entry and review the authorization policy explicitly.

Public rendering requires an explicit route choice:

```sh
mix brando.gen Studio.Catalog.Product --public-route /products
```

This adds a simple controller/HTML pair and browser routes for `/products` and
`/products/:id`. Schemas with a status field expose published records. The default
Blueprint leaves `absolute_url false`; define its URL when public routing is ready.
Generated public controllers resolve tenant context before querying content.
Templates do not assume an image field. `--main-field` selects a display/filter
field; otherwise the generator prefers `title`, a string field, then `id`.

Consumer templates in `priv/templates/brando.gen.blueprint` and
`priv/templates/brando.gen` override package defaults. The Blueprint command also
accepts `--template RELATIVE_PATH`, which takes precedence over the conventional
consumer override. Conflicting output files are preserved for manual integration.

[Blueprint migrations](blueprint_migrations.md) explains snapshot history,
subsequent storage changes, rollback, and explicit rebaseline.

## Framework migrations and upgrades

```sh
mix brando.gen.migrations --dry-run
mix brando.gen.migrations
mix brando.migrate
# For named environments, after public migrations:
mix brando.migrate --tenants
```

The source command adds missing versioned framework migrations, preserves
historical files regardless of their timestamps, and does not recreate the
pre-versioned installation baseline or run the database.

Older installations generated their own `Mix.Tasks.Brando.Upgrade`, which shadows
the library's native upgrade hook. Retire the recognized task in a separate step:

```sh
mix brando.upgrade.prepare
mix compile
```

The plan archives its source under `priv/brando/legacy_tasks` and removes it from
compilation. Customized or unrecognized tasks block removal: rename their module
and task explicitly, preserving your application-specific steps. Compile in a
new invocation before using `mix igniter.upgrade brando`.

Igniter calls the library-owned `brando.upgrade FROM TO` hook. The current recipe
accepts forward changes in the 0.54 development line, from `0.54.0-dev` onward,
and never beyond the loaded dependency version. Equal versions are a no-op;
use `brando.gen.migrations` to reconcile files during development. Applications
with older DSL syntax must first follow [Migrating to 0.54](migrating_to_054.md).
Future release transitions require explicit upgrade recipes and qualification.

## Auxiliary generators

```sh
mix brando.gen.mail
mix brando.gen.sitemap
mix brando.gen.authorization
mix brando.gen.release
mix brando.gen.tenant_migration add_projects
```

All commands use reviewed source plans and consumer namespaces. New dependencies
are fetched once after acceptance. Customized owned files produce conflicts;
consumer templates under `priv/templates/TASK` take precedence. Tenant migration
names use lowercase letters, digits and underscores; `--interactive` guides a
missing name. Existing migration implementations and timestamps are preserved. New Blueprint
storage uses tenant migrations in single/multi mode; run `mix brando.migrate --tenants`
after public migrations. History in a different directory requires an explicit
transition decision.

Mail generation reuses a Phoenix mailer, adds missing Swoosh/Req dependencies,
and supplies local/test adapter defaults plus a default Req API client.
Build notifications with `MyApp.Emails.contact(changeset, from: ..., to: ...)`.
Invalid form data raises before constructing an email. Configure the production
adapter and credentials deliberately; generating mail helpers never sends mail.

The sitemap selects published pages; review their public URL rules before calling
`Brando.Sitemap.generate_sitemap/0`. Authorization generation starts from the
maintained default policy; review permissions for your application content types.

Release generation creates `MyApp.ReleaseTasks` and adds a missing Mix release
definition. It preserves existing release settings, runtime configuration,
secrets, Dockerfiles and deployment files. Build with `MIX_ENV=prod mix release`,
then invoke migrations explicitly as described in [Deployment](deployment.md).
`brando.install.fabfile` is retired and directs callers to release generation and
Florist; it does not modify existing Fabric files.

```sh
mix brando.gen.otel
mix brando.gen.otel --adapter bandit --exporter otlp
```

Telemetry infers a single declared Bandit/PlugCowboy dependency or asks for an
explicit `--adapter`. It uses the discovered service namespace and the Repo's
configured event prefix, preserves existing configuration, and guards against
legacy duplicate instrumentation. [Phoenix instrumentation](https://hexdocs.pm/opentelemetry_phoenix/OpentelemetryPhoenix.html)
already covers LiveView. The [OpenTelemetry SDK](https://hexdocs.pm/opentelemetry/readme.html)
supports the default `traces_exporter: :none`; opt into OTLP and set the standard
`OTEL_EXPORTER_OTLP_ENDPOINT`/`OTEL_EXPORTER_OTLP_HEADERS` environment variables.
Existing exporter choices remain unchanged on reruns.

`brando.setup.tenancy` also accepts `--interactive` for missing mode/site choices.
Without it, pass the options explicitly; `--yes` only accepts the diff.

## Task reference

Run `mix help TASK` for current options. These are separate operations:

| Task | Result |
| --- | --- |
| `brando.install` | Reviewed Brando source installation; also called by `igniter.install` |
| `brando.gen.blueprint` | Reviewed Blueprint source |
| `brando.gen` | Reviewed context/admin source; optional public routes |
| `brando.gen.backend` / `brando.gen.frontend` | Reviewed asset scaffolds with conflict checks |
| `brando.assets.setup` | Operational Yalc installation and consumer builds |
| `brando.gen.blueprint_migration` | Reviewed migration/snapshot pair with stale-plan checks; database application is separate |
| `brando.gen.languages` / `brando.gen.admin` | Operational language/account initialization |
| `brando.setup.tenancy` | Igniter tenancy source preparation |
| `brando.migrate_to_tenant` | Operational data conversion |
| `brando.gen.sitemap` / `brando.gen.mail` / `brando.gen.authorization` | Reviewed auxiliary modules with conflict checks |
| `brando.gen.release` | Reviewed release helpers and missing Mix configuration |
| `brando.install.fabfile` | Retired; use release generation and Florist |
| `brando.gen.otel` | Reviewed application-scoped telemetry setup |
| `brando.gen.migrations` | Reviewed missing framework migration files |
| `brando.upgrade.prepare` | Reviewed retirement of the recognized consumer-owned upgrade task |
| `brando.upgrade FROM TO` | Version-aware hook called by Igniter |
| `brando.gen.tenant_migration` | Tenant migration source; see the tenancy guide |

For setup failures, fix the first compiler, migration or asset error before
continuing. Do not mark a migration applied to skip an error. Keep historical
migrations and snapshots in version control.
