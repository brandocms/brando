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

case "$BRANDO_E2E_DATABASE" in
  *[!a-zA-Z0-9_]*)
    echo "Invalid BRANDO_E2E_DATABASE: only letters, numbers, and underscores are allowed" >&2
    exit 1
    ;;
esac

case "$BRANDO_E2E_PORT" in
  ''|*[!0-9]*)
    echo "Invalid BRANDO_E2E_PORT: expected an integer" >&2
    exit 1
    ;;
esac

if [ "$BRANDO_E2E_PORT" -lt 1024 ] || [ "$BRANDO_E2E_PORT" -gt 65535 ]; then
  echo "Invalid BRANDO_E2E_PORT: expected a port between 1024 and 65535" >&2
  exit 1
fi

# A scripted run must never silently attach to a server from another worktree.
# Direct Playwright invocations retain their local reuse behavior.
export BRANDO_E2E_REUSE_SERVER=false

echo "E2E instance: $BRANDO_E2E_INSTANCE"
echo "E2E database: $BRANDO_E2E_DATABASE"
echo "E2E server: $BRANDO_E2E_BASE_URL"

# Check if database exists, create it if not, then ensure it's up to date
MIX_ENV=e2e mix do ecto.create, ecto.migrate

# Reset explicitly, otherwise seed only when the isolated database is fresh.
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
else
  BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/ensure_e2e_seeds.exs
fi

unset NO_COLOR
cd e2e/playwright

# Bash 3 treats an empty array expansion as unbound under `set -u`.
if [ "${#EXTRA_ARGS[@]}" -eq 0 ]; then
  pnpm "$TEST_COMMAND"
else
  pnpm "$TEST_COMMAND" "${EXTRA_ARGS[@]}"
fi
