#!/usr/bin/env bash
# Checks that the shell tests `mix check` runs leave the repository alone when
# run from a Git hook. Git runs a hook in a linked worktree with GIT_DIR set to
# that worktree's git directory; on 10 Oct 2026 a test that built a scratch
# repository committed and pushed in the real one instead (main was replaced).
#
# Builds a decoy repository with its own origin and a linked worktree holding
# the tests, installs a pre-push hook that runs them, pushes a branch, and
# fails if anything but that branch reached the decoy origin.
#
#   bash test/scripts/hook_env_test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/hook-env-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

git_q() { git -c user.name=me -c user.email=me@example.com -c init.defaultBranch=main "$@"; }

git_q init -q --bare "$tmp/origin.git"
git_q clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
(cd "$tmp/main" && echo keep >keep.txt && git_q add . && git_q commit -qm keep && git_q push -q origin HEAD:main) || exit 1
git_q -C "$tmp/main" worktree add -q "$tmp/wt" -b feature 2>/dev/null || exit 1

# The worktree carries what the tests need from this repository.
mkdir -p "$tmp/wt/scripts" "$tmp/wt/.github"
cp -R "$root/test" "$tmp/wt/"
cp -R "$root/scripts/." "$tmp/wt/scripts/"
cp "$root/.github/known-flakes.txt" "$tmp/wt/.github/" 2>/dev/null

cat >"$tmp/main/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)" || exit 1
for t in test/scripts/*_test.sh; do
  case "$t" in */hook_env_test.sh) continue ;; esac
  bash "$t" >/dev/null 2>&1
done
exit 0
HOOK
chmod +x "$tmp/main/.git/hooks/pre-push"

(cd "$tmp/wt" && git_q add . && git_q commit -qm feature && git_q push -q origin feature 2>/dev/null) || exit 1

refs="$(git --git-dir="$tmp/origin.git" for-each-ref --format='%(refname:short) %(subject)' | sort)"
expected="$(printf 'feature feature\nmain keep')"
if [ "$refs" != "$expected" ]; then
  echo "hook_env_test: a test run from a pre-push hook changed the repository's origin:" >&2
  echo "$refs" | sed 's/^/  /' >&2
  exit 1
fi
echo "hook_env_test: ok"
