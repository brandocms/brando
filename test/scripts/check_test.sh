#!/usr/bin/env bash
# Checks when scripts/check runs its Elixir gates and how it stops without
# deps, in a scratch repository with a stub `mix` and stubs for the bash
# gates. Each case names the line check must print, its exit status, and
# whether it ran mix. Needs bash and git.
#
#   bash test/scripts/check_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "$*" >>"$MIX_CALLS"\n' >"$tmp/bin/mix"
chmod +x "$tmp/bin/mix"

git_q() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }

failures=0
# scenario NAME — a fresh repository on a base commit, with the check script,
# stubs for its bash gates and a two-package mix.lock; the cases add the
# branch's changes and deps.
scenario() {
  repo="$tmp/$1"
  mkdir -p "$repo/scripts" "$repo/lib"
  cp "$root/scripts/check" "$repo/scripts/"
  # shellcheck disable=SC2013
  for gate in $(sed -n 's/^ *run_step "[^"]*" bash \([^ ]*\).*/\1/p' "$root/scripts/check"); do
    mkdir -p "$repo/$(dirname "$gate")"
    echo 'exit 0' >"$repo/$gate"
  done
  # Gates that run a script directly (`run_step "…" scripts/changelog check`).
  # shellcheck disable=SC2013
  for gate in $(sed -n 's/^ *run_step "[^"]*" \(scripts\/[^ ]*\).*/\1/p' "$root/scripts/check"); do
    mkdir -p "$repo/$(dirname "$gate")"
    printf '#!/bin/sh\nexit 0\n' >"$repo/$gate"
    chmod +x "$repo/$gate"
  done
  printf '%%{\n  "alpha": {:hex, :alpha, "1.0.0"},\n  "beta": {:hex, :beta, "1.0.0"},\n}\n' >"$repo/mix.lock"
  echo "# Brando" >"$repo/README.md"
  echo "defmodule A do end" >"$repo/lib/a.ex"
  (cd "$repo" && git_q init -q) || exit 1
  in_scratch "$repo"
  (cd "$repo" && git_q add . && git_q commit -qm base && git_q branch base) || exit 1
}

# change PATH... — the branch commits a change to each file.
change() {
  local file
  for file in "$@"; do
    mkdir -p "$repo/$(dirname "$file")"
    echo "change" >>"$repo/$file"
  done
  (cd "$repo" && git_q add . && git_q commit -qm change) || exit 1
}

deps() {
  local dep
  for dep in "$@"; do mkdir -p "$repo/deps/$dep"; done
}

# expect NAME STATUS LINE MIX(ran|skipped) ARGS... — runs the check.
expect() {
  local name="$1" want_status="$2" want_line="$3" want_mix="$4" got status mix=skipped
  shift 4
  rm -f "$tmp/mix_calls"
  got="$(cd "$repo" && env PATH="$tmp/bin:$PATH" MIX_CALLS="$tmp/mix_calls" CHECK_BASE="${base:-base}" \
    scripts/check "$@" 2>&1)"
  status=$?
  [ -s "$tmp/mix_calls" ] && mix=ran
  if [ "$status" = "$want_status" ] && grep -qxF -- "$want_line" <<<"$got" && [ "$mix" = "$want_mix" ]; then
    echo "ok   $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name (exit $status, expected $want_status; mix $mix, expected $want_mix)"
    echo "     expected line: $want_line"
    sed 's/^/     | /' <<<"$got"
  fi
}

skipped="check: Elixir gates skipped (--fast, and only Markdown no gate reads changed)"
no_deps="check: no deps/ in this worktree; run scripts/worktree-setup"

scenario docs-only
change CHANGELOG.md docs/guide.md .claude/skills/x/SKILL.md
echo "draft" >"$repo/NOTES.md"
expect "--fast skips the Elixir gates for Markdown no gate reads, without deps" 0 "$skipped" skipped --fast
expect "a full check still needs deps for the same change" 1 "$no_deps" skipped
base=missing expect "--fast without a base to compare with runs everything" 1 "$no_deps" skipped --fast

for file in README.md guides/blocks.md usage-rules.md usage-rules/seo.md lib/brando/notes.md mix.exs \
  scripts/ci-wait; do
  scenario "read-$(basename "$file")"
  change CHANGELOG.md "$file"
  expect "--fast runs the Elixir gates when $file changes" 1 "$no_deps" skipped --fast
done

scenario renamed-readme
(cd "$repo" && mkdir docs && git_q mv README.md docs/readme.md && git_q commit -qm move) || exit 1
expect "--fast runs the Elixir gates when README.md moves away" 1 "$no_deps" skipped --fast

scenario untracked
echo "x" >"$repo/lib/b.ex"
expect "an untracked Elixir file counts as a change" 1 "$no_deps" skipped --fast

scenario stale-deps
change lib/a.ex
deps alpha
expect "names the package missing from deps/" 1 \
  "check: deps/beta is missing (mix.lock is ahead of deps/); run scripts/worktree-setup" skipped --fast
deps beta
expect "runs the Elixir gates once deps/ has every package" 0 "check: all gates passed" ran --fast

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
