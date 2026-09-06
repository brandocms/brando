# Igniter installer foundations

Implementation tracker: [#2462](https://github.com/brandocms/brando/issues/2462).

The first increment provides shared source-planning helpers and the opt-in
interactive installer convention. The main `brando.install` task is still the
legacy fresh-project scaffold; its conversion to Igniter is the next increment.
It must not be used as an in-place updater. The new discovery/namespace options
below are internal contracts, not additional flags on the legacy task.

## Source discovery

`Mix.Brando.Igniter.Project.discover/2` reads the pending Igniter sources and
returns `{:ok, igniter, project}` or `{:error, igniter}` with a blocking issue.
Always carry the returned Igniter forward.

The initial supported shape is a standalone Phoenix project with a conventional
`mix.exs`, an application callback declared as a literal module tuple, an Ecto
Repo declaring the PostgreSQL adapter, and an endpoint that plugs the selected
router. The source helpers are exercised with Igniter 0.8.3; the repository's CI
currently covers Elixir 1.17–1.20 and OTP 27–28. Consumer version compatibility
still needs qualification with the actual installer.

Discovery returns the OTP application, base application namespace, supervision
module, web/admin namespaces, Repo, router, and endpoint. It uses the selected
router's `use WebModule, :router` declaration for the web namespace. By default,
the application namespace comes from the Mix project module and the admin
namespace appends `Admin`; composing tasks can supply namespace overrides.
Discovery does not evaluate consumer configuration or load its modules.

`Project.options/0` supplies string options for `module`, `web_module`,
`admin_module`, `repo`, `router`, and `endpoint` to an Igniter task's `info/2`.
Multiple Repos/routers/endpoints require explicit selection. Endpoints must use
the selected router, and test-support modules are excluded from candidates.
Umbrella roots and unsupported adapters produce issues before scaffold writes.

## Owned files and shared files

`Mix.Brando.Igniter.Files.create/3` plans a new owned file. Equivalent existing
Elixir code is preserved, including comments and formatting; non-Elixir files
must match byte for byte. Different content produces a blocking issue rather
than an overwrite, including when `--yes` is set. Pending files from other
composed tasks participate in the same check.

Patch shared files such as `mix.exs`, application modules, configuration, and
routers with Igniter's AST helpers. Do not pass them to an owned-file copier or
call a disk-writing legacy task inside `igniter/1`. Keep Yalc and the consumer's
chosen dependency sources during iteration. npm publication belongs to later
release qualification.

## Defaults and guided setup

New installations default to tenancy mode `none` without prompting.
`mix brando.install --interactive` guides the tenancy choice; an explicit
`--tenancy-mode single` asks only for the missing site key. Supplied choices are
respected. `--tenancy-prompt` remains a compatibility alias and
`--no-tenancy-prompt` suppresses tenancy questions even with `--interactive`.
Closed stdin produces the existing actionable prompt error, not an assumed
answer.

Future Igniter generators should use the same opt-in `--interactive` convention:
ask only for missing choices, validate responses, and pass resolved arguments
to source-planning helpers. `--yes` accepts a reviewed plan; it is not a request
for guided setup or permission to overwrite conflicting application files.

`Mix.Brando.Install.Options.tenancy/2` supplies the pure option resolver for the
native installer. Passing an existing tenancy choice preserves it when flags
are omitted; a mode is not assigned as an OptionParser default because doing so
would erase the distinction between omission and an explicit change. The legacy
scaffold does not yet read or preserve an existing application's configuration.

## Focused verification

Run the source tests and the existing installer regression tests without
starting Brando or connecting to a database:

```sh
MIX_ENV=test mix run --no-start scripts/test_igniter.exs
```

Pass a test file to rerun a failing group:

```sh
MIX_ENV=test mix run --no-start scripts/test_igniter.exs test/mix/brando/igniter/project_test.exs
```

The same test files are also discovered by the normal `mix test` suite.
Fixtures contain source only and distinguish the OTP name from the module and
web namespaces. They preserve existing routes, tests, local dependencies, and
Yalc manifests. A separate Elixir process verifies that the optional helpers
can compile without Igniter installed. These checks establish the planning
contracts; complete installation still needs generated-consumer compilation,
consumer Vite builds, database setup, and browser verification in later steps.
