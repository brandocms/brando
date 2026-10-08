#!/usr/bin/env bash
# Runs the E2E suite as N Playwright shards at once, each on its own instance:
# database, port, media directory and results directory. The suite itself
# stays on one worker per shard (see playwright.config.js), so a shard behaves
# exactly like a normal run.
#
#   ./test_e2e_parallel.sh 4 --reset            # whole suite, 4 shards
#   ./test_e2e_parallel.sh 3 --reset tests/blocks
#
# Each shard writes its log to tmp/e2e-shards/<n>.log and its Playwright
# results to playwright/test-results/shard-<n>.
set -uo pipefail

SHARDS="${1:?usage: test_e2e_parallel.sh <shards> [test_e2e.sh args...]}"
shift

case "$SHARDS" in
  ''|*[!0-9]*) echo "Shard count must be an integer" >&2; exit 1 ;;
esac

source .envrc
BASE_INSTANCE="$BRANDO_E2E_INSTANCE"
SHARD_DIR="$PWD/tmp/e2e-shards"
mkdir -p "$SHARD_DIR"

# Compile once up front so the shards don't all compile at the same time.
MIX_ENV=e2e mix compile --warnings-as-errors || exit 1

pids=()
ready_pids=()
trap 'kill ${ready_pids[@]+"${ready_pids[@]}"} 2>/dev/null || true' EXIT
for i in $(seq 1 "$SHARDS"); do
  # One line per shard when its server answers HTTP (see server_ready.sh).
  port="$(
    unset BRANDO_E2E_DATABASE BRANDO_E2E_PORT BRANDO_E2E_BASE_URL BRANDO_URL_PORT PORT
    export BRANDO_E2E_INSTANCE="${BASE_INSTANCE}_shard${i}"
    source .envrc
    echo "$BRANDO_E2E_PORT"
  )"
  ./server_ready.sh "$port" "(shard $i/$SHARDS)" &
  ready_pids+=($!)

  (
    # .envrc derives the database and port from the instance name.
    unset BRANDO_E2E_DATABASE BRANDO_E2E_PORT BRANDO_E2E_BASE_URL BRANDO_URL_PORT PORT
    export BRANDO_E2E_INSTANCE="${BASE_INSTANCE}_shard${i}"
    export BRANDO_E2E_MEDIA_PATH="$SHARD_DIR/$i/media"
    mkdir -p "$BRANDO_E2E_MEDIA_PATH"
    ./test_e2e.sh "$@" --shard="$i/$SHARDS" --output="test-results/shard-$i" > "$SHARD_DIR/$i.log" 2>&1
  ) &
  pids+=($!)
done

status=0
for i in $(seq 1 "$SHARDS"); do
  if wait "${pids[$((i - 1))]}"; then
    echo "shard $i/$SHARDS: passed"
  else
    status=1
    echo "shard $i/$SHARDS: FAILED (tmp/e2e-shards/$i.log)"
  fi
  grep -E "^\s+[0-9]+ (passed|failed|flaky|skipped)|^\s+\[Google Chrome\] ›" "$SHARD_DIR/$i.log" | sed "s/^/  [$i] /"
done

exit $status
