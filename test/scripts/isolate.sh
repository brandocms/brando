# Sourced first by every shell test here. Git runs hooks (pre-push runs
# scripts/check, which runs these tests) with GIT_DIR, and in a linked
# worktree GIT_WORK_TREE or GIT_INDEX_FILE, pointing at the repository being
# pushed. A test that builds a scratch repository would then commit and push
# in that one: on 10 Oct 2026 one replaced main on GitHub. Clear them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_IMPLICIT_WORK_TREE

# in_scratch DIR — fails unless git in DIR resolves to DIR's own repository.
in_scratch() {
  [ "$(cd "$1" && git rev-parse --absolute-git-dir 2>/dev/null)" = "$(cd "$1/.git" 2>/dev/null && pwd -P)" ] || {
    echo "$(basename "$0"): $1 is not its own repository; refusing to write" >&2
    exit 1
  }
}
