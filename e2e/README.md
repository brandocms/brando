# E2eProject

## Worktree-isolated E2E runs

`test_e2e.sh` sources `.envrc`, which derives a stable instance key from the
absolute Git worktree path. The key selects a worktree-specific PostgreSQL
database and Phoenix port, so E2E runs from separate worktrees can run at the
same time against one PostgreSQL server.

The runner prints its database and URL before setup. Override the derived
values when needed by exporting `BRANDO_E2E_INSTANCE`,
`BRANDO_E2E_DATABASE`, or `BRANDO_E2E_PORT` before invoking the runner.
GitHub Actions uses the same path with a stable `ci` instance.

## Playwright runs

From `e2e/`, source `.envrc` before running commands:

```sh
source .envrc
./test_e2e.sh --reset tests/blocks/block-var-uploads.spec.js
```

`--reset` drops, migrates and seeds the isolated test database. Compilation is
incremental. Without `--reset`, the runner migrates and seeds only a fresh
database. Setup runs in one Mix VM.

Use `--check-migrations` to reset and also validate rollback and reapplication
of every migration after the baseline. CI runs this once, on `legacy-1`:

```sh
./test_e2e.sh --check-migrations tests/blocks/block-var-uploads.spec.js
```

Keep one Playwright worker per server: SQL sandboxes do not isolate PubSub,
caches or other application state. CI runs the legacy suite in four shards
(`legacy-1` to `legacy-4`), each on its own runner with its own server and
PostgreSQL service.

Each attempt writes its duration and result to `playwright/test-results/timings.jsonl`
(or the selected `--output` directory), including on runs interrupted before
the final HTML/JSON reports. Ordinary actions have a 15-second deadline;
operations that need longer should set an explicit timeout. CI's Playwright
deadline leaves time to finish reports before GitHub's job deadline.

To start your server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install BrandoJS's own dependencies with `cd ../assets && pnpm install` —
    the backend links BrandoJS from this checkout and builds it from source
  * Install Node.js b/e dependencies with `cd assets/backend && pnpm install`
  * Install Node.js f/e dependencies with `cd assets/frontend && yarn install`

`./run_e2e.sh` does all of the above, builds both asset projects and starts the
server.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## End to end tests with Playwright

  * Install Playwright: `cd playwright && pnpm install && pnpm exec playwright install chromium`
  * Run the suite against a freshly seeded database: `source .envrc && ./test_e2e.sh --reset`
  * Run one spec: `source .envrc && ./test_e2e.sh --reset tests/path/to/test.spec.js`
