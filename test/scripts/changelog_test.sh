#!/usr/bin/env bash
# Checks scripts/changelog against fragments and changelogs in a scratch
# directory: which fragments `check` accepts, and what `collate` writes.
#
#   bash test/scripts/changelog_test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/scripts/changelog"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/changelog-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

failures=0
fragments=""
changelog=""

# fresh: an empty fragments directory and changelog for the next case.
fresh() {
  rm -rf "$scratch/case"
  mkdir -p "$scratch/case/changelog.d"
  fragments="$scratch/case/changelog.d"
  changelog="$scratch/case/CHANGELOG.md"
  : > "$changelog"
}

run() {
  CHANGELOG_FILE="$changelog" CHANGELOG_FRAGMENTS="$fragments" "$script" "$@" 2>&1
}

pass() { echo "ok   $1"; }
fail() {
  failures=$((failures + 1))
  echo "FAIL $1"
  shift
  local line
  for line in "$@"; do echo "     $line"; done
}

# expect_check <case> <exit status> <text the output must contain>
expect_check() {
  local name="$1" want_status="$2" want="$3" output status
  output="$(run check)"
  status=$?
  if [ "$status" -eq "$want_status" ] && grep -qF -- "$want" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exit $want_status and: $want" "got exit $status:" "$output"
  fi
}

# expect_changelog <case>: CHANGELOG matches stdin.
expect_changelog() {
  local name="$1" diff
  if diff="$(diff -u - "$changelog")"; then
    pass "$name"
  else
    fail "$name" "$diff"
  fi
}

fresh
rmdir "$fragments"
expect_check "no fragments directory" 0 "0 fragment(s) valid"

fresh
printf -- '- **One.** Fixed.\n' > "$fragments/a.fixes.md"
printf -- '- **Two.** Code:\n\n  ```elixir\n  # Before\n  ```\n' > "$fragments/wave8-x.y.breaking.md"
printf 'Not a fragment.\n' > "$fragments/README.md"
printf 'junk' > "$fragments/.DS_Store"
expect_check "valid fragments; README and dotfiles skipped" 0 "2 fragment(s) valid"

fresh
printf -- '- x\n' > "$fragments/a.fix.md"
expect_check "unknown section" 1 "a.fix.md: not named <name>.<section>.md"

fresh
printf -- '- x\n' > "$fragments/fixes.md"
expect_check "section without a name" 1 "fixes.md: not named"

fresh
printf -- '- x\n' > "$fragments/a.fixes.txt"
expect_check "not markdown" 1 "a.fixes.txt: not named"

fresh
printf -- '- x\n' > "$fragments/a b.fixes.md"
expect_check "space in the name" 1 "a b.fixes.md: not named"

fresh
printf '\n  \n' > "$fragments/a.fixes.md"
expect_check "blank fragment" 1 "a.fixes.md: empty"

fresh
printf 'Fixed a thing.\n' > "$fragments/a.fixes.md"
expect_check "not a list entry" 1 "a.fixes.md: the first line is not a list entry"

fresh
printf -- '- x\n\n#### Fixes\n' > "$fragments/a.fixes.md"
expect_check "heading" 1 "a.fixes.md:3: a heading"

fresh
printf -- '- x\n\n  ```elixir\n  # Before\n' > "$fragments/a.fixes.md"
expect_check "unclosed code fence" 1 "a.fixes.md: a code fence is not closed"

fresh
printf -- '- x\n' > "$fragments/a.fixes.md"
printf 'x\n' > "$fragments/b.fixes.md"
expect_check "summary counts the failing fragments" 1 "1 of 2 fragment(s) need fixing"

# Collation: name order at the top of the first heading of each section, a
# heading added for a missing section, fragments deleted.
fresh
cat > "$changelog" <<'EOF'
## 0.55.0 (Unreleased)

### Upgrading

Prose.

#### Breaking

- Old breaking.

#### Fixes
- Old fix.

#### Fixes

- Older fix, an earlier layer.

## 0.54.0

#### Fixes

- Released fix.
EOF
printf '\n- **B.** Second.\n  More.\n\n\n' > "$fragments/b-branch.fixes.md"
printf -- '- **A.** First.\n\n- **A2.** Also first.\n' > "$fragments/a-branch.fixes.md"
printf -- '- **Br.** Breaks.\n' > "$fragments/a-branch.breaking.md"
printf -- '- **Sec.** Secure.\n' > "$fragments/c.security.md"
printf -- '- **Dep.** Bumped.\n' > "$fragments/c.dependencies.md"
printf 'Kept.\n' > "$fragments/README.md"
output="$(run collate)"
status=$?
if [ "$status" -eq 0 ] && [ "$output" = "changelog: collated 5 fragment(s) into CHANGELOG.md" ]; then
  pass "collate reports"
else
  fail "collate reports" "got exit $status: $output"
fi
expect_changelog "collate into existing and missing sections" <<'EOF'
## 0.55.0 (Unreleased)

### Upgrading

Prose.

#### Breaking

- **Br.** Breaks.

- Old breaking.

#### Fixes

- **A.** First.

- **A2.** Also first.

- **B.** Second.
  More.

- Old fix.

#### Fixes

- Older fix, an earlier layer.

#### Dependencies

- **Dep.** Bumped.

#### Security

- **Sec.** Secure.

## 0.54.0

#### Fixes

- Released fix.
EOF
left="$(ls -A "$fragments")"
if [ "$left" = "README.md" ]; then pass "collate deletes the fragments"; else fail "collate deletes the fragments" "left: $left"; fi

fresh
printf '## 0.56.0 (Unreleased)\n' > "$changelog"
printf -- '- **F.** New.\n' > "$fragments/a.features.md"
printf -- '- **X.** Fixed.\n' > "$fragments/a.fixes.md"
run collate > /dev/null
expect_changelog "collate into a release with no headings yet" <<'EOF'
## 0.56.0 (Unreleased)

#### Features

- **F.** New.

#### Fixes

- **X.** Fixed.
EOF

fresh
printf '## 0.55.0\n\n#### Fixes\n\n- Released.\n' > "$changelog"
printf -- '- **X.** Fixed.\n' > "$fragments/a.fixes.md"
output="$(run collate)"
status=$?
if [ "$status" -eq 1 ] && grep -qF "is not an Unreleased release" <<<"$output" &&
  [ -f "$fragments/a.fixes.md" ] && [ "$(cat "$changelog")" = "$(printf '## 0.55.0\n\n#### Fixes\n\n- Released.')" ]; then
  pass "collate refuses a released top section and changes nothing"
else
  fail "collate refuses a released top section and changes nothing" "got exit $status: $output"
fi

fresh
printf '## 0.55.0 (Unreleased)\n' > "$changelog"
printf -- '- **X.** Fixed.\n' > "$fragments/a.fixes.md"
printf 'bad\n' > "$fragments/b.fixes.md"
output="$(run collate)"
status=$?
if [ "$status" -eq 1 ] && [ -f "$fragments/a.fixes.md" ] && [ "$(cat "$changelog")" = "## 0.55.0 (Unreleased)" ]; then
  pass "collate refuses an invalid fragment and changes nothing"
else
  fail "collate refuses an invalid fragment and changes nothing" "got exit $status: $output"
fi

fresh
printf '## 0.55.0 (Unreleased)\n' > "$changelog"
output="$(run collate)"
if [ "$output" = "changelog: no fragments to collate" ]; then pass "collate with no fragments"; else fail "collate with no fragments" "$output"; fi

# The repository's own fragments.
output="$("$script" check 2>&1)" && pass "changelog.d/ in this checkout" || fail "changelog.d/ in this checkout" "$output"

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
