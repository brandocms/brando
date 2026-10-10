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
#     reused=false to $GITHUB_OUTPUT. It reuses only a run that
#       - is a pull_request run of .github/workflows/ci.yml on the PR head
#         merged by <sha> (its second parent),
#       - uploaded merge-queue-<tree>-<base> for <sha>'s own tree and first
#         parent: the PR was merged onto the same base, so it is alone in its
#         queue group and main has not moved since, and the workflow file,
#         being in the tree, is the same,
#       - and whose latest attempt has the recording job and every check the
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

# run_passed RUN_ID REQUIRED_JSON — succeeds when the run's latest attempt
# has the recording job and every required check concluded "success".
run_passed() {
  local jobs
  jobs="$(gh api "repos/$repo/actions/runs/$1/jobs?per_page=100")" || return 2
  jq -e --arg record "$record_job" --argjson required "$2" '
    .jobs as $jobs
    | (.total_count == ($jobs | length))
      and (($required + [$record]) | all(. as $name
        | [$jobs[] | select(.name == $name)]
        | length > 0 and all(.conclusion == "success")))
  ' <<<"$jobs" > /dev/null
}

lookup() {
  local sha="$1" branch="${2:-main}" info tree base head extra name required runs id count
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
      .workflow_runs[] | select(.path == $path and .event == "pull_request" and .head_sha == $head)
      | .id')" || decide false "running every job: cannot list the pull_request runs of $head"

  for id in $runs; do
    count="$(gh api "repos/$repo/actions/runs/$id/artifacts?name=$name" |
      jq --arg name "$name" '[.artifacts[] | select(.name == $name)] | length')" ||
      decide false "running every job: cannot read the artifacts of run $id"
    [ "$count" -gt 0 ] || continue
    run_passed "$id" "$required"
    case $? in
      0) decide true "reusing pull_request run $id, which passed on the same tree ($tree, base $base): https://github.com/$repo/actions/runs/$id" ;;
      2) decide false "running every job: cannot read the jobs of run $id" ;;
    esac
  done
  decide false "running every job: no passed pull_request run of $workflow tested tree $tree on base $base"
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
