#!/usr/bin/env bash
# Lets a merge queue run of ci.yml reuse the pull_request run that already
# tested the same tree, instead of running every job again.
#
#   merge-queue-reuse.sh name <sha>
#     Prints the artifact name a pull_request run uploads once every gated job
#     passed: merge-queue-<tree>-<base>, from <sha> (the run's github.sha, the
#     merge of the PR head onto its base that the jobs checked out).
#
#   merge-queue-reuse.sh lookup <sha> [<base branch>]
#     For a merge_group commit <sha>: prints one line saying whether a
#     pull_request run already passed on this tree, and writes reused=true or
#     reused=false to $GITHUB_OUTPUT. Of the pull_request runs of
#     .github/workflows/ci.yml on the PR head merged by <sha> (its second
#     parent), it takes the newest whose required checks have all finished,
#     and reuses it only if it
#       - uploaded merge-queue-<tree>-<base> for <sha>'s own tree and first
#         parent: the PR was merged onto the same base, so it is alone in its
#         queue group and main has not moved since, and the workflow file,
#         being in the tree, is the same,
#       - and its latest attempt has the recording job and every check the
#         base branch's rulesets require concluded "success".
#     Anything else, an API error included, prints why and writes
#     reused=false. It exits 0 either way.
#
# Needs gh (GH_TOKEN with actions: read), jq and GITHUB_REPOSITORY.
set -uo pipefail

workflow=".github/workflows/ci.yml"
# The ci.yml job that uploads the artifact after the gated jobs succeeded.
record_job="Record the tested tree for the merge queue"

repo="${GITHUB_REPOSITORY:-}"
[ -n "$repo" ] || { echo "merge-queue-reuse: GITHUB_REPOSITORY is not set" >&2; exit 2; }

# commit_info SHA — prints "<tree> <parent>…".
commit_info() {
  gh api "repos/$repo/git/commits/$1" | jq -r '[.tree.sha] + [.parents[].sha] | join(" ")'
}

# decide true|false LINE — writes the output and prints the line.
decide() {
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "reused=$1" >> "$GITHUB_OUTPUT"
  echo "merge-queue-reuse: $2"
  exit 0
}

# run_state RUN_ID REQUIRED_JSON — prints the state of the run's latest
# attempt: running (a required check has not finished, or is missing),
# passed (every required check and the recording job concluded "success"),
# failed (anything else) or incomplete (the jobs list is cut short).
run_state() {
  gh api "repos/$repo/actions/runs/$1/jobs?per_page=100" |
    jq -r --arg record "$record_job" --argjson required "$2" '
      .jobs as $jobs
      | def named($name): [$jobs[] | select(.name == $name)];
      if .total_count != ($jobs | length) then "incomplete"
      elif ($required | all(named(.) | length > 0 and all(.status == "completed")) | not) then "running"
      elif ($required + [$record]) | all(named(.) | length > 0 and all(.conclusion == "success"))
      then "passed"
      else "failed" end'
}

lookup() {
  local sha="$1" branch="${2:-main}" info tree base head extra name required runs id state count
  branch="${branch#refs/heads/}"

  info="$(commit_info "$sha")" || decide false "running every job: cannot read commit $sha"
  read -r tree base head extra <<<"$info"
  if [ -z "$head" ] || [ -n "$extra" ]; then
    decide false "running every job: $sha is not a merge of one pull request onto its base"
  fi
  name="merge-queue-$tree-$base"

  required="$(gh api "repos/$repo/rules/branches/$branch" | jq -c '
    [.[] | select(.type == "required_status_checks")
      | .parameters.required_status_checks[].context] | unique')" ||
    decide false "running every job: cannot read the required checks of $branch"
  [ "$required" != "[]" ] || decide false "running every job: $branch requires no checks"

  runs="$(gh api "repos/$repo/actions/runs?event=pull_request&head_sha=$head&per_page=100" |
    jq -r --arg path "$workflow" --arg head "$head" '
      [.workflow_runs[] | select(.path == $path and .event == "pull_request" and .head_sha == $head)]
      | sort_by(.id) | reverse | .[].id')" ||
    decide false "running every job: cannot list the pull_request runs of $head"

  # The newest run whose required checks have finished decides: an older pass
  # does not outweigh a newer failure on the same head.
  for id in $runs; do
    state="$(run_state "$id" "$required")" || decide false "running every job: cannot read the jobs of run $id"
    case "$state" in
      running) continue ;;
      incomplete) decide false "running every job: cannot read every job of run $id" ;;
      passed)
        count="$(gh api "repos/$repo/actions/runs/$id/artifacts?name=$name" |
          jq --arg name "$name" '[.artifacts[] | select(.name == $name)] | length')" ||
          decide false "running every job: cannot read the artifacts of run $id"
        if [ "$count" -gt 0 ]; then
          decide true "reusing pull_request run $id, which passed on the same tree ($tree, base $base): https://github.com/$repo/actions/runs/$id"
        fi
        ;;
    esac
    decide false "running every job: the newest finished pull_request run $id on $head did not pass and record tree $tree on base $base"
  done
  decide false "running every job: no pull_request run of $workflow on $head has finished its required checks"
}

case "${1:-}" in
  name)
    [ $# -eq 2 ] || { echo "usage: merge-queue-reuse.sh name <sha>" >&2; exit 2; }
    info="$(commit_info "$2")" || exit 1
    read -r tree base head extra <<<"$info"
    if [ -z "$head" ] || [ -n "$extra" ]; then
      echo "merge-queue-reuse: $2 is not a merge of one pull request onto its base" >&2
      exit 1
    fi
    echo "merge-queue-$tree-$base"
    ;;
  lookup)
    [ $# -ge 2 ] && [ $# -le 3 ] || { echo "usage: merge-queue-reuse.sh lookup <sha> [<base branch>]" >&2; exit 2; }
    lookup "$2" "${3:-}"
    ;;
  *)
    echo "usage: merge-queue-reuse.sh name <sha> | lookup <sha> [<base branch>]" >&2
    exit 2
    ;;
esac
