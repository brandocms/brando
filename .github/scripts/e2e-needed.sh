#!/usr/bin/env bash
# Reads a pull request's changed paths, one per line, and prints "true" when
# the browser E2E suite should run for it, "false" when every path is one the
# suite cannot exercise: the repository's tooling and its tests, the unit
# tests (not the JavaScript ones or fixtures), guides, changelog fragments,
# agent docs and top-level Markdown.
# Prints "true" for no paths at all, since a failed lookup must not skip it.
#
#   git diff --name-only --no-renames BASE HEAD | bash .github/scripts/e2e-needed.sh
set -uo pipefail

# Paths the E2E jobs read themselves stay in: the workflow, its path check, the
# JavaScript tests its first shard runs and the fixtures a spec reads.
outside_e2e() {
  case "$1" in
    .github/workflows/ci.yml | .github/scripts/check-e2e-paths.sh | test/javascript/* | test/fixtures/*) return 1 ;;
    scripts/* | test/* | guides/* | changelog.d/* | .claude/* | .github/*) return 0 ;;
    */*) return 1 ;;
    *.md) return 0 ;;
    *) return 1 ;;
  esac
}

seen=false
while IFS= read -r path; do
  [ -n "$path" ] || continue
  seen=true
  outside_e2e "$path" || { echo true; exit 0; }
done

if [ "$seen" = true ]; then echo false; else echo true; fi
