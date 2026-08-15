#!/bin/zsh
set -e
source .envrc

echo "E2E instance: $BRANDO_E2E_INSTANCE"
echo "E2E database: $BRANDO_E2E_DATABASE"
echo "E2E server: $BRANDO_E2E_BASE_URL"

# Check if database exists, create it if not, then ensure it's up to date
MIX_ENV=test mix do ecto.create, ecto.migrate

# Reset explicitly, otherwise seed only when the isolated database is fresh.
if [ "$1" = "--reset" ] || [ "$2" = "--reset" ]; then
  echo "Resetting database with seed data..."
  MIX_ENV=test mix do ecto.drop, ecto.create, ecto.migrate
  MIX_ENV=test mix run priv/repo/e2e_seeds.exs
else
  BRANDO_SEEDING=true MIX_ENV=test mix run priv/repo/ensure_e2e_seeds.exs
fi

# Build static assets. Each build runs in a subshell so a failure aborts the
# script (set -e) instead of leaving us in the asset directory — previously a
# failed `cd X && ... && cd ../../` chain skipped the final cd, and the server
# then started from assets/frontend and died with "no mix.exs was found".
# The two projects use different package managers: backend is pnpm
# (pnpm-lock.yaml), frontend is yarn (yarn.lock + "packageManager": "yarn@…").
echo "Building static assets [backend]"
(cd assets/backend && pnpm install && pnpm build)
echo "Building static assets [frontend]"
(cd assets/frontend && yarn install && yarn build)

echo "Starting E2E project server"
MIX_ENV=test PORT="$BRANDO_E2E_PORT" iex -S mix phx.server
