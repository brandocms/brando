#!/bin/zsh
set -e

# Check if database exists, create it if not, then ensure it's up to date
MIX_ENV=test mix do ecto.create, ecto.migrate

# Only run seeds if database was just created or if --reset flag is passed
if [ "$1" = "--reset" ] || [ "$2" = "--reset" ]; then
  echo "Resetting database with seed data..."
  MIX_ENV=test mix do ecto.drop, ecto.create, ecto.migrate
  MIX_ENV=test mix run priv/repo/e2e_seeds.exs
elif ! MIX_ENV=test mix ecto.migrate; then
  echo "Running seed data for fresh database..."  
  MIX_ENV=test mix run priv/repo/e2e_seeds.exs
fi

# build static assets
echo "Building static assets [backend]"
cd assets/backend && yalc update && yarn install --force && yarn build && cd ../../
echo "Building static assets [frontend]"
cd assets/frontend && yarn install && yarn build && cd ../../

echo "Starting E2E project server"
MIX_ENV=test PORT=4444 iex -S mix phx.server