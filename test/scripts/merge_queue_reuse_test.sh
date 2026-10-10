#!/usr/bin/env bash
# Checks when .github/scripts/merge-queue-reuse.sh lets a merge queue run reuse
# a pull_request run, against a stub `gh` that serves each case's API replies
# from a scratch directory. Needs bash and jq.
#
#   bash test/scripts/merge_queue_reuse_test.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/scripts/merge-queue-reuse.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/merge-queue-reuse-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"

cat >"$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <path>: the case's reply for that endpoint, or an API error when the
# case has none.
[ "$1" = api ] || exit 1
path="${2#repos/o/r/}"
case "$path" in
  git/commits/*) reply="commit-${path#git/commits/}" ;;
  rules/branches/*) reply="rules-${path#rules/branches/}" ;;
  actions/runs\?*) reply="runs" ;;
  actions/runs/*/artifacts\?*) reply="${path#actions/runs/}"; reply="artifacts-${reply%%/*}" ;;
  actions/runs/*/jobs\?*) reply="${path#actions/runs/}"; reply="jobs-${reply%%/*}" ;;
  *) exit 1 ;;
esac
[ -f "$CASE_DIR/$reply.json" ] || { echo "gh: HTTP 404 ($2)" >&2; exit 1; }
cat "$CASE_DIR/$reply.json"
EOF
chmod +x "$scratch/bin/gh"

tree=1111111111111111111111111111111111111111
main=2222222222222222222222222222222222222222
pr=3333333333333333333333333333333333333333
queued=4444444444444444444444444444444444444444
record="Record the tested tree for the merge queue"
required=("mix test (OTP 27.2 | Elixir 1.18.1)" "Admin CSS colour tokens")
case_dir=""

# commit SHA TREE PARENT…
commit() {
  local sha="$1" t="$2"
  shift 2
  jq -n --arg tree "$t" '{tree: {sha: $tree}, parents: [$ARGS.positional[] | {sha: .}]}' \
    --args "$@" > "$case_dir/commit-$sha.json"
}
# rules CONTEXT… — the required checks of main.
rules() {
  jq -n '[{type: "pull_request"},
    {type: "required_status_checks", parameters: {required_status_checks:
      [$ARGS.positional[] | {context: ., integration_id: 15368}]}}]' \
    --args "$@" > "$case_dir/rules-main.json"
}
# runs "ID PATH EVENT HEAD"… — the pull_request runs, newest first.
runs() {
  printf '%s\n' "$@" | jq -R 'split(" ") | {id: (.[0] | tonumber), path: .[1], event: .[2], head_sha: .[3]}' |
    jq -s '{total_count: length, workflow_runs: .}' > "$case_dir/runs.json"
}
# artifacts ID NAME…
artifacts() {
  local id="$1"
  shift
  jq -n '{artifacts: [$ARGS.positional[] | {name: ., expired: false}]}' --args "$@" \
    > "$case_dir/artifacts-$id.json"
}
# jobs ID "NAME=CONCLUSION"…
jobs() {
  local id="$1"
  shift
  printf '%s\n' "$@" | jq -R 'capture("^(?<name>.*)=(?<conclusion>[a-z]*)$")
    | .conclusion |= (if . == "" then null else . end)' |
    jq -s '{total_count: length, jobs: .}' > "$case_dir/jobs-$id.json"
}
passed_jobs() {
  jobs "$1" "${required[0]}=success" "${required[1]}=success" "E2E app unit tests=success" \
    "$record=success" "E2E (legacy-1)=failure"
}

# fresh: a queue commit alone on main whose tree run 10 passed on.
fresh() {
  case_dir="$scratch/case"
  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  commit "$queued" "$tree" "$main" "$pr"
  rules "${required[@]}"
  runs "10 .github/workflows/ci.yml pull_request $pr"
  artifacts 10 "merge-queue-$tree-$main" "e2e-artifacts-legacy-1"
  passed_jobs 10
}

failures=0
# expect REUSED LINE_PATTERN NAME — runs lookup on the queue commit; the line
# is stdout, where gh's own errors (stderr) do not go.
expect() {
  local reused="$1" pattern="$2" label="$3" output written
  : > "$scratch/output"
  output="$(env CASE_DIR="$case_dir" GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$scratch/output" \
    PATH="$scratch/bin:$PATH" "$script" lookup "$queued" refs/heads/main 2>"$scratch/stderr")"
  local status=$?
  written="$(cat "$scratch/output")"
  if [ "$status" -eq 0 ] && [ "$written" = "reused=$reused" ] &&
    [[ "$output" == "merge-queue-reuse: "$pattern ]]; then
    echo "ok   $label"
  else
    failures=$((failures + 1))
    echo "FAIL $label"
    echo "     expected: reused=$reused, merge-queue-reuse: $pattern (exit 0)"
    echo "     got:      ${written:-<no output>}, $output (exit $status)"
    sed 's/^/     | /' "$scratch/stderr"
  fi
}

fresh
expect true "reusing pull_request run 10, *" "reuses the passed run that tested the same tree on the same base"

fresh
runs "12 .github/workflows/ci.yml pull_request $pr" "10 .github/workflows/ci.yml pull_request $pr"
artifacts 12 "e2e-artifacts-legacy-1"
expect true "reusing pull_request run 10, *" "skips a newer run that recorded nothing for the older one that did"

fresh
artifacts 10 "merge-queue-$tree-5555555555555555555555555555555555555555"
expect false "running every job: no passed pull_request run *" "runs everything when main has moved since the PR's run"

fresh
artifacts 10 "merge-queue-6666666666666666666666666666666666666666-$main"
expect false "running every job: no passed pull_request run *" "runs everything when the PR's run tested another tree"

fresh
commit "$queued" "$tree" "7777777777777777777777777777777777777777" "$pr"
artifacts 10 "merge-queue-$tree-$main"
expect false "running every job: no passed pull_request run *" "runs everything for a PR queued behind another (its base is a queue commit)"

fresh
artifacts 10
expect false "running every job: no passed pull_request run *" "runs everything when the PR's run recorded nothing"

fresh
artifacts 10 "merge-queue-$tree-$main-extra" "x-merge-queue-$tree-$main"
expect false "running every job: no passed pull_request run *" "matches the artifact name exactly"

fresh
commit "$queued" "$tree" "$main"
expect false "running every job: * is not a merge of one pull request onto its base" "runs everything for a one-parent queue commit"

fresh
commit "$queued" "$tree" "$main" "$pr" "8888888888888888888888888888888888888888"
expect false "running every job: * is not a merge of one pull request onto its base" "runs everything for an octopus merge"

fresh
jobs 10 "${required[0]}=failure" "${required[1]}=success" "$record=success"
expect false "running every job: no passed pull_request run *" "runs everything when a required job failed in the latest attempt"

fresh
jobs 10 "${required[0]}=success" "${required[1]}=success" "$record=skipped"
expect false "running every job: no passed pull_request run *" "runs everything when the recording job did not succeed in the latest attempt"

fresh
jobs 10 "${required[0]}=success" "${required[1]}=success" "$record="
expect false "running every job: no passed pull_request run *" "runs everything while a re-run of the recording job is in progress"

fresh
jobs 10 "${required[0]}=success" "$record=success"
expect false "running every job: no passed pull_request run *" "runs everything when the run lacks a check the ruleset requires"

fresh
jobs 10 "${required[0]}=success" "${required[0]}=cancelled" "${required[1]}=success" "$record=success"
expect false "running every job: no passed pull_request run *" "runs everything when any job of a required name did not succeed"

fresh
passed_jobs 10
jq '.total_count = 150' "$case_dir/jobs-10.json" > "$case_dir/jobs.tmp" && mv "$case_dir/jobs.tmp" "$case_dir/jobs-10.json"
expect false "running every job: no passed pull_request run *" "runs everything when the jobs list is incomplete"

fresh
runs "10 .github/workflows/other.yml pull_request $pr"
expect false "running every job: no passed pull_request run *" "ignores runs of another workflow"

fresh
runs "10 .github/workflows/ci.yml push $pr"
expect false "running every job: no passed pull_request run *" "ignores runs of another event"

fresh
runs "10 .github/workflows/ci.yml pull_request 9999999999999999999999999999999999999999"
expect false "running every job: no passed pull_request run *" "ignores runs on another PR head"

fresh
rules
expect false "running every job: main requires no checks" "runs everything when the branch requires no checks"

fresh
rm "$case_dir/rules-main.json"
expect false "running every job: cannot read the required checks of main" "runs everything when the rulesets cannot be read"

fresh
rm "$case_dir/commit-$queued.json"
expect false "running every job: cannot read commit $queued" "runs everything when the queue commit cannot be read"

fresh
rm "$case_dir/runs.json"
expect false "running every job: cannot list the pull_request runs of $pr" "runs everything when the runs cannot be listed"

fresh
rm "$case_dir/artifacts-10.json"
expect false "running every job: cannot read the artifacts of run 10" "runs everything when the artifacts cannot be read"

fresh
rm "$case_dir/jobs-10.json"
expect false "running every job: cannot read the jobs of run 10" "runs everything when the jobs cannot be read"

# name: what a pull_request run records for its merge commit.
fresh
commit "$queued" "$tree" "$main" "$pr"
got="$(env CASE_DIR="$case_dir" GITHUB_REPOSITORY=o/r PATH="$scratch/bin:$PATH" "$script" name "$queued" 2>&1)"
if [ "$got" = "merge-queue-$tree-$main" ]; then
  echo "ok   names the record after the merge commit's tree and base"
else
  failures=$((failures + 1))
  echo "FAIL names the record after the merge commit's tree and base"
  echo "     got: $got"
fi
commit "$queued" "$tree" "$main"
if env CASE_DIR="$case_dir" GITHUB_REPOSITORY=o/r PATH="$scratch/bin:$PATH" "$script" name "$queued" > /dev/null 2>&1; then
  failures=$((failures + 1))
  echo "FAIL refuses to name the record for a commit that is not a two-parent merge"
else
  echo "ok   refuses to name the record for a commit that is not a two-parent merge"
fi

# ci.yml: the recording job carries the name the script looks for, needs
# exactly the jobs that skip their steps on a reused run, so none is skipped
# without having passed on the pull request, and checks their results itself
# (an implicit success() would also see the skipped reuse job and never run).
workflow="$root/.github/workflows/ci.yml"
gated="$(awk '/^  [a-z0-9_]+:$/ { job = substr($1, 1, length($1) - 1) }
  /^    needs: reuse$/ { print job }' "$workflow" | sort | tr '\n' ' ')"
recorded="$(awk '/^  record:$/ { in_record = 1; next } /^  [a-z0-9_]+:$/ { in_record = 0 }
  in_record && /^    needs: \[/ { gsub(/^    needs: \[|\]$/, ""); gsub(/, */, "\n"); print }' "$workflow" |
  sort | tr '\n' ' ')"
record_if="$(awk '/^  record:$/ { in_record = 1; next } /^  [a-z0-9_]+:$/ { in_record = 0 }
  in_record' "$workflow")"
if grep -qxF "    name: $record" "$workflow" && [ -n "$gated" ] && [ "$gated" = "$recorded" ] &&
  grep -qF '!cancelled()' <<<"$record_if" &&
  [ "$(grep -oE "!contains\(needs\.\*\.result, '(failure|cancelled|skipped)'\)" <<<"$record_if" | sort -u | wc -l)" -eq 3 ]; then
  echo "ok   ci.yml records the tree after every job a reused run skips"
else
  failures=$((failures + 1))
  echo "FAIL ci.yml records the tree after every job a reused run skips"
  echo "     jobs needing reuse: ${gated:-<none>}"
  echo "     record needs:       ${recorded:-<none>}"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
