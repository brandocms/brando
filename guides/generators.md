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
conflicting files. `--dry-run` previews source without applying it.
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
Templates do not assume an image field. `--main-field` selects a display/filter
field; otherwise the generator prefers `title`, a string field, then `id`.

Consumer templates in `priv/templates/brando.gen.blueprint` and
`priv/templates/brando.gen` override package defaults. The Blueprint command also
accepts `--template RELATIVE_PATH`, which takes precedence over the conventional
consumer override. Conflicting output files are preserved for manual integration.

[Blueprint migrations](blueprint_migrations.md) explains snapshot history,
subsequent storage changes, rollback, and explicit rebaseline. Migration/snapshot
planning and versioned Igniter upgrades remain tracked in
[#2462](https://github.com/brandocms/brando/issues/2462); source installation is not
an automatic data-upgrade procedure for an older Brando application.

## Task reference

Run `mix help TASK` for current options. These are separate operations:

| Task | Result |
| --- | --- |
| `brando.install` | Reviewed Brando source installation; also called by `igniter.install` |
| `brando.gen.blueprint` | Reviewed Blueprint source |
| `brando.gen` | Reviewed context/admin source; optional public routes |
| `brando.gen.backend` / `brando.gen.frontend` | Reviewed asset scaffolds with conflict checks |
| `brando.assets.setup` | Operational Yalc installation and consumer builds |
| `brando.gen.blueprint_migration` | Storage migration and snapshot; review before applying |
| `brando.gen.languages` / `brando.gen.admin` | Operational language/account initialization |
| `brando.setup.tenancy` | Igniter tenancy source preparation |
| `brando.migrate_to_tenant` | Operational data conversion |
| `brando.gen.sitemap` / `brando.gen.mail` / `brando.gen.authorization` | Legacy auxiliary source generators pending conversion |
| `brando.gen.release` / `brando.install.fabfile` | Legacy deployment scaffolds pending replacement |
| `brando.gen.tenant_migration` | Tenant migration source; see the tenancy guide |

For setup failures, fix the first compiler, migration or asset error before
continuing. Do not mark a migration applied to skip an error. Keep historical
migrations and snapshots in version control.
