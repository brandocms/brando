# Fresh Igniter consumer smoke

This creates a new standalone Phoenix app and a uniquely named database for every
run. It exercises the real package installer with the current Brando checkout and
matching Yalc assets, rather than an already configured E2E application.

Prerequisites: Elixir 1.20.3 / OTP 28.4.1, phx_new 1.8.13, Node.js 24 or a
later even major (the admin's `engines` is `>=24.0.0`), pnpm,
Yalc 1.0.0-pre.53 (checkout source only), and a disposable PostgreSQL service. Local checks used Node.js
23.11.0, pnpm 10.4.1 and PostgreSQL 16.1. All four cases also
[passed on Linux CI](https://github.com/brandocms/brando/actions/runs/34073198244)
with Node.js 22, pnpm 10.32.1 and PostgreSQL 14. Install the pinned browser test
dependency and Chromium once:

```sh
pnpm --dir scripts/igniter_smoke install --frozen-lockfile
pnpm --dir scripts/igniter_smoke exec playwright install chromium
```

From the repository root:

```sh
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh none
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh single
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh multi
BRANDO_SMOKE_BOOTSTRAP=precompiled BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh none
```

Set `BRANDO_SMOKE_PGHOST`, `BRANDO_SMOKE_PGUSER`, and
`BRANDO_SMOKE_PGPASSWORD` for that service. Defaults are localhost and
postgres/postgres. `BRANDO_SMOKE_PORT` selects the consumer HTTP port (4482).
The browser tests run twice. First the consumer runs as installed, with
`hmr: true` and its `Brando.Vite` endpoint watchers starting the admin's and
the site's Vite dev servers, on the next two ports (4483 and 4484) unless
`BRANDO_SMOKE_VITE_ADMIN_PORT` and `BRANDO_SMOKE_VITE_FRONTEND_PORT` say
otherwise. The run fails if one of them answers before the consumer starts,
or if a Vite server still listens after it stops. Then the database goes
back to its seeded copy (`<database>_seeded`), `config/dev.exs` gets
`hmr: false`, and the tests run against the built assets. Logs are
`server.log`/`browser-vite.log` and `server-built.log`/`browser-built.log`.
`BRANDO_SMOKE_PHX_EBIN` optionally selects a compiled phx_new beam directory
instead of the installed archive.

The script verifies an unattended dry run and an installation rerun against
source fingerprints, and that the installer wrote what Florist's release build
needs (Brando's Dockerfile and `.dockerignore`, ReleaseTasks, a release that
writes the tarball, a runtime `media_path`) and a live preview target for CMS
pages. It builds both Vite consumers, verifies manifests and exact
binary assets, migrates the database, and initializes the chosen tenancy mode.
The installer explicitly selects CMS page rendering and replaces the generated
Phoenix homepage route. It seeds published and draft Pages inside live environments,
then generates a Blueprint/resource and storage after site provisioning,
applies the appropriate migrations, signs into the admin, creates and edits a
Product, and checks its public rendering through Chromium. A second browser test
edits the CMS homepage in admin and checks public cache invalidation, the CMS
layout, published pages, draft protection, 404s, robots and frontend
errors. After checking installer idempotence, a fixture adds application-owned
navigation to the minimal CMS layout. A third browser test exercises frontend
initialization and the installed mobile-menu animations, including reopening,
resize and interrupted transitions. No email or telemetry
is sent. A failure retains logs and browser traces in the printed temporary
directory; the consumer server stops on exit.

The `precompiled` case first builds Brando without Igniter, then adds it and runs
ordinary dependency compilation. It also adds application-owned routes, files,
configuration, a context function and a supervised process before installation.
The check verifies their preserved bytes or runtime behavior after the complete
installation/generation workflow, including the custom public endpoint.

## Packaged source

`BRANDO_SMOKE_SOURCE=packaged` runs the same consumer workflow against the
packages a release would publish instead of the checkout:

```sh
BRANDO_SMOKE_SOURCE=packaged BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh none
```

[`packages.sh`](packages.sh) copies the checkout's tracked and unignored files
to a scratch directory, sets a release candidate version there with
`scripts/release-version bump`, and builds the Hex tarball (`mix hex.build`)
and the npm tarball (`npm pack` in `assets/`). The Hex tarball is unpacked as
`mix deps.get` would unpack it, and the scratch copy is deleted, so no Brando
checkout remains next to the consumer. `logs/packages.log` has the file
counts and sizes, `logs/hex-contents.txt` and `logs/npm-contents.txt` the
listings. Either package containing `node_modules`, `_build`, `deps` or Yalc
state fails the run, and so does a Hex package without the `.formatter.exs`
that applications' `import_deps: [:brando]` reads.

The candidate version is the checkout's `X.Y.Z` with `-rc.smoke`
(`0.55.0-dev` becomes `0.55.0-rc.smoke`); `BRANDO_SMOKE_VERSION` overrides it.
It must not be a development version: a released Brando generates an admin
that pins `@brandocms/brandojs` to its own version on npm, and that is the path
this mode qualifies. `rc.smoke` is never published, so the installed version
also proves which tarball pnpm used.

The consumer takes Brando as a path dependency on the unpacked Hex package,
which resolves its own dependencies from Hex like any package. The generated
`assets/backend/package.json` keeps the exact npm pin users get; since no
registry has the candidate, [`packaged.exs`](packaged.exs) adds a
`pnpm.overrides` entry pointing that package at the npm tarball. pnpm then
installs the tarball's contents and resolves its dependencies from npm as a
registry install would. A local registry would also exercise registry
metadata and dist-tags, which publication and the registry-download check
cover.

`mix brando.assets.setup` runs without options and must take the npm path. A
`yalc` on the front of `PATH` fails if anything runs it, and CI installs no
Yalc for packaged jobs. After the asset builds the check requires the
installed BrandoJS version to be the candidate, `pnpm-lock.yaml` to resolve it
to the tarball, and no `.yalc`, `yalc.lock` or project Yalc store. The run
fails if the consumer wrote into the unpacked Hex package, or if any file in
the consumer (dependencies, `_build` and `node_modules` included) names the
checkout's path.

## Inspecting a run

The generated app and its database remain available for inspection. Dispose of
them with the temporary directory and PostgreSQL service when finished. The
workflow in `.github/workflows/igniter-smoke.yml` runs each mode against a separate
PostgreSQL service on a fresh runner, and retains failure artifacts for seven days.
It runs the packaged source for the `none` and `multi` tenancy modes.
Registry downloads after publication and additional version combinations
require separate qualification.
