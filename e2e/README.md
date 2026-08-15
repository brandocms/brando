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

To start your server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js f/e dependencies with `cd assets/frontend && yarn install`
  * Install Node.js b/e dependencies with `cd assets/backend && yarn install`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## End to end tests with Cypress

  * Install your E2E deps:

    `$ cd e2e && yarn install`

  * Dump your SQL structure:

    `$ mix ecto.dump`

  * Start server and open Cypress:

    `$ mix test.e2e`

  * Select your project - `myapp/assets/backend`
