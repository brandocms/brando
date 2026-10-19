# Generators

Generate content types, framework migrations and auxiliary modules in an
application that already runs Brando; [Installation](installation.md) sets one
up. The source generators show their changes as an Igniter diff for review, and
a conflicting file stops the plan. The [task reference](#task-reference) lists
the main Brando tasks, including the installation ones; `mix help | grep brando`
lists them all.

<!-- usage-rules:start topic="generators" -->

## Generate a content type

```sh
mix brando.gen.blueprint Catalog Product
mix compile --warnings-as-errors
mix brando.gen MyApp.Catalog.Product
mix brando.gen.blueprint_migration MyApp.Catalog.Product
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

<!-- usage-rules:end -->

Public rendering requires an explicit route choice:

```sh
mix brando.gen MyApp.Catalog.Product --public-route /products
```

This adds a controller/HTML pair with an index at `/products` and a page per
entry at `/products/:slug`, or `/products/:id` when the Blueprint has no `slug`
field. Pages by id need an integer or UUID primary key named `id`; for another,
the generator stops with an issue. Schemas with a status field expose published
records, and the entry page loads the images its [meta fields](blueprints.md#datasources-metadata-and-json-ld) read, such as
`meta_image`. The entry page
shows the main field and, for a Blueprint with block fields, their rendered
blocks (`Brando.HTML.render_blocks/1`). Templates do not assume an image field.
`--main-field` selects a display/filter field; otherwise the generator prefers
`title`, a string field, then `id`.

With the [CMS public pages](installation.md#add-cms-public-pages) (installed by
`mix brando.install` unless you pass `--no-public-site`, or added later with
`mix brando.gen.site`), the routes go in a scope that pipes through
`[:browser, :brando_site]`, as the CMS pages do, so tenant, locale, identity,
navigation and [lockdown](installation.md#lockdown) apply to them. The scope goes after the
`:brando_site` pipeline and before the CMS catch-all. The controller renders in
`YourWeb.CMS.Layouts` with the `partials` fragments, as `CMS.PageController`
does, and puts the entry's meta tags, title and, for a translatable Blueprint,
hreflang links. A missing entry goes to `BrandoWeb.FallbackController`, which
follows a matching redirect or renders the site's [404 page](installation.md#error-pages).
The rendered blocks are direct children of `main`, and the heading, list and
back link sit in `<div class="inner">` inside `.page-section` wrappers, which the
installed frontend's `modules.css` spaces with `@space container;` like the
seeded modules. A `.page-section` that opens `main` gets the seeded hero's top
space below the navigation, and one that ends it the same space before the
footer. The 404 and 500 pages use the same wrappers.

Without the CMS site, the routes pipe through `:browser` only, the pages render
in your application's layout, and the controller resolves the tenant itself. A
missing entry or malformed id raises `Ecto.NoResultsError`, which your
`ErrorHTML` renders as a 404. These pages are not locked by
`Brando.Plug.Lockdown`; the generator's notice says what to wire by hand.
Generate the CMS site before the resource to get the integrated version.

The default Blueprint leaves `absolute_url false`. The notice then prints the
`absolute_url` that matches the new route, such as
`absolute_url ~H"/products/{@entry.slug}"`; set it so admin preview links,
sitemaps and SEO use the page.

For a Blueprint with a `language` field, each language gets its routes, as the
[CMS pages](i18n.md) do: the default language's at `/products`, and every other
language's in a scope under its code, such as `/no/products` (the default
language's too, at `/en/products`, with `scope_default_language_routes: true`).
The languages are read from `config :brando, :languages` and `:default_language`
when the resource is generated. A regional code such as `pt-br` gets the scope
`as: :"pt-br"`, whose helpers (`:"pt-br_product_path"`) `route_i18n` calls. For a
language added later, run the command again: it adds the scopes of the languages
whose routes are missing, and leaves the existing ones.
The pages list and show the request's language with the query's `language:`
option, so translations can share a slug and the context needs no language
clause. With the CMS site, `:brando_site` takes the language from the path;
without it, each scope's `assigns` give it. The notice prints an `absolute_url`
that gives each translation its prefixed URL, for hreflang links, admin previews
and sitemaps: `absolute_url ~H|{route_i18n(@entry, :product_path, :show, [@entry.slug])}|`.
It also prints one when the Blueprint's `absolute_url` gives every language the
same path.

Consumer templates in `priv/templates/brando.gen.blueprint` and
`priv/templates/brando.gen` override package defaults. With a consumer
`controller.ex` or `html.ex` in `priv/templates/brando.gen`, entry pages keep the
`:id` route param, which templates copied before slug routes match, and the
notice says so; the templates' `param` binding then is `"id"`. The Blueprint command also
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

An existing copy is matched by name and left as it is. With `--refresh`, the
command also rewrites each copy whose code differs from Brando's current
template, keeping its file name and timestamp, for review like any other plan:

```sh
mix brando.gen.migrations --refresh
```

That is the fix when an empty database (a new test database, CI, a new server)
stops at an old Brando data migration with `relation "…" does not exist`: the
copy predates the template that skips application tables a later migration
creates. A database that already ran a copy is not affected by rewriting it.

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

Igniter calls the library-owned `brando.upgrade FROM TO` hook. It accepts forward
upgrades from `0.54.0-dev` onward to a 0.54 or 0.55 target, never beyond the
loaded dependency version. Each crossed minor version composes its recipe
before missing framework migrations are planned: a 0.54 → 0.55 upgrade runs
`brando.migrate55` first. A `-dev` version counts as older than every
prerelease and the release of the same version, so a Git or path installation
at `0.55.0-dev` moves onto `0.55.0-beta.0` or `0.55.0` as an upgrade, without a
recipe since both are the 0.55 line. Other versions order as semantic
versions. Equal versions are a no-op; use `brando.gen.migrations` to reconcile
files during development. An application that ran `mix brando.migrate55`
against an earlier `0.55.0-dev` build runs it again after the update to pick up
rewrites added since; the task is idempotent and leaves migrated source unchanged. Applications
with older DSL syntax must first follow [Migrating from 0.53 or 0.54](migrating_from_053.md).
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

Mail generation reuses a Phoenix mailer or creates `MyApp.Mailer`, and
supplies local/test adapter defaults plus a default Req API client; Swoosh and
Req come with Brando, so no dependency is added. It also points Brando at the
mailer, for the email Brando sends itself, and writes a placeholder sender
(`noreply@example.com`) to replace; see [Email](email.md).
`mix brando.gen.mail --contact` also scaffolds a contact form,
`MyApp.Contact.ContactForm`; build its notifications with
`MyApp.Emails.contact(changeset, from: ..., to: ...)`.
Invalid form data raises before constructing an email. Configure the production
adapter and credentials deliberately; generating mail helpers never sends mail.

The sitemap selects published pages; review their public URL rules before calling
`Brando.Sitemap.generate_sitemap/0`. Authorization generation starts from the
maintained default policy; review permissions for your application content types.

Release generation creates `MyApp.ReleaseTasks` and adds a missing Mix release
definition, with `steps: [:assemble, :tar]` for Florist. `brando.install` does
the same, so run it only for an application installed before that. It
preserves existing release settings, runtime configuration, secrets,
Dockerfiles and deployment files, with a notice when an existing release
writes no tarball, or when `mix.exs` defines releases but none named after the
application (it adds no second release then). Build with `MIX_ENV=prod mix release`,
then invoke migrations explicitly as described in [Deployment](deployment.md).
`brando.install.fabfile` is retired and directs callers to release generation and
Florist; it does not modify existing Fabric files. `brando.install` no longer
writes `fabfile.py` or `deployment.cfg` into a new application.

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
| `brando.assets.setup` | Operational asset installation (BrandoJS from npm or a checkout) and consumer builds |
| `brando.gen.blueprint_migration` | Reviewed migration/snapshot pair with stale-plan checks, for one Blueprint or every application Blueprint with `--all`; database application is separate |
| `brando.setup` | Operational post-install setup: assets, database, account, seeds |
| `brando.gen.languages` / `brando.gen.admin` | Operational language/account initialization |
| `brando.gen.seeds` | Operational default content: identity, seven modules, index page, menu, footer fragment |
| `brando.setup.tenancy` | Igniter tenancy source preparation |
| `brando.migrate_to_tenant` | Operational data conversion |
| `brando.migrate` | Runs public or tenant migrations |
| `brando.modules` | Export, plan and import module-definition DSL files |
| `brando.gen.site` | Plans CMS page rendering (a new install composes it) with explicit homepage ownership |
| `brando.gen.sitemap` / `brando.gen.mail` / `brando.gen.authorization` | Reviewed auxiliary modules with conflict checks |
| `brando.gen.release` | Reviewed release helpers and missing Mix configuration |
| `brando.install.fabfile` | Retired; use release generation and Florist |
| `brando.gen.otel` | Reviewed application-scoped telemetry setup |
| `brando.gen.migrations` | Reviewed missing framework migration files |
| `brando.upgrade.prepare` | Reviewed retirement of the recognized consumer-owned upgrade task |
| `brando.upgrade FROM TO` | Version-aware hook called by Igniter |
| `brando.migrate54` / `brando.migrate55` | Migrates application source from Brando 0.53 to 0.54 / 0.54 to 0.55 |
| `brando.gen.tenant_migration` | Tenant migration source; see the tenancy guide |
| `brando.doctor` | Read-only checks of versions, migrations, configuration, assets and content; see [System check](doctor.md) |
| `brando.images.adopt` | Records the config of images made before 0.55 whose files already match it, so they aren't recreated; `--dry-run` counts only. See [Media](media.md#images-made-before-fingerprints) |
| `brando.gettext.reconcile` | Extracts, merges each Gettext backend's existing locales, fills empty translations from sibling catalogs, deletes the emptied 0.53 Blueprint domains and reports per Blueprint domain; `--dry-run` writes nothing |

<!-- usage-rules:start topic="generators" -->

For setup failures, fix the first compiler, migration or asset error before
continuing. After an upgrade, `mix brando.doctor` lists what is still out of
date (see [System check](doctor.md)). Do not mark a migration applied to skip an error. Keep historical
migrations and snapshots in version control.

<!-- usage-rules:end -->
