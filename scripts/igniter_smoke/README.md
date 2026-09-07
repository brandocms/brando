# Fresh Igniter consumer smoke

This creates a new standalone Phoenix app and a uniquely named database for every
run. It exercises the real package installer with the current Brando checkout and
matching Yalc assets, rather than an already configured E2E application.

Prerequisites: Elixir 1.20.3 / OTP 28.4.1, phx_new 1.8.13, Node.js 22, pnpm,
Yalc 1.0.0-pre.53, and a disposable PostgreSQL service. Install the pinned browser
test dependency and Chromium once:

```sh
pnpm --dir scripts/igniter_smoke install --frozen-lockfile
pnpm --dir scripts/igniter_smoke exec playwright install chromium
```

From the repository root:

```sh
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh none
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh single
BRANDO_SMOKE_PGPORT=5432 ./scripts/igniter_smoke.sh multi
```

Set `BRANDO_SMOKE_PGHOST`, `BRANDO_SMOKE_PGUSER`, and
`BRANDO_SMOKE_PGPASSWORD` for that service. Defaults are localhost and
postgres/postgres. `BRANDO_SMOKE_PORT` selects the consumer HTTP port (4482).
`BRANDO_SMOKE_PHX_EBIN` optionally selects a compiled phx_new beam directory
instead of the installed archive.

The script verifies an unattended dry run and an installation rerun against
source fingerprints. It builds both Vite consumers, verifies manifests and exact
binary assets, migrates the database, and initializes the chosen tenancy mode.
It then generates a Blueprint/resource and storage after site provisioning,
applies the appropriate migrations, signs into the admin, creates and edits a
Product, and checks its public rendering through Chromium. No email or telemetry
is sent. A failure retains logs and browser traces in the printed temporary
directory; the consumer server stops on exit.

The generated app and its database remain available for inspection. Dispose of
them with the temporary directory and PostgreSQL service when finished. The
workflow in `.github/workflows/igniter-smoke.yml` runs each mode against a separate
PostgreSQL service on a fresh runner, and retains failure artifacts for seven days.
Release packages/npm and additional version combinations require separate
qualification; this job deliberately exercises the current checkout/Yalc path.
