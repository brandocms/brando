#!/usr/bin/env bash
# Checks that a branch cannot run its own code through Git on checkout, merge
# or rebase: scripts/install-git-helpers points Git at copies outside the tree.
# Controls with the configuration it replaced show the fixture branch does run
# code when Git is pointed at the tree. Also checks that the pre-push hook still
# runs from every worktree, also on a branch older than the hook, and that
# scripts/worktree-setup installs it only when the copies are missing, with stubs
# for its tools.
#
# Only scratch repositories, whose one remote is a local bare repository, with
# Git's global and system config shut out. Needs bash, git and python3.
#
#   bash test/scripts/git_helpers_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/git-helpers-test.XXXXXX")" || exit 1
tmp="$(cd "$tmp" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

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

# register_driver DIR SCRIPT PYTHON — the command --install would write for them.
register_driver() {
  (cd "$1" && python3 -I -c 'import runpy, subprocess, sys
command = runpy.run_path(sys.argv[1], run_name="driver")["driver_command"](sys.argv[2], sys.argv[3])
subprocess.run(["git", "config", "merge.gettext.driver", command], check=True)' "$root/scripts/gettext-merge-driver" "$2" "$3")
}

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

echo "-- a python3 on PATH that the tree's version manager could pick"
mkdir -p "$tmp/planted-bin"
printf '#!/bin/sh\necho "python3 on PATH" >>"%s"\nexit 0\n' "$marker" >"$tmp/planted-bin/python3"
chmod +x "$tmp/planted-bin/python3"
fresh "$tmp/planted"
(cd "$tmp/planted" && scripts/install-git-helpers) || fail "install before the planted python3"
git -C "$tmp/planted" checkout -q contributor
PATH="$tmp/planted-bin:$PATH" git -C "$tmp/planted" rebase -q origin/main >/dev/null 2>&1
no_branch_code "the driver does not run the python3 on PATH"
assert "the rebase still merges through the installed driver" merged_catalogue "$tmp/planted"

echo "-- a path that needs quoting"
odd="$tmp/odd dir's %O \$(echo path >>'$marker')"
fresh "$odd"
(cd "$odd" && scripts/install-git-helpers) || fail "install under an odd path"
odd_bin="$odd/.git/odd bin's %P"
mkdir -p "$odd_bin"
ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$odd_bin/python3"
register_driver "$odd" "$odd/.git/brando-hooks/gettext-merge-driver" "$odd_bin/python3" || fail "register an interpreter under an odd path"
git -C "$odd" checkout -q contributor
no_branch_code "checkout under an odd path"
git -C "$odd" rebase -q origin/main >/dev/null 2>&1
no_branch_code "rebase under an odd path"
assert "rebase under an odd path uses the installed driver" merged_catalogue "$odd"
# The tree is the contributor's now: its hook differs, its merge script and
# Python modules would write the marker if anything ran them.
cp "$odd/.git/brando-hooks/pre-push" "$tmp/odd-pre-push"
(cd "$odd" && scripts/install-git-helpers --if-missing) || fail "--if-missing under an odd path"
assert "--if-missing finds the copies under an odd path" cmp -s "$odd/.git/brando-hooks/pre-push" "$tmp/odd-pre-push"
no_branch_code "--if-missing runs nothing from the branch"

echo "-- the installed interpreter is gone"
gone_line="the installed copy or its Python interpreter is gone"
gone="$tmp/gone dir's %O"
fresh "$gone"
(cd "$gone" && scripts/install-git-helpers) || fail "install before the interpreter goes"
register_driver "$gone" "$gone/.git/brando-hooks/gettext-merge-driver" "$tmp/gone bin's %P/python3" || fail "register a dead interpreter"
out="$(git -C "$gone" merge --no-edit origin/contributor 2>&1)"
grep -q 'scripts/install-git-helpers' <<<"$out" && grep -q "$gone_line" <<<"$out" && ok "the merge says the driver is gone and what to run" ||
  fail "the merge says the driver is gone and what to run" "$out"
grep -q '^<<<<<<<' "$gone/$catalogue" && ok "the line merge still happens" || fail "the line merge still happens" "$out"
no_branch_code "the line merge runs nothing from the branch"
git -C "$gone" merge --abort
(cd "$gone" && scripts/install-git-helpers --if-missing) || fail "--if-missing with a dead interpreter"
case "$(git -C "$gone" config merge.gettext.driver)" in
  *"gone bin"*) fail "--if-missing replaces a dead interpreter" "$(git -C "$gone" config merge.gettext.driver)" ;;
  *) ok "--if-missing replaces a dead interpreter" ;;
esac
out="$(git -C "$gone" merge --no-edit origin/contributor 2>&1)" && ok "the merge succeeds after the repair" || fail "the merge succeeds after the repair" "$out"
assert "the config names a working interpreter again" merged_catalogue "$gone"
grep -q "$gone_line" <<<"$out" && fail "a working driver does not say it is gone" "$out" || ok "a working driver does not say it is gone"
no_branch_code "the repaired driver runs nothing from the branch"

echo "-- a python3 that does not run"
mkdir -p "$tmp/failing-bin"
printf '#!/bin/sh\nexit 1\n' >"$tmp/failing-bin/python3"
chmod +x "$tmp/failing-bin/python3"
fresh "$tmp/no-python"
(cd "$tmp/no-python" && scripts/install-git-helpers) || fail "install before python3 breaks"
no_python_copies="$tmp/no-python/.git/brando-hooks"
cp "$no_python_copies/pre-push" "$tmp/no-python-hook"
config_before="$(cat "$tmp/no-python/.git/config")"
echo "# changed in the tree" >>"$tmp/no-python/.githooks/pre-push"
for mode in "" --if-missing; do
  label="install-git-helpers ${mode:-without options}"
  if out="$(cd "$tmp/no-python" && PATH="$tmp/failing-bin:$PATH" scripts/install-git-helpers $mode 2>&1)"; then
    fail "$label stops" "$out"
  else
    ok "$label stops"
  fi
  grep -q 'python3' <<<"$out" && ok "$label says python3 does not run" || fail "$label says python3 does not run" "$out"
  assert "$label leaves the hook copy alone" cmp -s "$no_python_copies/pre-push" "$tmp/no-python-hook"
  [ "$(cat "$tmp/no-python/.git/config")" = "$config_before" ] && ok "$label leaves the config alone" || fail "$label leaves the config alone"
  cp "$tmp/no-python-hook" "$no_python_copies/pre-push"
done

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

echo "-- the pre-push hook on a branch older than --passed"
git -C "$tmp/safe" worktree add -q "$tmp/older-wt" -b older origin/main
cat >"$tmp/older-wt/scripts/check" <<CHECK
#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in
    --fast) ;;
    *) echo "check: unknown option \$arg" >&2; exit 2 ;;
  esac
done
echo ran >>"$check_calls"
CHECK
git -C "$tmp/older-wt" add scripts/check
git -C "$tmp/older-wt" commit -qm "a check without --passed"
: >"$check_calls"
out="$(git -C "$tmp/older-wt" push -q origin older:refs/heads/older-1 2>&1)" && ok "the first push succeeds" ||
  fail "the first push succeeds" "$out"
out="$(git -C "$tmp/older-wt" push -q origin older:refs/heads/older-2 2>&1)" && ok "the second push, with a recorded tree, succeeds" ||
  fail "the second push, with a recorded tree, succeeds" "$out"
[ "$(wc -l <"$check_calls" | tr -d ' ')" = 2 ] && ok "both pushes ran the branch's check" ||
  fail "both pushes ran the branch's check" "$(cat "$check_calls")"

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
# setup DIR — scripts/worktree-setup in DIR, with its tools stubbed.
setup() {
  mkdir -p "$1/assets" "$1/e2e/assets/backend" "$1/e2e/assets/frontend" "$1/e2e/playwright"
  (cd "$1" && env -u BRANDO_TEST_DATABASE_URL PATH="$tmp/bin:$PATH" scripts/worktree-setup 2>&1)
}
fresh "$tmp/new"
git -C "$tmp/new" worktree add -q "$tmp/new-wt" -b wt origin/main
if out="$(setup "$tmp/new-wt")"; then
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

echo "-- setup leaves the clone's copies alone"
git -C "$tmp/new" checkout -q main
new_copies="$tmp/new/.git/brando-hooks"
cp "$new_copies/pre-push" "$tmp/kept-pre-push"
cp "$new_copies/gettext-merge-driver" "$tmp/kept-driver"
echo "# from a stale branch" >>"$tmp/new-wt/.githooks/pre-push"
echo "# from a stale branch" >>"$tmp/new-wt/scripts/gettext-merge-driver"
config_before="$(cat "$tmp/new/.git/config")"
if out="$(setup "$tmp/new-wt")"; then ok "setup on a tree that changed the hook runs"; else fail "setup on a tree that changed the hook runs" "$out"; fi
assert "setup leaves the hook copy alone" cmp -s "$new_copies/pre-push" "$tmp/kept-pre-push"
assert "setup leaves the driver copy alone" cmp -s "$new_copies/gettext-merge-driver" "$tmp/kept-driver"
[ "$(cat "$tmp/new/.git/config")" = "$config_before" ] && ok "setup leaves the config alone" || fail "setup leaves the config alone"

(cd "$tmp/new-wt" && scripts/install-git-helpers) || fail "a plain install from that tree"
assert "a plain install takes the tree's hook" cmp -s "$tmp/new-wt/.githooks/pre-push" "$new_copies/pre-push"
assert "a plain install takes the tree's driver" cmp -s "$tmp/new-wt/scripts/gettext-merge-driver" "$new_copies/gettext-merge-driver"

rm "$new_copies/pre-push"
(cd "$tmp/new" && scripts/install-git-helpers --if-missing) || fail "--if-missing without the hook copy"
[ -x "$new_copies/pre-push" ] && ok "--if-missing restores a missing hook copy" || fail "--if-missing restores a missing hook copy"
rm "$new_copies/gettext-merge-driver"
(cd "$tmp/new" && scripts/install-git-helpers --if-missing) || fail "--if-missing without the driver copy"
[ -f "$new_copies/gettext-merge-driver" ] && ok "--if-missing restores a missing driver copy" || fail "--if-missing restores a missing driver copy"
git -C "$tmp/new" config merge.gettext.driver "$old_driver"
(cd "$tmp/new" && scripts/install-git-helpers --if-missing) || fail "--if-missing with the driver in the tree"
case "$(git -C "$tmp/new" config merge.gettext.driver)" in
  *"$new_copies/gettext-merge-driver"*) ok "--if-missing moves a driver in the tree to the copy" ;;
  *) fail "--if-missing moves a driver in the tree to the copy" "$(git -C "$tmp/new" config merge.gettext.driver)" ;;
esac

fresh "$tmp/old-setup"
git -C "$tmp/old-setup" config core.hooksPath .githooks
git -C "$tmp/old-setup" config merge.gettext.driver "$old_driver"
if out="$(setup "$tmp/old-setup")"; then ok "setup runs on a clone with the old configuration"; else fail "setup runs on a clone with the old configuration" "$out"; fi
[ "$(git -C "$tmp/old-setup" config core.hooksPath)" = "$tmp/old-setup/.git/brando-hooks" ] && [ -x "$tmp/old-setup/.git/brando-hooks/pre-push" ] &&
  ok "setup installs over the old configuration" || fail "setup installs over the old configuration"

echo "-- a first install while another setup holds the config lock"
# hold_config_lock DIR — takes the lock on DIR's config for about a second.
hold_config_lock() {
  : >"$1/.git/config.lock"
  (sleep 1; rm -f "$1/.git/config.lock") &
}
fresh "$tmp/locked"
hold_config_lock "$tmp/locked"
if out="$(cd "$tmp/locked" && scripts/install-git-helpers 2>&1)"; then ok "scripts/install-git-helpers waits for the lock"; else fail "scripts/install-git-helpers waits for the lock" "$out"; fi
wait
[ "$(git -C "$tmp/locked" config core.hooksPath)" = "$tmp/locked/.git/brando-hooks" ] && ok "core.hooksPath is set after the wait" ||
  fail "core.hooksPath is set after the wait"
fresh "$tmp/locked-driver"
hold_config_lock "$tmp/locked-driver"
if out="$(cd "$tmp/locked-driver" && python3 -I scripts/gettext-merge-driver --install 2>&1)"; then ok "the driver's --install waits for the lock"; else fail "the driver's --install waits for the lock" "$out"; fi
wait
case "$(git -C "$tmp/locked-driver" config merge.gettext.driver)" in
  *"$tmp/locked-driver/.git/brando-hooks/gettext-merge-driver"*) ok "the driver is registered after the wait" ;;
  *) fail "the driver is registered after the wait" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "git_helpers_test: $failures failure(s)" >&2
  exit 1
fi
echo "git_helpers_test: ok"
