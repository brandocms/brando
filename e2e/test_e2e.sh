#!/usr/bin/env bash
set -euo pipefail
source .envrc

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
  # Force recompile to ensure sandbox plug is included (compile_env is evaluated at compile time)
  MIX_ENV=e2e mix compile --force --warnings-as-errors
  MIX_ENV=e2e mix do ecto.drop, ecto.create, ecto.migrate
  echo "Validating post-baseline migration rollback and forward execution..."
  # `--to` is inclusive, so target the first migration after the monolithic baseline.
  MIX_ENV=e2e mix ecto.rollback --to 20250528084352
  MIX_ENV=e2e mix ecto.migrate
  BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs
elif ! MIX_ENV=e2e mix ecto.migrate; then
  echo "Running seed data for fresh database..."
  BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs
fi

unset NO_COLOR
cd e2e/playwright

# Bash 3 treats an empty array expansion as unbound under `set -u`.
if [ "${#EXTRA_ARGS[@]}" -eq 0 ]; then
  pnpm "$TEST_COMMAND"
else
  pnpm "$TEST_COMMAND" "${EXTRA_ARGS[@]}"
fi
