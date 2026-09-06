#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if git grep -nIE '/(private/tmp|tmp|Users|home)/' -- e2e/e2e/playwright/tests; then
  echo 'E2E specs contain machine-specific paths. Use testInfo.outputPath() for artifacts and repository-relative paths for fixtures.' >&2
  exit 1
fi
