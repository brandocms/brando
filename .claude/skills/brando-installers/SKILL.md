---
name: brando-installers
description: Igniter installer and generator contracts in Brando. Use when changing `mix brando.install`, a `brando.gen*` generator, another Igniter task, a Blueprint storage plan, or an upgrade task.
user-invocable: true
---

# Igniter installers and generators

`brando.install`, `brando.gen.blueprint`, `brando.gen`,
`brando.gen.blueprint_migration`, framework/tenant migrations, the auxiliary
generators (mail, sitemap, authorization, release, CMS site), telemetry
(`brando.gen.otel`) and the frontend/backend asset generators all use Igniter.
`igniter.install brando` discovers the same `brando.install` task
(`Mix.Tasks.Brando.Install`): there is one installation implementation. The planning modules live in `lib/mix/brando/igniter/`.
User-facing commands and asset setup are in `guides/installation.md` and
`guides/generators.md`.

## Discovery and supported inputs

`Mix.Brando.Igniter.Project.discover/2` reads the pending source tree and
returns `{:ok, igniter, project}` or `{:error, igniter}` with issues. It
discovers the OTP application independently of the application/web/admin
namespaces, Repo, endpoint and router. Several matching modules require
explicit `--repo`, `--router` or `--endpoint`; the other overrides are
`--module`, `--web-module` and `--admin-module`. Literal existing Brando
namespace configuration is respected. Discovery never evaluates consumer code.

Supported: a standalone Phoenix application with a literal Mix application
callback, a PostgreSQL Repo, conventional application children, and an
endpoint plugging the selected router. Umbrella roots, unsupported supervision
shapes, ambiguous modules and dynamic or conflicting identity/tenancy
configuration are blocking issues.

## Source planning and file ownership

- Shared Elixir files are extended through AST edits; existing routes,
  dependencies, secrets, application children and tests stay. The installer
  enables named Phoenix route helpers, initializes Brando after successful
  supervisor startup, and uses a distinct admin API pipeline beside Phoenix's
  `:api`. Runtime module lookup respects the selected endpoint/router/admin
  namespaces.
- `Mix.Brando.Igniter.Files.create/3` checks both pending and existing owned
  files. Equivalent Elixir ASTs pass (comments and formatting kept); text
  comparison normalizes trailing whitespace, as Rewrite's writer does.
  Different content blocks the plan, even with `--yes`.
- Consumer asset `package.json` manifests gain missing defaults; existing
  dependency sources and scripts stay.
- Historical migration names match independently of timestamps; newly added
  versions sort after existing ones.
- Binary files (the templates' `.ico` favicons, the only binaries they ship)
  never enter Rewrite's new-file writer, which normalizes trailing newlines
  even for binaries. The digest-checked `brando.assets.copy` task, whose
  allowlist is the template manifest's `.ico` entries, runs after acceptance,
  writes exact bytes with atomic no-clobber creation, and refuses changed
  destinations. Dry runs copy nothing. `brando.assets.setup` is a separate
  operational task that installs and builds consumer assets, with BrandoJS
  from npm, a Yalc copy of a checkout, or a linked checkout.

## CLI and compilation boundaries

### Install flags

A new install defaults to tenancy `none`; a rerun without the flag keeps the
existing configuration. `single` requires a valid site key. `--interactive`
asks only for missing choices; `--yes` controls diff acceptance; closed input
is an issue. `--no-tenancy-prompt` turns the questions off, even with
`--interactive`.

### Blueprints and resources

- `brando.gen.blueprint` takes `Domain Schema`, validates module and query
  names, and generates title/slug fields, a form and a listing in the current
  DSL. Template precedence: explicit `--template`, then the consumer's
  template, then the packaged default.
- Resource generation takes a **compiled** Blueprint. A Blueprint with pending
  source changes cannot feed a resource generator in the same plan: accept,
  compile, then generate. Embedded Blueprints cannot generate standalone
  resources.
- Context query declarations and admin routes are edited semantically: custom
  functions stay, conflicting names are reported, and the checks include
  function names other Blueprints' query/mutation declarations supply.
- Route ownership accounts for nested prefixes, REST resources and parameter
  names; existing `/admin` routes need integrating before installation.
  Explicit admin and resource routes precede public catch-alls.
- Public controllers/routes require `--public-route`. When the CMS site exists
  they pipe through its `:brando_site` pipeline, ahead of its catch-all, and
  render in its layout. Authorization and navigation stay explicit application
  choices.

### CMS site

The CMS scaffold uses a distinct `Web.CMS` namespace and an explicit
`:page_html_module` configuration. It owns a tenant/locale/identity pipeline,
page routes and Brando's support endpoints, appending catch-all routing after
the application's explicit routes.

- A new install composes it unless given `--no-public-site`, and takes the
  root from phx.new's `PageController.home` only while that controller and its
  `home.html.heex` are unchanged; a changed homepage is kept, without the
  site, with a notice, and `--interactive` asks instead. Reruns never add the
  site.
- `mix brando.gen.site --replace-phoenix-home` removes only the root
  `PageController.home` declaration; nested routes and Phoenix source files
  stay.
- Other ownership (another homepage, catch-alls, parameter-first routes,
  support paths, or no `:browser` pipeline) blocks `mix brando.gen.site`; a new
  install leaves the site out instead, with a notice naming the routes.
- Custom generated files block the plan. Guidance requires an affirmative
  ownership answer, independent of diff acceptance.

### What planning does not do

New direct dependencies queue one `deps.get` after source acceptance; existing
dependency sources are kept. Dependency installation and compilation that
Igniter itself performs are upstream bootstrap. Brando's planning callbacks
start no database, seed no content, build no assets, create no accounts and
deploy nothing.

### Optional Igniter dependency

Brando compiles with and without Igniter. Both branches of each optional
module implement Mix's `__mix_recompile__?/0` hook: fallback modules request
recompilation when Igniter appears, native modules when it is removed.
Otherwise empty conditional source files stay absent after a dependency
compiled without Igniter, even when the installer task itself reloads.
Subprocess tests cover both transitions, and a separate Elixir process checks
that guarded helpers compile without Igniter.

## Storage plans

`Brando.Blueprint.Migrations.plan/2` reads and validates history without
writing files or directories. `commit_plan/1` rechecks the compiled schema and
a fingerprint of the migration/snapshot files under the existing locks;
fingerprints serialize deterministically across Igniter's separate Mix
process. The deferred Igniter adapter prints the migration source before
acceptance and uses this writer for both transaction participants: binary
snapshots and independently writable migrations never go to Rewrite.
Competing or stale plans are rejected; a snapshot failure rolls back the newly
created migration. Compose at most one storage plan per invocation: one
Blueprint, or every application Blueprint with `brando.gen.blueprint_migration
--all` (`plan_all/1` and `commit_plans/1`: written together or not at all, and
it takes neither `--migration-path` nor `--rebaseline`).

Igniter accepts automatically when stdin is not a terminal (outside
`MIX_ENV=test`). Unattended previews use `--dry-run --yes`; `--yes` also
suppresses the large-diff question.

## Auxiliary and upgrade contracts

- **Mail** reuses `<App>.Mailer` or the application's one other Swoosh
  mailer (else creates `<App>.Mailer`), points `config :brando, mailer:` at it
  and writes a placeholder sender when none is set. `--contact`'s
  `Emails.contact/2` requires explicit `:from`/`:to` and a valid form
  changeset. It adds no dependency (Swoosh and Req come with Brando) and sends
  nothing.
- **Release** owns only ReleaseTasks and missing Mix release configuration.
- **Telemetry** keeps service/exporter configuration, initializes the
  discovered Repo inside `start/2`, requires no provider credentials and
  attaches no duplicate LiveView handlers.
- **Tenancy preparation** uses the same opt-in interactive contract and shared
  configuration mutation as installation.
- **Upgrades.** `brando.upgrade` (the `igniter.upgrade` hook) and
  `brando.gen.migrations` are library-owned; a consumer-owned
  `Mix.Tasks.Brando.Upgrade` under `lib/` blocks `brando.upgrade`.
  `brando.upgrade.prepare` recognizes any version Brando installed
  (`priv/templates/brando.migrate/legacy_upgrade_tasks`), archives it to
  `priv/brando/legacy_tasks/` outside compilation paths, and removes it only
  when the archive has no conflict; a customized implementation requires an
  explicit rename. A separate compile removes the stale beam before Igniter
  resolves the library hook.
- **Version hook** rejects downgrades, versions before `0.54.0-dev` (old DSL
  source), target minors without a recipe and versions beyond the loaded
  dependency; a `-dev` version orders before every prerelease and the release
  of the same version (`Upgrade.compare_versions/2`); equal versions are a
  no-op. Recipes are keyed by target minor (`55 => "brando.migrate55"`). The
  pre-0.54 DSL conversion (`brando.migrate54`) stays an explicit compilation
  prerequisite with its own rewrite tests.

## Verification

Source tests (also part of `mix test`), optionally with test files to run a
subset:

```sh
MIX_ENV=test mix run --no-start scripts/test_igniter.exs
```

They cover direct and composed plans, repeat runs, custom namespaces,
conflicts, template precedence, missing input, exact binary copying,
historical migration names, compiling two resources in one context, and
rejecting existing authentication-table ownership before planning.

The consumer smoke creates a fresh phx.new consumer and an isolated database
per run and drives the real `igniter.install`: preview/rerun fingerprints,
binary asset bytes, both Vite builds through Yalc, migrations (including a
fresh database), tenant storage after site provisioning (schema-qualified
public user references, automatic tenant migration destinations, shared user
cascades before the first environment exists), admin login, creating, editing
and publicly rendering a generated resource, and CMS pages, drafts, 404s and
robots. Database tests verify the user cascades in every active environment.
Prerequisites, environment variables and the precompiled/customized cases are
in `scripts/igniter_smoke/README.md`; one run per tenancy mode:

```sh
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh none   # also: single, multi
```

`BRANDO_SMOKE_SOURCE=packaged` runs the same workflow against the Hex and npm
packages a release would publish (`mix hex.build` and `npm pack` from a
scratch copy at a non-development version), with no checkout or Yalc.
