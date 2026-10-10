#!/usr/bin/env bash
# Checks that the shell tests `mix check` runs leave the repository alone when
# run from a Git hook. Git runs a hook in a linked worktree with GIT_DIR set to
# that worktree's git directory; on 10 Oct 2026 a test that built a scratch
# repository committed and pushed in the real one instead (main was replaced).
#
# Builds a decoy repository with its own origin and a linked worktree holding
# the tests, installs a pre-push hook that runs them, pushes a branch, and
# fails if the decoy's refs, HEADs, indexes or working trees changed, or if
# anything but the pushed branch reached its origin.
#
#   bash test/scripts/hook_env_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/hook-env-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

git_q() { git -c user.name=me -c user.email=me@example.com -c init.defaultBranch=main "$@"; }

git_q init -q --bare "$tmp/origin.git"
git_q clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
in_scratch "$tmp/main"
(cd "$tmp/main" && echo keep >keep.txt && git_q add . && git_q commit -qm keep && git_q push -q origin HEAD:main) || exit 1
git_q -C "$tmp/main" worktree add -q "$tmp/wt" -b feature 2>/dev/null || exit 1

# The worktree carries what the tests need from this repository.
mkdir -p "$tmp/wt/scripts" "$tmp/wt/.github"
cp -R "$root/test" "$tmp/wt/"
cp -R "$root/scripts/." "$tmp/wt/scripts/"
cp "$root/.github/known-flakes.txt" "$tmp/wt/.github/" 2>/dev/null
(cd "$tmp/wt" && git_q add . && git_q commit -qm feature) || exit 1

# Everything a stray git command could change in the decoy, local and remote.
state() {
  local dir
  for dir in "$tmp/main" "$tmp/wt"; do
    echo "== $dir"
    git -C "$dir" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags
    git -C "$dir" rev-parse HEAD
    git -C "$dir" ls-files -s | git hash-object --stdin
    git -C "$dir" status --porcelain
  done
  echo "== origin"
  git --git-dir="$tmp/origin.git" for-each-ref --format='%(refname) %(objectname)'
}

# The hook runs every other shell test and notes how each exited.
cat >"$tmp/main/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
cd "\$(git rev-parse --show-toplevel)" || exit 1
for t in test/scripts/*_test.sh; do
  case "\$t" in */hook_env_test.sh) continue ;; esac
  bash "\$t" >/dev/null 2>&1
  echo "\$(basename "\$t") \$?" >>"$tmp/statuses"
done
exit 0
HOOK
chmod +x "$tmp/main/.git/hooks/pre-push"

# What the push alone does: origin gains feature at the worktree's commit.
before="$(state)"
feature="$(git -C "$tmp/wt" rev-parse HEAD)"
(cd "$tmp/wt" && git_q push -q origin feature 2>/dev/null) || exit 1
expected_main="$(printf '%s\n' "$before" | sed -n '/^== origin$/,$p' | grep 'refs/heads/main')"

after="$(state)"
status=0
if [ "$(printf '%s\n' "$after" | sed '/^== origin$/q')" != "$(printf '%s\n' "$before" | sed '/^== origin$/q')" ]; then
  echo "hook_env_test: a test run from a pre-push hook changed the decoy repository:" >&2
  diff <(printf '%s\n' "$before" | sed '/^== origin$/q') <(printf '%s\n' "$after" | sed '/^== origin$/q') | sed 's/^/  /' >&2
  status=1
fi
origin_after="$(printf '%s\n' "$after" | sed -n '/^== origin$/,$p' | sed 1d | sort)"
origin_expected="$(printf 'refs/heads/feature %s\n%s' "$feature" "$expected_main" | sort)"
if [ "$origin_after" != "$origin_expected" ]; then
  echo "hook_env_test: a test run from a pre-push hook changed the decoy origin:" >&2
  diff <(echo "$origin_expected") <(echo "$origin_after") | sed 's/^/  /' >&2
  status=1
fi
[ -s "$tmp/statuses" ] || { echo "hook_env_test: the hook ran no tests" >&2; status=1; }

[ "$status" -eq 0 ] && echo "hook_env_test: ok ($(wc -l <"$tmp/statuses" | tr -d ' ') tests ran under the hook)"
exit "$status"
