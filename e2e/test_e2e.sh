#!/usr/bin/env bash
set -euo pipefail
source .envrc

# Default test command
TEST_COMMAND="test"
RESET_DB=false
CHECK_MIGRATIONS=false
EXTRA_ARGS=()

# Process arguments
for arg in "$@"; do
  if [ "$arg" = "--ui" ]; then
    TEST_COMMAND="test:ui"
  elif [ "$arg" = "--reset" ]; then
    RESET_DB=true
  elif [ "$arg" = "--check-migrations" ]; then
    RESET_DB=true
    CHECK_MIGRATIONS=true
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

# Compile, prepare the database and seed in one VM. Mix tracks compile_env
# changes itself; forcing compilation on every reset defeats incremental builds.
SETUP_ARGS=()
if [ "$RESET_DB" = true ]; then
  SETUP_ARGS+=(--reset)
fi
if [ "$CHECK_MIGRATIONS" = true ]; then
  SETUP_ARGS+=(--check-migrations)
fi

if [ "${#SETUP_ARGS[@]}" -eq 0 ]; then
  BRANDO_SEEDING=true MIX_ENV=e2e mix do compile --warnings-as-errors + run --no-start priv/repo/prepare_e2e.exs
else
  BRANDO_SEEDING=true MIX_ENV=e2e mix do compile --warnings-as-errors + run --no-start priv/repo/prepare_e2e.exs "${SETUP_ARGS[@]}"
fi

unset NO_COLOR

# Playwright starts the server; print one line when it answers HTTP. The app
# would print the same line, so silence that copy. A server already on the
# port is not ours: Playwright refuses it, so don't report it as ready.
export BRANDO_E2E_QUIET_READY=1
if ! curl -s -o /dev/null --max-time 2 "http://localhost:$BRANDO_E2E_PORT/"; then
  ./server_ready.sh "$BRANDO_E2E_PORT" &
  ready_pid=$!
  trap 'kill "$ready_pid" 2>/dev/null || true' EXIT
fi

cd playwright

# Bash 3 treats an empty array expansion as unbound under `set -u`.
if [ "${#EXTRA_ARGS[@]}" -eq 0 ]; then
  pnpm "$TEST_COMMAND"
else
  pnpm "$TEST_COMMAND" "${EXTRA_ARGS[@]}"
fi
