#!/usr/bin/env bash
# Checks scripts/changelog against fragments and changelogs in a scratch
# directory: which fragments `check` accepts, and what `collate` writes,
# including the PR numbers it reads from a scratch repository's merges.
#
#   bash test/scripts/changelog_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

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
printf -- '- x\n\n  ```elixir\n  code\n  ~~~\n' > "$fragments/a.fixes.md"
expect_check "a fence closed by the other fence character" 1 "a.fixes.md: a code fence is not closed"

fresh
printf -- '- x\n\n  ````markdown\n  ```\n  # Not a heading\n  ```\n  ````\n' > "$fragments/a.fixes.md"
expect_check "a longer fence holding a shorter one" 0 "1 fragment(s) valid"

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

# Headings in the changelog's code blocks are not its structure.
fresh
cat > "$changelog" <<'EOF'
## 0.55.0 (Unreleased)

### Upgrading

An example:

```markdown
#### Fixes
~~~
## Example
```

#### Fixes

- Old fix.
EOF
printf -- '- **X.** Fixed.\n' > "$fragments/a.fixes.md"
printf -- '- **Sec.** Secure.\n' > "$fragments/a.security.md"
run collate > /dev/null
expect_changelog "collate skips headings inside code blocks" <<'EOF'
## 0.55.0 (Unreleased)

### Upgrading

An example:

```markdown
#### Fixes
~~~
## Example
```

#### Fixes

- **X.** Fixed.

- Old fix.

#### Security

- **Sec.** Secure.
EOF

# PR links: collation adds a link to the pull request whose merge brought each
# fragment into the branch, at the end of an entry's line with none.
git_q() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
fresh
repo="$scratch/case"
(
  cd "$repo" || exit 1
  printf '## 0.55.0 (Unreleased)\n' > CHANGELOG.md
  git_q init -q && in_scratch "$repo" && git_q add . && git_q commit -qm base || exit 1

  git_q switch -qc feat-a
  cat > changelog.d/feat-a.fixes.md <<'EOF'
- The link goes before the full stop.

- No full stop

- Linked already ([#7](https://github.com/brandocms/brando/pull/7)).

- Numbered already (#8).

- Numbered with a list (#5, #6).

- A sentence that wraps its link
  onto the next line ([#9](https://github.com/brandocms/brando/pull/9)).

- A sentence that wraps
  without a link.

- A change the reader must act on.
  Replace `a` with `b`, a step without a link.

  ```markdown
  - A code block is not an entry.
  ```
EOF
  git_q add . && git_q commit -qm "Add a" || exit 1
  # A pull request merged into feat-a before feat-a merged: its merge does not
  # bring in the fragment, so it is not the one.
  git_q switch -qc sub && echo sub > sub.txt && git_q add . && git_q commit -qm sub || exit 1
  git_q switch -q feat-a && git_q merge -q --no-ff -m "Merge pull request #11 from o/sub" sub || exit 1
  git_q switch -q main && git_q merge -q --no-ff -m "Merge pull request #12 from o/feat-a" feat-a || exit 1

  # Merged locally into feat-d, which a pull request merged.
  git_q switch -qc feat-c
  printf -- '- From a branch merged locally first.\n' > changelog.d/feat-c.features.md
  git_q add . && git_q commit -qm "Add c" || exit 1
  git_q switch -qc feat-d main && echo d > d.txt && git_q add . && git_q commit -qm d || exit 1
  git_q merge -q --no-ff -m "Merge branch 'feat-c' into feat-d" feat-c || exit 1
  git_q switch -q main && git_q merge -q --no-ff -m "Merge pull request #14 from o/feat-d" feat-d || exit 1

  # Committed on main without a pull request, and not committed at all.
  printf -- '- Direct, no pull request.\n' > changelog.d/direct.fixes.md
  git_q add . && git_q commit -qm direct || exit 1
  printf -- '- Untracked, not committed.\n' > changelog.d/untracked.fixes.md
) || exit 1
output="$(run collate)"
status=$?
if [ "$status" -eq 0 ] && [ "$output" = "changelog: collated 4 fragment(s) into CHANGELOG.md
changelog: no pull request merged these yet, so their entries get no PR link: direct.fixes.md untracked.fixes.md" ]; then
  pass "collate names the fragments no pull request merged"
else
  fail "collate names the fragments no pull request merged" "got exit $status: $output"
fi
expect_changelog "collate adds a PR link to an entry's line without one" <<'EOF'
## 0.55.0 (Unreleased)

#### Features

- From a branch merged locally first ([#14](https://github.com/brandocms/brando/pull/14)).

#### Fixes

- Direct, no pull request.

- The link goes before the full stop ([#12](https://github.com/brandocms/brando/pull/12)).

- No full stop ([#12](https://github.com/brandocms/brando/pull/12))

- Linked already ([#7](https://github.com/brandocms/brando/pull/7)).

- Numbered already (#8).

- Numbered with a list (#5, #6).

- A sentence that wraps its link
  onto the next line ([#9](https://github.com/brandocms/brando/pull/9)).

- A sentence that wraps
  without a link ([#12](https://github.com/brandocms/brando/pull/12)).

- A change the reader must act on ([#12](https://github.com/brandocms/brando/pull/12)).
  Replace `a` with `b`, a step without a link.

  ```markdown
  - A code block is not an entry.
  ```

- Untracked, not committed.
EOF

# The repository's own fragments.
output="$("$script" check 2>&1)" && pass "changelog.d/ in this checkout" || fail "changelog.d/ in this checkout" "$output"

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
