#!/bin/zsh
set -e

# Default test command
TEST_COMMAND="test"
RESET_DB=false
EXTRA_ARGS=()

# Process arguments
for arg in "$@"; do
  if [ "$arg" = "--ui" ]; then
    TEST_COMMAND="test:ui"
  elif [ "$arg" = "--reset" ]; then
    RESET_DB=true
  else
    EXTRA_ARGS+=("$arg")
  fi
done

# Check if database exists, create it if not, then ensure it's up to date
MIX_ENV=e2e mix do ecto.create, ecto.migrate

# Only run seeds if database was just created or if --reset flag is passed
if [ "$RESET_DB" = true ]; then
  echo "Resetting database with seed data..."
  MIX_ENV=e2e mix do ecto.drop, ecto.create, ecto.migrate
  MIX_ENV=test mix run priv/repo/e2e_seeds.exs
elif ! MIX_ENV=e2e mix ecto.migrate; then
  echo "Running seed data for fresh database..."
  MIX_ENV=test mix run priv/repo/e2e_seeds.exs
fi

cd e2e/playwright && yarn $TEST_COMMAND "${EXTRA_ARGS[@]}"