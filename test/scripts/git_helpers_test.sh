#!/usr/bin/env bash
# Checks that a branch cannot run its own code through Git on checkout, merge
# or rebase: scripts/install-git-helpers points Git at copies outside the tree.
# Controls with the configuration it replaced show the fixture branch does run
# code when Git is pointed at the tree. Also checks that the pre-push hook still
# runs from every worktree and that scripts/worktree-setup installs it, with
# stubs for its tools.
#
# Only scratch repositories, whose one remote is a local bare repository, with
# Git's global and system config shut out. Needs bash, git and python3.
#
#   bash test/scripts/git_helpers_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/git-helpers-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

tmp="$(cd "$tmp" && pwd -P)"
export HOME="$tmp/home" GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --file "$GIT_CONFIG_GLOBAL" user.name me
git config --file "$GIT_CONFIG_GLOBAL" user.email me@example.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

marker="$tmp/branch-code-ran"
check_calls="$tmp/check_calls"
catalogue=priv/gettext/no/LC_MESSAGES/default.po
failures=0

ok() { echo "ok   $1"; }
fail() {
  failures=$((failures + 1))
  echo "FAIL $1"
  [ $# -lt 2 ] || sed 's/^/     | /' <<<"$2"
}
# assert NAME COMMAND... — the command succeeds.
assert() {
  local name="$1"
  shift
  if "$@"; then ok "$name"; else fail "$name"; fi
}

# no_branch_code NAME — nothing from the branch has run since the last check.
no_branch_code() {
  if [ -e "$marker" ]; then
    fail "$1" "$(cat "$marker")"
    rm -f "$marker"
  else
    ok "$1"
  fi
}
# branch_code NAME — the control: the branch's code did run.
branch_code() {
  if [ -e "$marker" ]; then
    ok "$1"
    rm -f "$marker"
  else
    fail "$1"
  fi
}

po_head() {
  printf 'msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Language: no\\n"\n"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n'
}
po_entry() { printf '\n#, elixir-autogen, elixir-format\nmsgid "%s"\nmsgstr "%s"\n' "$1" "$1"; }

# Both messages in the catalogue, no conflict markers: the real driver merged.
merged_catalogue() {
  grep -q 'msgid "Contributor"' "$1/$catalogue" && grep -q 'msgid "Maintainer"' "$1/$catalogue" &&
    ! grep -q '^<<<<<<<' "$1/$catalogue"
}

# The base commit, main with a change to the catalogue, and the contributor's
# branch: a hook for each thing Git could run, and a merge script and Python
# modules of its own.
git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
in_scratch "$tmp/seed"
(
  cd "$tmp/seed" || exit 1
  mkdir -p scripts .githooks e2e "$(dirname "$catalogue")"
  cp "$root/scripts/install-git-helpers" "$root/scripts/gettext-merge-driver" "$root/scripts/worktree-setup" scripts/
  cp "$root/.githooks/pre-push" .githooks/
  cp "$root/.gitattributes" .
  cp "$root/e2e/.envrc" e2e/
  # The hook's gate: notes its arguments and what the hook left in GIT_DIR.
  printf '#!/bin/sh\necho "$* GIT_DIR=${GIT_DIR:-}" >>"%s"\n' "$check_calls" >scripts/check
  chmod +x scripts/check
  { po_head; po_entry Base; } >"$catalogue"
  git add -A && git commit -qm base && git push -q origin HEAD:main

  git switch -q -c contributor
  for hook in post-checkout post-merge post-rewrite post-commit pre-commit pre-merge-commit \
    prepare-commit-msg commit-msg pre-rebase pre-auto-gc reference-transaction pre-push; do
    printf '#!/bin/sh\necho "hook %s" >>"%s"\n' "$hook" "$marker" >".githooks/$hook"
    chmod +x ".githooks/$hook"
  done
  # Python, as the driver commands run it.
  printf 'open("%s", "a").write("merge script\\n")\n' "$marker" >scripts/gettext-merge-driver
  for module in re shlex tempfile; do
    printf 'open("%s", "a").write("python module %s\\n")\n' "$marker" "$module" >"$module.py"
    cp "$module.py" "$(dirname "$catalogue")/"
  done
  # Its own commit: a rebase then replays the catalogue change on a tree that
  # already holds the branch's merge script.
  git add -A && git commit -qm tooling
  po_entry Contributor >>"$catalogue"
  git add -A
  # A subject Git passes on to the driver as a label.
  git commit -qm "Translate \$(echo subject >>'$marker')"
  git push -q origin HEAD:contributor

  git switch -q main
  po_entry Maintainer >>"$catalogue"
  git add -A && git commit -qm maintainer && git push -q origin HEAD:main
) || exit 1

# fresh DIR — a clone, on main, with only the origin above to reach.
fresh() {
  git clone -q -b main "$tmp/origin.git" "$1" 2>/dev/null || exit 1
  in_scratch "$1"
}

# The configuration earlier versions of scripts/worktree-setup wrote.
old_driver="sh -c 'test -f scripts/gettext-merge-driver || exec git merge-file --marker-size=\"\$3\" -L \"\$6\" -L \"\$5\" -L \"\$7\" \"\$1\" \"\$0\" \"\$2\"; exec python3 scripts/gettext-merge-driver \"\$0\" \"\$@\"' %O %A %B %L %P %S %X %Y"

echo "-- controls: Git pointed at the tree"
fresh "$tmp/old"
git -C "$tmp/old" config core.hooksPath .githooks
git -C "$tmp/old" checkout -q contributor
branch_code "core.hooksPath .githooks: the branch's post-checkout hook runs on checkout"
git -C "$tmp/old" checkout -q main
rm -f "$marker"
git -C "$tmp/old" merge -q --no-edit origin/contributor >/dev/null 2>&1
branch_code "core.hooksPath .githooks: its post-merge hook runs on merge"

fresh "$tmp/old-driver"
git -C "$tmp/old-driver" config merge.gettext.driver "$old_driver"
git -C "$tmp/old-driver" checkout -q contributor
git -C "$tmp/old-driver" rebase -q origin/main >/dev/null 2>&1
branch_code "the tree-relative driver: the branch's merge script runs on rebase"

echo "-- a clone whose setup has not been rerun keeps working"
fresh "$tmp/not-rerun"
git -C "$tmp/not-rerun" config core.hooksPath .githooks
git -C "$tmp/not-rerun" config merge.gettext.driver "$old_driver"
git -C "$tmp/not-rerun" switch -q -c topic HEAD~1
po_entry Topic >>"$tmp/not-rerun/$catalogue"
git -C "$tmp/not-rerun" add -A
git -C "$tmp/not-rerun" commit -qm topic
if git -C "$tmp/not-rerun" rebase -q main >/dev/null 2>&1 && grep -q 'msgid "Maintainer"' "$tmp/not-rerun/$catalogue" &&
  grep -q 'msgid "Topic"' "$tmp/not-rerun/$catalogue"; then
  ok "the old driver command still merges catalogues through this tree's script"
else
  fail "the old driver command still merges catalogues through this tree's script"
fi
: >"$check_calls"
git -C "$tmp/not-rerun" push -q origin HEAD:refs/heads/not-rerun 2>/dev/null
grep -q -- '--fast' "$check_calls" && ok "the tracked pre-push hook still runs" || fail "the tracked pre-push hook still runs"

echo "-- installed"
fresh "$tmp/safe"
(cd "$tmp/safe" && scripts/install-git-helpers) || fail "scripts/install-git-helpers"
copies="$tmp/safe/.git/brando-hooks"
[ "$(git -C "$tmp/safe" config core.hooksPath)" = "$copies" ] && ok "core.hooksPath is absolute and outside the tree" ||
  fail "core.hooksPath is absolute and outside the tree" "$(git -C "$tmp/safe" config core.hooksPath)"
case "$(git -C "$tmp/safe" config merge.gettext.driver)" in
  *"$copies/gettext-merge-driver"*scripts/gettext-merge-driver* | *" scripts/gettext-merge-driver"*)
    fail "the driver names only the copy" "$(git -C "$tmp/safe" config merge.gettext.driver)" ;;
  *"$copies/gettext-merge-driver"*) ok "the driver names only the copy" ;;
  *) fail "the driver names only the copy" "$(git -C "$tmp/safe" config merge.gettext.driver)" ;;
esac
[ "$(cd "$copies" && find . -type f | sort | tr '\n' ' ')" = "./gettext-merge-driver ./pre-push " ] &&
  ok "the only files there are the hook and the driver" || fail "the only files there are the hook and the driver" "$(ls -a "$copies")"
[ -x "$copies/pre-push" ] && ok "the hook copy is executable" || fail "the hook copy is executable"
[ -z "$(git -C "$tmp/safe" status --porcelain)" ] && ok "the tree stays clean" || fail "the tree stays clean"
config_before="$(cat "$tmp/safe/.git/config")"
(cd "$tmp/safe" && scripts/install-git-helpers) || fail "rerunning scripts/install-git-helpers"
[ "$(cat "$tmp/safe/.git/config")" = "$config_before" ] && ok "a rerun changes nothing" || fail "a rerun changes nothing"

echo "-- a contributor's branch in an installed clone"
git -C "$tmp/safe" fetch -q origin
no_branch_code "fetch runs nothing from the branch"
git -C "$tmp/safe" checkout -q contributor
no_branch_code "checkout runs nothing from the branch"
assert "the copies are untouched by the checkout" cmp -s "$copies/pre-push" "$root/.githooks/pre-push"
git -C "$tmp/safe" checkout -q main
no_branch_code "checking out main again runs nothing from the branch"
if git -C "$tmp/safe" merge -q --no-edit origin/contributor >/dev/null 2>&1; then ok "merge succeeds"; else fail "merge succeeds"; fi
no_branch_code "merge runs nothing from the branch"
assert "merge uses the installed driver" merged_catalogue "$tmp/safe"

git -C "$tmp/safe" reset -q --hard origin/main
git -C "$tmp/safe" checkout -q contributor
if git -C "$tmp/safe" rebase -q origin/main >/dev/null 2>&1; then ok "rebase succeeds"; else fail "rebase succeeds"; fi
no_branch_code "rebase runs nothing from the branch"
assert "rebase uses the installed driver" merged_catalogue "$tmp/safe"
git -C "$tmp/safe" switch -q main

git -C "$tmp/safe" worktree add -q "$tmp/safe-wt" origin/contributor
no_branch_code "worktree add of the branch runs nothing from it"
git -C "$tmp/safe-wt" rebase -q origin/main >/dev/null 2>&1
no_branch_code "rebase in a linked worktree runs nothing from the branch"
assert "the linked worktree uses the installed driver" merged_catalogue "$tmp/safe-wt"

echo "-- a path that needs quoting"
odd="$tmp/odd dir's %O \$(echo path >>'$marker')"
fresh "$odd"
(cd "$odd" && scripts/install-git-helpers) || fail "install under an odd path"
git -C "$odd" checkout -q contributor
no_branch_code "checkout under an odd path"
git -C "$odd" rebase -q origin/main >/dev/null 2>&1
no_branch_code "rebase under an odd path"
assert "rebase under an odd path uses the installed driver" merged_catalogue "$odd"

echo "-- the pre-push hook"
git -C "$tmp/safe" worktree add -q "$tmp/push-wt" -b feature origin/main
echo change >"$tmp/push-wt/change.txt"
git -C "$tmp/push-wt" add change.txt
git -C "$tmp/push-wt" commit -qm change
: >"$check_calls"
git -C "$tmp/push-wt" push -q origin feature 2>/dev/null || fail "push from a linked worktree"
[ "$(cat "$check_calls")" = "--fast GIT_DIR=" ] && ok "a push from a linked worktree runs the check, without GIT_DIR" ||
  fail "a push from a linked worktree runs the check, without GIT_DIR" "$(cat "$check_calls")"
: >"$check_calls"
SKIP_CHECK=1 git -C "$tmp/push-wt" push -q origin feature:refs/heads/skipped 2>/dev/null
[ ! -s "$check_calls" ] && ok "SKIP_CHECK=1 skips it" || fail "SKIP_CHECK=1 skips it"
git -C "$tmp/safe-wt" push -q origin HEAD:refs/heads/from-branch 2>/dev/null
no_branch_code "a push from the branch runs the installed hook, not the branch's"

echo "-- rerunning takes the tree's version"
echo "# updated" >>"$tmp/push-wt/.githooks/pre-push"
(cd "$tmp/push-wt" && scripts/install-git-helpers) || fail "install from a linked worktree"
assert "the copy has the tree's change" cmp -s "$tmp/push-wt/.githooks/pre-push" "$copies/pre-push"

echo "-- upgrading a clone set up before the copies"
(cd "$tmp/old" && git reset -q --hard origin/main && scripts/install-git-helpers) || fail "install over the old configuration"
[ "$(git -C "$tmp/old" config core.hooksPath)" = "$tmp/old/.git/brando-hooks" ] && ok "core.hooksPath moves to the copies" ||
  fail "core.hooksPath moves to the copies"
git -C "$tmp/old" checkout -q contributor
no_branch_code "the upgraded clone runs nothing from the branch"

echo "-- a fresh scripts/worktree-setup"
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/mix"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/npx"
printf '#!/bin/sh\n[ "$1" = exec ] && shift && [ "$1" = -- ] && shift\nexec "$@"\n' >"$tmp/bin/mise"
chmod +x "$tmp/bin/mix" "$tmp/bin/npx" "$tmp/bin/mise"
fresh "$tmp/new"
git -C "$tmp/new" worktree add -q "$tmp/new-wt" -b wt origin/main
mkdir -p "$tmp/new-wt/assets" "$tmp/new-wt/e2e/assets/backend" "$tmp/new-wt/e2e/assets/frontend" "$tmp/new-wt/e2e/playwright"
if out="$(cd "$tmp/new-wt" && env -u BRANDO_TEST_DATABASE_URL PATH="$tmp/bin:$PATH" scripts/worktree-setup 2>&1)"; then
  ok "setup runs in a linked worktree"
else
  fail "setup runs in a linked worktree" "$out"
fi
[ "$(git -C "$tmp/new" config core.hooksPath)" = "$tmp/new/.git/brando-hooks" ] && ok "setup points core.hooksPath at the copies" ||
  fail "setup points core.hooksPath at the copies" "$(git -C "$tmp/new" config core.hooksPath)"
[ -x "$tmp/new/.git/brando-hooks/pre-push" ] && [ -f "$tmp/new/.git/brando-hooks/gettext-merge-driver" ] &&
  ok "setup installs the hook and the driver" || fail "setup installs the hook and the driver"
: >"$check_calls"
echo change >"$tmp/new-wt/change.txt"
git -C "$tmp/new-wt" add change.txt
git -C "$tmp/new-wt" commit -qm change
git -C "$tmp/new-wt" push -q origin wt 2>/dev/null
grep -q -- '--fast' "$check_calls" && ok "after setup a push runs the hook" || fail "after setup a push runs the hook"
git -C "$tmp/new" checkout -q contributor
no_branch_code "after setup a checkout runs nothing from the branch"

if [ "$failures" -gt 0 ]; then
  echo "git_helpers_test: $failures failure(s)" >&2
  exit 1
fi
echo "git_helpers_test: ok"
