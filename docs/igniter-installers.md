# Igniter source tasks

Implementation tracker: [#2462](https://github.com/brandocms/brando/issues/2462).
User-facing commands and the current Yalc bootstrap are in
[Installation and generators](../guides/generators.md).

`brando.install`, `brando.gen.blueprint`, `brando.gen`,
`brando.gen.blueprint_migration`, framework/tenant migrations, auxiliary
mail/sitemap/authorization/release/CMS-site generators, telemetry and the frontend/backend
asset generators use Igniter. `igniter.install brando` discovers the same
`Brando.Install` task; there is one installation implementation.

## Discovery and supported inputs

`Mix.Brando.Igniter.Project.discover/2` reads the pending source tree and returns
`{:ok, igniter, project}` or `{:error, igniter}` with issues. It discovers the OTP
application independently of application/web/admin namespaces, Repo, endpoint
and router. Multiple matching modules require explicit selection with `--repo`,
`--router` or `--endpoint`. Other overrides are `--module`, `--web-module` and
`--admin-module`. Literal existing Brando namespace configuration is respected.

The initial supported layout is a standalone Phoenix application with a literal
Mix application callback, a PostgreSQL Repo, conventional application children,
and an endpoint plugging the selected router. Umbrella roots, unsupported
supervision shapes, ambiguous modules and dynamic/conflicting identity or tenancy
configuration produce blocking issues. Discovery does not evaluate consumer code.

Source tests use Igniter 0.8.3. Real consumers have been checked with phx_new and
Phoenix 1.8.13, LiveView 1.2.11, Elixir 1.20.3 and OTP 28.4.1. This is evidence for
that combination with PostgreSQL 16.1, not qualification of every version in
Brando's unit-test matrix. The `igniter.new` archive 0.5.28 one-shot path also
installs and compiles successfully from outside an existing Mix project.

## Source planning and file ownership

Shared Elixir files are extended using AST edits. Existing routes, dependencies,
secrets, application children and tests remain in place. The installer enables
named Phoenix route helpers, initializes Brando after successful supervisor
startup, and uses a distinct admin API pipeline to coexist with Phoenix's `:api`.
Runtime module lookup respects selected endpoint/router/admin namespaces.

`Files.create/3` checks both pending and existing owned files. Equivalent Elixir
ASTs preserve comments and formatting. Text comparison permits trailing whitespace
normalization, matching Rewrite's writer. Different content blocks the plan even
with `--yes`. Consumer asset package manifests merge missing defaults while
preserving existing dependency sources and scripts. Historical migration names are
matched independently of timestamps, and newly added versions follow existing ones.

Rewrite normalizes trailing newlines even for binary files. Binary fonts/icons
therefore never enter its new-file writer. A whitelisted, digest-checked
`brando.assets.copy` task runs after acceptance, writes exact bytes with atomic
no-clobber creation, and refuses changed destinations. Dry runs do not copy them.
`brando.assets.setup` is a separate operational task for Yalc and consumer builds.

## CLI and compilation boundaries

A new install defaults to tenancy `none`; a rerun with no flag preserves existing
configuration. `single` requires a valid site key. `--interactive` asks only for
missing choices, while `--yes` controls diff acceptance. Closed input is an issue.
`--no-tenancy-prompt` retains its compatibility behavior.

Blueprint generation takes `Domain Schema`, validates module and query names,
and generates title/slug fields, a form and a listing using the current DSL.
Explicit `--template` wins over the consumer template, then the packaged default.

Resource generation takes a compiled Blueprint. A Blueprint with pending source
changes cannot feed a resource generator in the same plan: accept, compile, then
generate. Context query declarations and admin routes are edited semantically;
custom functions are preserved and conflicting names are reported. Public
controllers/routes require `--public-route`. Authorization and navigation are
explicit application choices.

Optional CMS scaffolding uses a distinct Web.CMS namespace and an explicit
`:page_html_module` configuration. It owns a tenant/locale/identity pipeline,
page routes and the Brando support endpoints, appending catch-all routing after
explicit application routes. `--replace-phoenix-home` only removes the root
Phoenix PageController.home declaration; nested routes and Phoenix source files
remain. Other ownership and custom generated files block the plan. Guidance
requires an affirmative ownership answer, independently of diff acceptance.

Embedded Blueprints cannot generate standalone resources. Context checks include
function names supplied by other Blueprint query/mutation declarations. Route
ownership accounts for nested prefixes, REST resources and parameter names;
existing `/admin` routes require integration before installation. Explicit admin
and resource routes precede public catch-alls.

New direct dependencies queue one `deps.get` after source acceptance. Existing
dependency sources are preserved. Dependency installation and compilation
performed by Igniter itself remain upstream bootstrap operations. Brando's planning callbacks do not start a database, seed
content, build assets, create accounts, or deploy an application.

## Storage plans

`Migrations.plan/2` reads and validates history without writing files or directories.
`commit_plan/1` rechecks the compiled schema and a fingerprint of migration/snapshot
files under the existing locks. The deferred Igniter adapter prints the migration
source before acceptance and uses this writer for both transaction participants.
It never hands binary snapshots or independently writable migrations to Rewrite.
Fingerprints serialize deterministically across the separate Mix process used by
Igniter. Competing/stale plans are rejected; snapshot failure rolls back the newly
created migration. Only one Blueprint storage plan may be composed per invocation.

Igniter 0.8 automatically accepts tasks with redirected stdin. Use `--dry-run --yes` for
unattended previews; `--yes` also suppresses the large-diff display question. Real terminal rejection and dry-run behavior have both been
checked against the disposable consumer, followed by successful paired persistence
and database application of an accepted alteration.

## Auxiliary and upgrade contracts

Mail reuses existing mailers, requires explicit notification addresses and
valid form data, and supplies Swoosh/Req defaults without sending messages.
Release generation owns only ReleaseTasks and missing Mix release configuration;
legacy deployment/environment/config replacement is retired. Telemetry preserves
service/exporter configuration and initializes the discovered Repo inside start/2.
It does not require provider credentials or attach duplicate LiveView handlers.
The tenancy preparation task uses the same opt-in interactive contract and shared
configuration mutation as installation.

`brando.gen.migrations` is library-owned and distinct from historical
consumer-owned `brando.upgrade` tasks. The compatibility planner recognizes the
maintained historical implementation, archives its complete source outside
compilation paths and schedules removal only after conflict checks. Customized
implementations require an explicit rename. A separate compile removes the stale
beam before Igniter resolves the library hook. The current version hook rejects
downgrades, unsupported old DSL source, future recipes and versions beyond the
loaded dependency. Equal versions are a no-op. The pre-0.54 DSL conversion remains
an explicit compilation prerequisite, with its own existing rewrite tests.

## Verification and remaining work

```sh
MIX_ENV=test mix run --no-start scripts/test_igniter.exs
```

Pass one or more test files to select a smaller group. These tests also run in the
normal `mix test` suite. They cover direct/composed plans, repeat runs, custom
namespaces, conflicts, template precedence, missing input, exact binary copying,
historical migration names, and compiling two resources in a shared context.
A separate Elixir process verifies that guarded helpers compile without Igniter.

Both branches of optional modules implement Mix's
[`__mix_recompile__?/0` hook](https://hexdocs.pm/mix/Mix.Tasks.Compile.Elixir.html#module-__mix_recompile__-0).
Empty conditional source files otherwise stay absent after a dependency was
compiled without Igniter, even when the installer task itself reloads. Fallback
modules now request recompilation when Igniter appears; native modules request it
when Igniter is removed. Subprocess tests cover both transitions. A real consumer
compiled without Igniter, added it, ran the normal package installer and compiled
successfully without a manual forced rebuild after adding Igniter.

The disposable consumer check has exercised the real `igniter.install` command,
both Vite builds through Yalc, database migrations, admin login, and creating,
editing and publicly rendering a generated resource in all three tenancy modes.
The reproducible [smoke script](../scripts/igniter_smoke/README.md) creates a new
consumer and isolated database per run, checks preview/rerun fingerprints and
binary asset bytes, and provisions named environments before generating tenant
storage. A GitHub Actions matrix runs the same workflow; its remote result still
needs confirmation after pushing the branch.

These checks caught and now cover schema-qualified public user references,
automatic tenant migration destinations and shared user cascades before the first
environment exists. Dedicated database tests verify cascades in all active
environments while preserving the caller's tenant context.

The CMS scaffold also passes a real dry run/rerun and browser checks for published
pages, drafts, 404s, robots and its frontend initialization without optional menu
markup. The fixture suite rejects existing authentication table ownership before
planning installation.

Keep the issue open for broader existing-app and old-consumer/version-upgrade
qualification across additional layouts/versions, and release artifact qualification.
The customized/precompiled consumer case is included in the smoke CI matrix and
passes locally, preserving custom files, routes, configuration, context functions
and supervision while exercising both browser workflows.
npm publication is deliberately deferred until release preparation.
