#!/usr/bin/env bash
# Runs the E2E app's own ExUnit tests (test/unit) in MIX_ENV=test, without a
# browser, as CI does. Creates and migrates this worktree's E2E database, and
# seeds it when it is fresh: some tests read the E2E seeds (identity, SEO,
# users). Arguments go to `mix test`.
#
#   ./test_unit.sh
#   ./test_unit.sh test/unit/doctor_test.exs
set -euo pipefail

cd "$(dirname "$0")"
source .envrc
export MIX_ENV=test

mix do ecto.create --quiet + ecto.migrate --quiet
BRANDO_SEEDING=true mix run priv/repo/ensure_e2e_seeds.exs
mix test --warnings-as-errors ${1+"$@"}
