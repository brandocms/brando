#!/usr/bin/env bash
# Checks when scripts/check runs its Elixir and tooling gates, how it stops
# without deps, and when the pre-push hook skips the gates after a passing
# push, in a scratch repository with a stub `mix` and stubs for the bash
# gates. Each case names the line check must print, its exit status, and
# whether it ran mix; some also name the tooling tests that ran. Needs bash
# and git.
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
  mkdir -p "$repo/scripts" "$repo/lib" "$repo/.githooks"
  cp "$root/scripts/check" "$repo/scripts/"
  cp "$root/.githooks/pre-push" "$repo/.githooks/"
  # Each gate's stub notes its path in GATE_CALLS.
  # shellcheck disable=SC2013
  for gate in $(sed -nE 's/^ *(run|tooling)_step "[^"]*" ("[^"]*" )?bash ([^ ]*).*/\3/p' "$root/scripts/check"); do
    mkdir -p "$repo/$(dirname "$gate")"
    printf 'echo %s >>"$GATE_CALLS"\nexit 0\n' "$gate" >"$repo/$gate"
  done
  # Gates that run a script directly (`run_step "…" scripts/changelog check`).
  # shellcheck disable=SC2013
  for gate in $(sed -n 's/^ *run_step "[^"]*" \(scripts\/[^ ]*\).*/\1/p' "$root/scripts/check"); do
    mkdir -p "$repo/$(dirname "$gate")"
    printf '#!/bin/sh\necho %s >>"$GATE_CALLS"\nexit 0\n' "$gate" >"$repo/$gate"
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

# judge NAME STATUS LINE MIX(ran|skipped) — compares the last run's output
# ($got, $status) with the expected.
judge() {
  local name="$1" want_status="$2" want_line="$3" want_mix="$4" mix=skipped
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

# expect NAME STATUS LINE MIX(ran|skipped) ARGS... — runs the check.
expect() {
  local name="$1" want_status="$2" want_line="$3" want_mix="$4"
  shift 4
  rm -f "$tmp/mix_calls" "$tmp/gate_calls"
  got="$(cd "$repo" && env PATH="$tmp/bin:$PATH" MIX_CALLS="$tmp/mix_calls" GATE_CALLS="$tmp/gate_calls" \
    CHECK_BASE="${base:-base}" scripts/check "$@" 2>&1)"
  status=$?
  judge "$name" "$want_status" "$want_line" "$want_mix"
}

# expect_push NAME STATUS LINE MIX(ran|skipped) — pushes HEAD to origin
# through the pre-push hook, with SKIP_CHECK from the environment.
expect_push() {
  local name="$1" want_status="$2" want_line="$3" want_mix="$4"
  rm -f "$tmp/mix_calls" "$tmp/gate_calls"
  got="$(cd "$repo" && export PATH="$tmp/bin:$PATH" MIX_CALLS="$tmp/mix_calls" GATE_CALLS="$tmp/gate_calls" \
    CHECK_BASE=base && git_q -c core.hooksPath=.githooks push -q -f origin HEAD:refs/heads/feature 2>&1)"
  status=$?
  judge "$name" "$want_status" "$want_line" "$want_mix"
}

# expect_tooling NAME TESTS... — the tooling tests (test/scripts/*_test.sh)
# the last run ran, by name without _test.sh, are exactly TESTS.
expect_tooling() {
  local name="$1" ran want
  shift
  ran="$(sed -n 's|^test/scripts/\(.*\)_test\.sh$|\1|p' "$tmp/gate_calls" 2>/dev/null | sort | tr '\n' ' ')"
  want="$(printf '%s\n' "$@" | sed '/^$/d' | sort | tr '\n' ' ')"
  if [ "$ran" = "$want" ]; then
    echo "ok   $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name"
    echo "     ran:      ${ran:-<none>}"
    echo "     expected: ${want:-<none>}"
  fi
}

# gate_ran GATE — the last run ran the gate at path GATE.
gate_ran() { grep -qxF "$1" "$tmp/gate_calls" 2>/dev/null; }

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

# Tooling gates run when the branch or working tree changes a file they
# exercise.
all_tooling="ci_wait merge_queue_reuse changelog release_version queue hook_env check"
scenario lib-only
change lib/a.ex
deps alpha beta
expect "a lib/ change skips the tooling gates" 0 \
  "check: ci-wait flake matching       skipped (no tooling changes)" ran --fast
expect_tooling "  … and runs none of them"
if gate_ran scripts/changelog && gate_ran scripts/release-version && gate_ran .github/scripts/check_css_colors.sh; then
  echo "ok     … but still the changelog, release version and CSS gates"
else
  failures=$((failures + 1))
  echo "FAIL   … but still the changelog, release version and CSS gates"
  sed 's/^/     | /' "$tmp/gate_calls" 2>/dev/null
fi

scenario ci-wait
change scripts/ci-wait
deps alpha beta
expect "a scripts/ci-wait change runs the gates that exercise it" 0 \
  "check: changelog script             skipped (no tooling changes)" ran --fast
expect_tooling "  … which are these" ci_wait merge_queue_reuse queue hook_env

scenario hook-change
change .githooks/pre-push
deps alpha beta
expect "a pre-push hook change runs the check gate selection test" 0 "check: all gates passed" ran --fast
expect_tooling "  … and the hook safety test" check hook_env

scenario untracked-fixture
deps alpha beta
mkdir -p "$repo/test/scripts/ci_wait"
echo "log" >"$repo/test/scripts/ci_wait/new.log"
expect "an untracked tooling fixture counts as a change" 0 "check: all gates passed" ran --fast
expect_tooling "  … for the tests that read it" ci_wait queue hook_env

scenario no-base
change lib/a.ex
deps alpha beta
base=missing expect "without a base to compare with every tooling gate runs" 0 "check: all gates passed" ran --fast
# shellcheck disable=SC2086
expect_tooling "  … all of them" $all_tooling

# The pre-push hook remembers the tree the gates last passed on, per
# worktree, and runs only the changelog check while just changelog
# fragments and unread Markdown change after it.
skipped_all="check: gates skipped (since they last passed, only changelog fragments and Markdown no gate reads changed)"
scenario push
main="$repo"
git_q init -q --bare "$tmp/push-origin.git"
(cd "$main" && git_q remote add origin "$tmp/push-origin.git" && git_q worktree add -q "$tmp/push-wt" -b feature) || exit 1
repo="$tmp/push-wt"
marker="$main/.git/worktrees/push-wt/brando-check-passed"
change lib/a.ex
deps alpha beta
expect_push "a first push runs the gates" 0 "check: all gates passed" ran
if [ "$(cat "$marker" 2>/dev/null)" = "$(git -C "$repo" rev-parse "HEAD^{tree}")" ]; then
  echo "ok     … and records the tree in the worktree's git directory"
else
  failures=$((failures + 1))
  echo "FAIL   … and records the tree in the worktree's git directory ($marker: $(cat "$marker" 2>/dev/null))"
fi

change changelog.d/feature.fixes.md docs/notes.md CHANGELOG.md
expect_push "a push changing only fragments and unread Markdown skips the gates" 0 "$skipped_all" skipped
if gate_ran scripts/changelog && ! gate_ran .github/scripts/check_css_colors.sh; then
  echo "ok     … but runs the changelog check"
else
  failures=$((failures + 1))
  echo "FAIL   … but runs the changelog check"
  sed 's/^/     | /' "$tmp/gate_calls" 2>/dev/null
fi
change changelog.d/feature.fixes.md
expect_push "  … again after a skipped push" 0 "$skipped_all" skipped

# kept NAME — the record still holds $recorded.
kept() {
  if [ "$(cat "$marker" 2>/dev/null)" = "$recorded" ]; then
    echo "ok   $1"
  else
    failures=$((failures + 1))
    echo "FAIL $1"
  fi
}

recorded="$(cat "$marker")"
change changelog.d/feature.fixes.md
echo "draft" >"$repo/notes.md"
expect_push "an untracked file, even unread Markdown, runs the gates" 0 "check: all gates passed" ran
kept "  … and records nothing"
rm "$repo/notes.md"
change README.md
expect_push "a change to Markdown a gate reads runs the gates" 0 "check: all gates passed" ran
recorded="$(cat "$marker")"
change changelog.d/feature.fixes.md
SKIP_CHECK=1 expect_push "SKIP_CHECK=1 runs nothing" 0 "" skipped
kept "  … and keeps the tree recorded before"
change lib/a.ex
expect_push "a lib/ change after a passing push runs the gates" 0 "check: all gates passed" ran

echo "not a tree" >"$marker"
change changelog.d/feature.fixes.md
expect_push "an unreadable record runs the gates" 0 "check: all gates passed" ran

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
