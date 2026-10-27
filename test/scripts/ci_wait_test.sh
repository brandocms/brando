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

# The live list, plus retired entries the fixtures below still use
cat "$root/.github/known-flakes.txt" "$fixtures/retired-flakes.txt" >"$stub/known-flakes.txt"
export CI_WAIT_FLAKES="$stub/known-flakes.txt"

cat >"$stub/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <path> …: the run's failed job (and CASE_PASSING, a passed one, and
# CASE_RUNNING, one still running), its log, its failed step (CASE_STEP,
# default Run Tests) or the run's status (the next line of CASE_STATUS).
# gh pr checks: the next line of CASE_CHECKS. gh run rerun: noted in
# CASE_CALLS, and refused, as GitHub does, while the run is not completed.
# A file's last line repeats. With CASE_OLD_GH set it is a gh without
# --allow-escape-sequences, which refuses the flag.
if [ -n "${CASE_OLD_GH:-}" ]; then
  for arg in "$@"; do
    [ "$arg" = --allow-escape-sequences ] && { echo "unknown flag: $arg" >&2; exit 1; }
  done
fi
if [ "$1 $2" = "api --help" ]; then
  echo "  -X, --method string"
  [ -n "${CASE_OLD_GH:-}" ] || echo "      --allow-escape-sequences   Allow printing terminal escape sequences"
  exit 0
fi
next() {
  local pos total
  pos="$(cat "$1.pos" 2>/dev/null || echo 1)"
  total="$(wc -l <"$1" | tr -d ' ')"
  [ "$pos" -lt "$total" ] && echo $((pos + 1)) >"$1.pos"
  sed -n "${pos}p" "$1"
}
case "$1 $2" in
  "pr checks") next "$CASE_CHECKS"; exit ;;
  "run rerun")
    if [ "$(cat "$CASE_STATUS.now" 2>/dev/null)" != completed ]; then
      echo "run $3 cannot be rerun; This workflow is already running" >&2
      exit 1
    fi
    echo "rerun $3" >>"$CASE_CALLS"
    exit ;;
esac
[ "$1" = api ] || exit 1
case "$2" in
  */actions/runs/*/jobs*)
    jq -n --arg name "$CASE_JOB" --arg id "$CASE_ID" --arg passing "${CASE_PASSING:-}" \
      --arg running "${CASE_RUNNING:-}" '{jobs: ([{name: $name,
      html_url: "https://github.com/o/r/actions/runs/\($id)/job/\($id)",
      status: "completed", conclusion: "failure"}] + if $passing == "" then [] else [{name: $passing,
      html_url: "https://github.com/o/r/actions/runs/\($id)/job/0",
      status: "completed", conclusion: "success"}] end + if $running == "" then [] else [{name: $running,
      html_url: "https://github.com/o/r/actions/runs/\($id)/job/1",
      status: "in_progress", conclusion: null}] end)}' ;;
  */actions/runs/*) next "$CASE_STATUS" | tee "$CASE_STATUS.now" ;;
  */actions/jobs/*/logs) cat "$CASE_LOG" ;;
  */actions/jobs/*) echo "${CASE_STEP:-Run Tests}" ;;
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
    CASE_STEP="${CASE_STEP:-}" CASE_RUNNING="${CASE_RUNNING:-}" CASE_OLD_GH="${CASE_OLD_GH:-}" \
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

# A job that failed setting up never ran the change's tests: CI
# infrastructure, whatever its log holds and with no log to read.
CASE_STEP="Initialize containers" check initialize-containers.log \
  'CI infrastructure: failed in Initialize containers — rerun with: gh run rerun 12 --failed'
CASE_STEP="Set up job" check missing.log \
  'CI infrastructure: failed in Set up job — rerun with: gh run rerun 13 --failed'
# A failed job is explained while other jobs of its run still run.
CASE_RUNNING="E2E (legacy-1)" check jit-crash.log 'known flake: beam-jit-crash — rerun with: gh run rerun 14 --failed'
# A gh without --allow-escape-sequences (2.88) still reads the log.
CASE_OLD_GH=1 check jit-crash.log 'known flake: beam-jit-crash — rerun with: gh run rerun 15 --failed'
# Hex timing out in Install dependencies: a known flake, not a real failure.
CASE_STEP="Install dependencies" check hex-registry-timeout.log \
  'known flake: hex-registry-timeout — rerun with: gh run rerun 16 --failed'

# expect <name> <status> <output> <command>... — the command's whole output
# and exit status.
expect() {
  local name="$1" want_status="$2" want="$3" got status
  shift 3
  got="$("$@" 2>&1)"
  status=$?
  if [ "$status" -eq "$want_status" ] && [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name"
    echo "     expected (exit $want_status):"
    sed 's/^/     | /' <<<"$want"
    echo "     got (exit $status):"
    sed 's/^/     | /' <<<"$got"
  fi
}

id=$((id + 1))
expect "says the run is still running" 1 "Run $id: still running; FAILED so far: job — https://github.com/o/r/actions/runs/$id
  job: real failure: ** (CompileError) test/brando/foo_test.exs:3: undefined function bar/0 (there is no such import) (step: Run Tests)" \
  env CASE_JOB=job CASE_ID="$id" CASE_RUNNING="E2E (legacy-1)" CASE_LOG="$fixtures/compile-error.log" \
  PATH="$stub:$PATH" "$ci_wait" --run "$id" --repo o/r

id=$((id + 1))
expect "names CI infrastructure in the verdict" 1 "Run $id: FAILED (CI infrastructure only): job — https://github.com/o/r/actions/runs/$id
  job: CI infrastructure: failed in Initialize containers — rerun with: gh run rerun $id --failed" \
  env CASE_JOB=job CASE_ID="$id" CASE_STEP="Initialize containers" CASE_LOG="$fixtures/initialize-containers.log" \
  PATH="$stub:$PATH" "$ci_wait" --run "$id" --repo o/r

# The merge queue's record job may fail without failing the run (ci.yml), so
# a failure there is not reported.
id=$((id + 1))
expect "ignores the merge queue's record job" 0 "Run $id: all 1 checks green" \
  env CASE_JOB="Record the tested tree for the merge queue" CASE_PASSING="mix test" CASE_ID="$id" \
  CASE_LOG=/dev/null PATH="$stub:$PATH" "$ci_wait" --run "$id" --repo o/r

# --rerun-flakes reruns a job that failed setting up once its run has
# finished (GitHub refuses before), then waits for the rerun.
infra='{"name": "E2E (legacy-4)", "bucket": "fail", "link": "https://github.com/o/r/actions/runs/40/job/41"}'
passed='{"name": "mix test", "bucket": "pass", "link": "https://github.com/o/r/actions/runs/40/job/42"}'
printf '%s\n' "[$infra, $passed]" "[$infra, $passed]" "[$infra, $passed]" \
  '[{"name": "E2E (legacy-4)", "bucket": "pending", "link": null}, '"$passed]" \
  "[${infra/fail/pass}, $passed]" >"$stub/checks"
printf '%s\n' in_progress completed >"$stub/status"
expect "reruns a job that failed setting up once its run finished" 0 "PR 5: CI infrastructure only (Initialize containers in E2E (legacy-4)); reran the failed jobs once, still waiting
PR 5: all 2 checks green" \
  env CASE_CHECKS="$stub/checks" CASE_STATUS="$stub/status" CASE_CALLS="$stub/calls" \
  CASE_STEP="Initialize containers" CASE_LOG="$fixtures/initialize-containers.log" \
  CI_WAIT_INTERVAL=0 CI_WAIT_CONFIRM=0 CI_WAIT_TIMEOUT=1 PATH="$stub:$PATH" \
  "$ci_wait" 5 --repo o/r --rerun-flakes
if [ "$(cat "$stub/calls" 2>/dev/null)" != "rerun 40" ]; then
  failures=$((failures + 1))
  echo "FAIL     reruns: $(cat "$stub/calls" 2>/dev/null)"
fi

# The assistant entry matches its assertion's diagnostic, not a later step
# that fails with the same page on screen
check assistant-proposal-flake.log "known flake: assistant-text-block-proposal — rerun with: gh run rerun $((id + 1)) --failed"
check assistant-proposal-real.log 'real failure: test a message produces a reviewed proposal that one click applies (BrandoAdmin.AssistantLiveTest)'

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
