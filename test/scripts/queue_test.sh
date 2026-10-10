#!/usr/bin/env bash
# Checks scripts/queue against a stub `gh` that plays each PR's merge-queue
# history from a list of states, and a local Git remote with a branch that
# conflicts with main. Each case names the lines and exit status queue must
# give. Needs bash, git and jq.
#
#   bash test/scripts/queue_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/queue-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# A checkout with the scripts and a remote, origin, where `conflicting` and
# main both change a.txt.
git_q() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
git_q init -q --bare "$tmp/origin.git"
git_q clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
(
  cd "$tmp/repo" || exit 1
  in_scratch "$tmp/repo"
  echo base >a.txt && echo base >b.txt && git_q add . && git_q commit -qm base
  git_q push -q origin HEAD:main
  git_q checkout -qb conflicting && echo theirs >a.txt && git_q commit -qam theirs
  git_q push -q origin conflicting
  git_q checkout -q main && echo ours >a.txt && git_q commit -qam ours && git_q push -q origin main
) || exit 1
mkdir -p "$tmp/repo/scripts" "$tmp/repo/.github"
cp "$root/scripts/queue" "$root/scripts/ci-wait" "$tmp/repo/scripts/"
cp "$root/.github/known-flakes.txt" "$tmp/repo/.github/"
logs="$root/test/scripts/ci_wait"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# State lives in $STATE: <pr>.base, <pr>.head, <pr>.sha, <pr>.queue (one
# "STATE ENTRY [REASON [COMMIT]]" per poll once queued, the last one
# repeating), <pr>.queued once enqueued, checks-<sha> (check runs JSON, one
# per poll, the last repeating), runs-<sha> (workflow runs JSON) and calls.
s="$STATE"
args=("$@")
filter=""
query=""
number=""
oid=""
paginate=false
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --jq) filter="${args[i + 1]}" ;;
    --paginate) paginate=true ;;
    -f|-F)
      case "${args[i + 1]}" in
        query=*) query="${args[i + 1]#query=}" ;;
        number=*) number="${args[i + 1]#number=}" ;;
        id=*) number="${args[i + 1]#id=PR_}" ;;
        oid=*) oid="${args[i + 1]#oid=}" ;;
      esac ;;
  esac
done

# next FILE — the file's current line, moving on to the next one per call.
next() {
  local pos total
  pos="$(cat "$1.pos" 2>/dev/null || echo 1)"
  total="$(wc -l <"$1" | tr -d ' ')"
  [ "$pos" -lt "$total" ] && echo $((pos + 1)) >"$1.pos"
  sed -n "${pos}p" "$1"
}

out() {
  if [ -n "$filter" ]; then jq -r "$filter"; else cat; fi
}

pr_json() {
  local n="$1" state=OPEN entry=null line reason commit
  if [ -f "$s/$n.queued" ]; then
    line="$(next "$s/$n.queue")"
    read -r state entry reason commit <<<"$line"
    [ "$entry" = - ] && entry=null || entry="{\"position\": 1, \"state\": \"$entry\"}"
    if [ -n "$reason" ] && [ ! -f "$s/$n.seen.$line" ]; then
      touch "$s/$n.seen.$line"
      echo "$reason ${commit:-}" >>"$s/$n.events"
    fi
  fi
  jq -n --arg id "PR_$n" --arg state "$state" --argjson entry "$entry" \
    --arg base "$(cat "$s/$n.base")" --arg head "$(cat "$s/$n.head")" --arg sha "$(cat "$s/$n.sha")" \
    --arg mergeable "$(cat "$s/$n.mergeable" 2>/dev/null || echo MERGEABLE)" \
    '{data: {repository: {pullRequest: {id: $id, state: $state, mergeable: $mergeable,
      baseRefName: $base, headRefName: $head, headRefOid: $sha, mergeQueueEntry: $entry}}}}'
}

case "$1 $2" in
  "api graphql")
    case "$query" in
      *enqueuePullRequest*)
        echo "enqueue $number${oid:+ $oid}" >>"$s/calls"
        touch "$s/$number.queued"
        echo '{"data": {"enqueuePullRequest": {"mergeQueueEntry": {"position": 1}}}}' | out ;;
      *dequeuePullRequest*)
        echo "dequeue $number" >>"$s/calls"
        echo '{"data": {}}' ;;
      *timelineItems*)
        count="$(wc -l <"$s/$number.events" 2>/dev/null | tr -d ' ')"
        read -r reason commit < <(tail -n 1 "$s/$number.events" 2>/dev/null)
        jq -n --argjson count "${count:-0}" --arg reason "${reason:-}" --arg commit "${commit:-}" \
          '{data: {repository: {pullRequest: {timelineItems: {filteredCount: $count, nodes:
            (if $count == 0 then [] else [{reason: $reason, actor: {login: "someone"},
              beforeCommit: (if $commit == "" then null else {oid: $commit} end)}] end)}}}}}' | out ;;
      *pullRequest*)
        [ -f "$s/$number.base" ] || { echo "Could not resolve to a PullRequest" >&2; exit 1; }
        pr_json "$number" | out ;;
    esac ;;
  "api repos/"*)
    case "$2" in
      */commits/*/check-runs*)
        sha="${2#*/commits/}" && sha="${sha%%/*}"
        # Someone pushes once the checks on this commit were read twice.
        echo x >>"$s/reads-$sha"
        if [ -f "$s/push-$sha" ] && [ "$(wc -l <"$s/reads-$sha")" -ge 2 ]; then
          read -r n new <"$s/push-$sha" && echo "$new" >"$s/$n.sha"
        fi
        # A line holding an array is several pages; without --paginate,
        # only the first.
        next "$s/checks-$sha" | jq -c --argjson all "$paginate" \
          'if type == "array" then (if $all then .[] else .[0] end) else . end' | out ;;
      */actions/runs\?head_sha=*) cat "$s/runs-${2#*head_sha=}" | out ;;
      */actions/runs/*/jobs*)
        id="${2#*/actions/runs/}" && id="${id%%/*}"
        jq -n --arg id "$id" '{jobs: [{name: "mix test", status: "completed", conclusion: "failure",
          html_url: "https://github.com/o/r/actions/runs/\($id)/job/\($id)"}]}' | out ;;
      */actions/jobs/*/logs) cat "$s/job.log" ;;
      */actions/jobs/*) echo "Run Tests" ;;
      *) exit 1 ;;
    esac ;;
  "pr edit")
    echo "edit $3 ${args[*]:3}" >>"$s/calls"
    echo main >"$s/$3.base" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

# pr N HEAD BASE SHA [QUEUE LINE]... — a PR, and its states once queued.
pr() {
  local n="$1"
  echo "$2" >"$state/$n.head"
  echo "$3" >"$state/$n.base"
  echo "$4" >"$state/$n.sha"
  shift 4
  printf '%s\n' "$@" >"$state/$n.queue"
}

# checks SHA JSON... — the check runs on a commit, one JSON per poll.
checks() {
  local sha="$1"
  shift
  printf '%s\n' "$@" >"$state/checks-$sha"
}

green='[{"name": "mix test", "status": "completed", "conclusion": "success", "html_url": "https://github.com/o/r/actions/runs/7/job/1"},
  {"name": "Coverage report", "status": "queued", "conclusion": null, "html_url": null},
  {"name": "Consumer", "status": "completed", "conclusion": "skipped", "html_url": "https://github.com/o/r/actions/runs/8/job/2"}]'
green="$(jq -c . <<<"$green")"
pending='{"check_runs": [{"name": "mix test", "status": "in_progress", "conclusion": null, "html_url": "x"}]}'
red='{"check_runs": [{"name": "mix test", "status": "completed", "conclusion": "failure", "html_url": "https://github.com/o/r/actions/runs/77/job/77"},
  {"name": "E2E", "status": "completed", "conclusion": "success", "html_url": "https://github.com/o/r/actions/runs/77/job/78"}]}'
red="$(jq -c . <<<"$red")"
green="{\"check_runs\": $green}"

failures=0
# run NAME EXPECTED_STATUS EXPECTED_OUTPUT ARGS... — runs queue on the
# current $state.
run() {
  local name="$1" want_status="$2" want="$3" got status
  shift 3
  got="$(cd "$tmp" && env PATH="$tmp/bin:$PATH" STATE="$state" QUEUE_INTERVAL=0.02 QUEUE_CONFIRM=0 \
    QUEUE_TIMEOUT=1 "$tmp/repo/scripts/queue" --repo o/r "$@" 2>&1)"
  status=$?
  if [ "$got" = "$want" ] && [ "$status" = "$want_status" ]; then
    echo "ok   $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name (exit $status, expected $want_status)"
    echo "     expected:"
    sed 's/^/     | /' <<<"$want"
    echo "     got:"
    sed 's/^/     | /' <<<"$got"
  fi
}

fresh() {
  state="$tmp/state-$1"
  mkdir -p "$state"
  cp "$logs/jit-crash.log" "$state/job.log"
}

fresh green
pr 1 feat-1 main aaaaaaa1 "OPEN QUEUED" "OPEN MERGEABLE" "OPEN - merged c1" "MERGED -"
checks aaaaaaa1 "$pending" "$green"
run "waits for green checks, queues, follows it to merged" 0 "PR 1: checks green on aaaaaaa; queued at position 1
PR 1: merged" 1

fresh red
pr 2 feat-2 main bbbbbbb2
checks bbbbbbb2 "$red"
pr 3 feat-3 feat-2 ccccccc3
checks ccccccc3 "$green"
run "explains failed checks, and holds back the PR stacked on it" 1 "PR 2: checks failed on bbbbbbb, not queued: mix test
  mix test: known flake: beam-jit-crash — rerun with: gh run rerun 77 --failed
PR 3: not queued: PR 2 did not merge" 2 3
[ ! -f "$state/calls" ] || { failures=$((failures + 1)); echo "FAIL     queued anyway: $(cat "$state/calls")"; }

fresh stack
pr 4 feat-4 main ddddddd4 "OPEN QUEUED" "MERGED - merged d4"
checks ddddddd4 "$green"
pr 5 feat-5 feat-4 eeeeeee5 "OPEN AWAITING_CHECKS" "MERGED - merged e5"
checks eeeeeee5 "$green"
run "queues a stacked PR after its base merges, retargeted to main" 0 "PR 4: checks green on ddddddd; queued at position 1
PR 4: merged
PR 5: PR 4 merged; retargeted to main
PR 5: checks green on eeeeeee; queued at position 1
PR 5: merged" 5 4
if [ "$(cat "$state/calls")" != "$(printf 'enqueue 4 ddddddd4\nedit 5 --base main --repo o/r\nenqueue 5 eeeeeee5')" ]; then
  failures=$((failures + 1))
  echo "FAIL     calls:"
  sed 's/^/     | /' "$state/calls"
fi

fresh conflict
pr 6 conflicting main fffffff6 "OPEN QUEUED" "OPEN UNMERGEABLE" "OPEN - merge_conflict"
checks fffffff6 "$green"
run "names the files in conflict when the queue drops it" 1 "PR 6: checks green on fffffff; queued at position 1
PR 6: dropped from the queue: conflicts with main in a.txt" 6

fresh push
pr 12 feat-12 main 5555555e "OPEN QUEUED" "MERGED - merged"
checks 5555555e "$green"
echo "12 6666666f" >"$state/push-5555555e"
checks 6666666f "$red"
run "checks a commit pushed after the checks passed before queueing it" 1 "PR 12: checks failed on 6666666, not queued: mix test
  mix test: known flake: beam-jit-crash — rerun with: gh run rerun 77 --failed" 12

fresh pages
pr 13 feat-13 main 7777777a
checks 7777777a "[$green, $red]"
run "reads every page of check runs" 1 "PR 13: checks failed on 7777777, not queued: mix test
  mix test: known flake: beam-jit-crash — rerun with: gh run rerun 77 --failed" 13

fresh merge-group
pr 7 feat-7 main 1111111a "OPEN AWAITING_CHECKS" "OPEN - failed_checks 9999999"
checks 1111111a "$green"
echo '{"workflow_runs": [{"id": 88, "conclusion": "failure"}, {"id": 89, "conclusion": "success"}]}' \
  >"$state/runs-9999999"
run "explains the failed merge-group checks" 1 "PR 7: checks green on 1111111; queued at position 1
PR 7: dropped from the queue: merge-group checks failed
  mix test: known flake: beam-jit-crash — rerun with: gh run rerun 88 --failed" 7

fresh already-queued
pr 8 feat-8 main 2222222b "OPEN LOCKED" "OPEN - manual"
touch "$state/8.queued"
run "follows a PR already in the queue, and says who dequeued it" 1 "PR 8: dequeued by someone" 8

fresh dequeue
pr 9 feat-9 main 3333333c "OPEN QUEUED"
touch "$state/9.queued"
run "dequeues a PR" 0 "PR 9: dequeued" --dequeue 9

fresh unknown
run "reports a PR it cannot read" 1 "PR 10: could not read it in o/r: Could not resolve to a PullRequest" 10

fresh unlisted-base
pr 11 feat-11 feat-x 4444444d
run "refuses a PR stacked on a branch that is not listed" 1 "PR 11: targets feat-x, not main; list the PR for feat-x too" 11

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
