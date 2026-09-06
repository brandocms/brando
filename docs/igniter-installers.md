# Igniter source tasks

Implementation tracker: [#2462](https://github.com/brandocms/brando/issues/2462).
User-facing commands and the current Yalc bootstrap are in
[Installation and generators](../guides/generators.md).

`brando.install`, `brando.gen.blueprint`, `brando.gen`,
`brando.gen.blueprint_migration`, framework/tenant migrations, auxiliary
mail/sitemap/authorization/release generators, telemetry and the frontend/backend
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

Source tests use Igniter 0.8.3. A real consumer has been checked with phx_new and
Phoenix 1.8.13, LiveView 1.2.11, Elixir 1.20.3 and OTP 28.4.1. This is evidence for
that combination, not qualification of every version in Brando's unit-test matrix.

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

Igniter 0.8 automatically accepts tasks with redirected stdin. Use `--dry-run` for
unattended previews. Real terminal rejection and dry-run behavior have both been
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

The disposable consumer check has exercised the real `igniter.install` command,
both Vite builds through Yalc, database migrations, admin login, and creating,
editing and publicly rendering a generated resource. Keep the issue open for
optional CMS public-site scaffolding, the complete consumer CI/tenancy matrix,
full old-consumer/version-upgrade qualification, and release artifact qualification. npm publication is deliberately deferred until
release preparation.
