# <%= application_module %>

To start your server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js f/e dependencies with `cd assets/frontend && pnpm install`
  * Install Node.js b/e dependencies with `cd assets/backend && pnpm install`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## End to end tests with Cypress

  * Install your E2E deps:

    `$ cd e2e && pnpm install`

  * Dump your SQL structure:

    `$ mix ecto.dump`

  * Start server and open Cypress:

    `$ mix test.e2e`

  * Select your project - `myapp/assets/backend`
