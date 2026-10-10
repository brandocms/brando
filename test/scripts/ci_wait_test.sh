#!/usr/bin/env bash
# Checks how scripts/ci-wait reads failed jobs, against the trimmed job logs
# in test/scripts/ci_wait/ and a stub `gh` that serves them as one-job runs.
# Each case names the line ci-wait must print for the job. Needs bash and jq.
#
#   bash test/scripts/ci_wait_test.sh
#   CI_WAIT=<path> bash test/scripts/ci_wait_test.sh   # another ci-wait
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
fixtures="$root/test/scripts/ci_wait"
ci_wait="${CI_WAIT:-$root/scripts/ci-wait}"
stub="$(mktemp -d "${TMPDIR:-/tmp}/ci-wait-test.XXXXXX")"
trap 'rm -rf "$stub"' EXIT

cat >"$stub/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <path> …: the run's failed job (and CASE_PASSING, a passed one), its
# log, or its failed step.
[ "$1" = api ] || exit 1
case "$2" in
  */actions/runs/*/jobs*)
    jq -n --arg name "$CASE_JOB" --arg id "$CASE_ID" --arg passing "${CASE_PASSING:-}" '{jobs: ([{name: $name,
      html_url: "https://github.com/o/r/actions/runs/\($id)/job/\($id)",
      status: "completed", conclusion: "failure"}] + if $passing == "" then [] else [{name: $passing,
      html_url: "https://github.com/o/r/actions/runs/\($id)/job/0",
      status: "completed", conclusion: "success"}] end)}' ;;
  */actions/jobs/*/logs) cat "$CASE_LOG" ;;
  */actions/jobs/*) echo "Run Tests" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"

failures=0
id=0
# check <fixture> <expected job line> [locale]
check() {
  local fixture="$1" expected="$2" locale="${3:-}" output line out
  id=$((id + 1))
  output="$(env CASE_JOB="job" CASE_ID="$id" CASE_LOG="$fixtures/$fixture" PATH="$stub:$PATH" \
    ${locale:+LC_ALL="$locale"} "$ci_wait" --run "$id" --repo o/r 2>&1)"
  line="$(sed -n 2p <<<"$output")"
  if [ "$line" = "  job: $expected" ]; then
    echo "ok   $fixture${locale:+ ($locale)}"
  else
    failures=$((failures + 1))
    echo "FAIL $fixture${locale:+ ($locale)}"
    echo "     expected:   job: $expected"
    echo "     got:        ${line:-<nothing>}"
    while IFS= read -r out; do echo "     | $out"; done <<<"$output"
  fi
}

check jit-crash.log 'known flake: beam-jit-crash — rerun with: gh run rerun 1 --failed'
check presence-flake.log 'known flake: presence-shard-owner-exited — rerun with: gh run rerun 2 --failed'
check presence-flake-counted.log 'known flake: presence-shard-owner-exited — rerun with: gh run rerun 3 --failed'
# Real failures in logs whose noise holds both halves of the Presence pattern.
check warnings-abort.log 'real failure: Test suite aborted after successful execution due to warnings while using the --warnings-as-errors option (step: Run Tests)'
check setup-all.log 'real failure: BrandoAdmin.FooTest: failure on setup_all callback'
check compile-error.log 'real failure: ** (CompileError) test/brando/foo_test.exs:3: undefined function bar/0 (there is no such import) (step: Run Tests)'
check mixed.log 'real failure: test scheduled publishing posts to the Slack routes that send it (Brando.NotificationsTest); also known flake: presence-shard-owner-exited'
check unparsed.log 'real failure: 2 failing test(s) not found in the log; also known flake: presence-shard-owner-exited'
# The flaky Playwright test is dropped, the failed one kept, in any locale.
for locale in '' C C.UTF-8; do
  check playwright.log 'real failure: [Google Chrome] › tests/pages/breadcrumbs.spec.js:4:5 › pages have JSON-LD breadcrumbs' "$locale"
done

# The merge queue's record job may fail without failing the run (ci.yml), so
# a failure there is not reported.
id=$((id + 1))
output="$(env CASE_JOB="Record the tested tree for the merge queue" CASE_PASSING="mix test" CASE_ID="$id" \
  CASE_LOG=/dev/null PATH="$stub:$PATH" "$ci_wait" --run "$id" --repo o/r 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ "$output" = "Run $id: all 1 checks green" ]; then
  echo "ok   ignores the merge queue's record job"
else
  failures=$((failures + 1))
  echo "FAIL ignores the merge queue's record job"
  echo "     expected:   Run $id: all 1 checks green (exit 0)"
  echo "     got:        $output (exit $status)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
