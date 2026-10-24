#!/usr/bin/env bash
# Checks which changed paths make .github/scripts/e2e-needed.sh run the E2E
# suite. Needs bash.
#
#   bash test/scripts/e2e_needed_test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0

# expect WANT NAME PATH... — the script's answer for those changed paths.
expect() {
  local want="$1" name="$2" got
  shift 2
  got="$(printf '%s\n' "$@" | bash "$root/.github/scripts/e2e-needed.sh")"
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name: expected $want, got $got"
  fi
}

expect false "tooling and its tests" scripts/queue test/scripts/queue_test.sh
expect false "unit tests" test/brando_admin/live/video_picker_upload_test.exs
expect false "docs, changelog and agent docs" guides/videos.md changelog.d/x.fixes.md AGENTS.md .claude/skills/brando-e2e/SKILL.md
expect false "other GitHub files" .github/known-flakes.txt .github/workflows/igniter-smoke.yml .github/scripts/merge-queue-reuse.sh
expect true "library code" scripts/queue lib/brando/videos.ex
expect true "assets" assets/src/hooks/UploadTrigger/index.js
expect true "the E2E app" e2e/playwright/tests/projects/video-picker-upload.spec.js
expect true "Markdown below the top level" scripts/queue priv/templates/brando.install/README.md
expect true "the workflow that runs it" .github/workflows/ci.yml
expect true "its path check" .github/scripts/check-e2e-paths.sh
expect true "the JavaScript tests its first shard runs" test/javascript/tiptap/editor.spec.js
expect true "… and the node ones" test/javascript/upload-progress.test.mjs
expect true "a fixture an E2E spec reads" test/fixtures/definitions/hero.exs.txt
expect true "dependencies" mix.lock
expect true "no paths (a failed lookup)"

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
