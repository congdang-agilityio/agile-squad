#!/usr/bin/env bash
# release.sh: deploy entry gate, release notes and post-release bookkeeping for a milestone.
#
# Usage:
#   release.sh gate <milestone>      JSON: ok + reasons. Every issue in the milestone is Done or
#                                    Released (epics and stories may be open), no open P0/P1
#                                    bug (nor an open bug missing from the board) in the repo,
#                                    latest CI run on main succeeded.
#   release.sh notes <milestone>     Markdown release notes from the merged PRs that closed the
#                                    milestone's issues, grouped by PR title type.
#   release.sh draft <milestone> <sha>
#                                    Create (or update) the draft GitHub Release <tag> on <sha>
#                                    with the notes above. Prints JSON {tag, url}.
#   release.sh deploy <sha>          Start the deploy workflow for <sha> with production=true and
#                                    print the new run {id, url} (waits until GitHub lists it).
#   release.sh wait <run> <job> [--timeout SEC]
#                                    Poll every 30 s until job <job> (staging|production) of the
#                                    run has finished, or is waiting for approval. Prints
#                                    {run_status, job, job_status, conclusion, jobs}. Exit 4 on
#                                    timeout (default 1800 s).
#   release.sh publish <milestone> [--note <one line>]...
#                                    Publish the draft release (creates the tag on its commit);
#                                    each --note becomes a bullet under "Known limitations".
#   release.sh finish <milestone>    After production: move the milestone's Done items to
#                                    Released and close the milestone. Prints JSON.
#
# The tag is the first word of the milestone title (e.g. "v0.1.0 operator endpoints" -> v0.1.0).
# CI workflow name: deploy.ci_workflow in the config (default: ci.yml).
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOARD="$SQUAD_SCRIPTS/board.sh"

milestone_json() { # number, title, state of the milestone (by title or number)
  gh api --paginate "repos/$OWNER/$REPO/milestones?state=all&per_page=100" \
    | jq -cs --arg m "$1" '[add // [] | .[] | select(.title == $m or (.number | tostring) == $m)] | first // empty'
}

ms_issues() { # issues in the milestone with board status (JSON array)
  local tmp; tmp="$(mktemp)"
  "$BOARD" list all > "$tmp"
  gh issue list --repo "$OWNER/$REPO" --milestone "$1" --state all --limit 500 \
      --json number,title,state,labels,closedByPullRequestsReferences \
    | jq --slurpfile b "$tmp" 'map(. as $i | {number, title, state, labels: [.labels[].name],
        prs: [.closedByPullRequestsReferences[].number],
        status: ([$b[0][] | select(.number == $i.number) | .status] | first)})'
  rm -f "$tmp"
}

cmd_gate() {
  local m; m="$(milestone_json "${1:?usage: release.sh gate <milestone>}")"
  [[ -n "$m" ]] || die "milestone '$1' not found"
  local title; title="$(jq -r .title <<<"$m")"
  local issues bugs ci wf
  issues="$(ms_issues "$title")"
  # board statuses may lag for new items: read missing ones directly
  local n
  for n in $(jq -r '.[] | select(.status == null) | .number' <<<"$issues"); do
    issues="$(jq --argjson n "$n" --arg s "$("$BOARD" get "$n" 2>/dev/null | jq -r '.status // empty')" \
              'map(if .number == $n then .status = (if $s == "" then null else $s end) else . end)' <<<"$issues")"
  done
  bugs="$(gh issue list --repo "$OWNER/$REPO" --label type:bug --state open --limit 500 --json number,title \
          | jq -c '.')"
  local tmp; tmp="$(mktemp)"; "$BOARD" list all > "$tmp"
  # a bug missing from the (eventually consistent) listing is read directly; one that is not
  # on the board at all has no priority and blocks the release until someone sets it
  for n in $(jq -r --slurpfile b "$tmp" '[.[].number] - [$b[0][].number] | .[]' <<<"$bugs"); do
    jq --argjson i "$("$BOARD" get "$n" 2>/dev/null || echo '{}')" '. + [$i | select(.number != null)]' "$tmp" > "$tmp.x" \
      && mv "$tmp.x" "$tmp"
  done
  bugs="$(jq --slurpfile b "$tmp" '[.[] | . as $i | ([$b[0][] | select(.number == $i.number)] | first) as $it
            | select($it == null or $it.priority == "P0" or $it.priority == "P1")
            | {number, title, priority: (if $it == null then "not on the board" else $it.priority end)}]' <<<"$bugs")"
  rm -f "$tmp"
  wf="$(cfg '.deploy.ci_workflow')"; wf="${wf:-ci.yml}"
  ci="$(gh run list --repo "$OWNER/$REPO" --workflow "$wf" --branch main --event push --limit 1 \
        --json conclusion,headSha,url -q '.[0] // {}')"; [[ -n "$ci" ]] || ci='{}'
  jq -n --argjson m "$m" --argjson issues "$issues" --argjson bugs "$bugs" --argjson ci "$ci" '
    ($issues | map(select((.labels | index("type:epic") or index("type:story")) | not))) as $work
    | {milestone: $m.title, tag: ($m.title | split(" ")[0]), state: $m.state,
       items: ($work | map({number, title, status, prs})),
       not_done: [$work[] | select(.status != "Done" and .status != "Released") | {number, status}],
       open_p0_p1_bugs: $bugs, ci_main: $ci}
    | .reasons = ([
        (if (.items | length) == 0 then "milestone has no items" else empty end),
        (.not_done[] | "#\(.number) is \(.status // "not on the board"), not Done"),
        (.open_p0_p1_bugs[] | "open \(.priority) bug #\(.number)"),
        (if .ci_main.conclusion != "success" then "latest CI on main is \(.ci_main.conclusion // "missing")" else empty end)])
    | .ok = (.reasons | length == 0)'
}

cmd_notes() {
  local m; m="$(milestone_json "${1:?usage: release.sh notes <milestone>}")"
  [[ -n "$m" ]] || die "milestone '$1' not found"
  local title prs; title="$(jq -r .title <<<"$m")"
  prs="$(ms_issues "$title" | jq -r '[.[].prs[]] | unique | .[]')"
  local rows='[]' p
  for p in $prs; do
    rows="$(jq -c --argjson r "$(gh pr view "$p" --repo "$OWNER/$REPO" --json number,title,mergedAt,state)" '. + [$r]' <<<"$rows")"
  done
  jq -r --arg t "$title" --arg tag "$(jq -r '.title | split(" ")[0]' <<<"$m")" '
    map(select(.state == "MERGED"))
    | map(. + {type: (.title | capture("^(?<t>[a-z]+)(\\(.*\\))?!?:").t // "other")})
    | ([["Features", ["feat"]], ["Fixes", ["fix"]], ["Chores and docs", ["chore","docs","refactor","test","ci","build","perf","style","other"]]]) as $groups
    | . as $all
    | "## \($tag)\n\nMilestone: \($t)\n" +
      ([$groups[] | . as $g | [$all[] | select(.type as $x | $g[1] | index($x))] as $in
        | select($in | length > 0)
        | "\n### \($g[0])\n" + ([$in[] | "- \(.title) (#\(.number))"] | join("\n"))] | join("\n")) + "\n"' <<<"$rows"
}

cmd_finish() {
  local m; m="$(milestone_json "${1:?usage: release.sh finish <milestone>}")"
  [[ -n "$m" ]] || die "milestone '$1' not found"
  local title num moved='[]' n done_items; title="$(jq -r .title <<<"$m")"; num="$(jq -r .number <<<"$m")"
  # own line: if the lookup fails the script stops here instead of closing an unreleased milestone
  done_items="$(ms_issues "$title" | jq -r '.[] | select(.status == "Done") | .number')"
  for n in $done_items; do
    "$BOARD" move "$n" Released >/dev/null
    moved="$(jq -c --argjson n "$n" '. + [$n]' <<<"$moved")"
  done
  gh api -X PATCH "repos/$OWNER/$REPO/milestones/$num" -f state=closed >/dev/null
  jq -n --arg t "$title" --argjson moved "$moved" '{milestone:$t, released:$moved, closed:true}'
}

cmd_draft() {
  local ms="${1:?usage: release.sh draft <milestone> <sha>}" sha="${2:?usage: release.sh draft <milestone> <sha>}"
  local m tag notes; m="$(milestone_json "$ms")"; [[ -n "$m" ]] || die "milestone '$ms' not found"
  tag="$(jq -r '.title | split(" ")[0]' <<<"$m")"
  notes="$(mktemp)"; cmd_notes "$ms" > "$notes"
  if gh release view "$tag" --repo "$OWNER/$REPO" >/dev/null 2>&1; then
    gh release edit "$tag" --repo "$OWNER/$REPO" --target "$sha" --notes-file "$notes" >/dev/null
  else
    gh release create "$tag" --repo "$OWNER/$REPO" --draft --target "$sha" --title "$tag" --notes-file "$notes" >/dev/null
  fi
  rm -f "$notes"
  gh release view "$tag" --repo "$OWNER/$REPO" --json tagName,url,isDraft -q '{tag: .tagName, url, draft: .isDraft}'
}

workflow() { local wf; wf="$(cfg '.deploy.staging_workflow')"; echo "${wf:-deploy.yml}"; }

cmd_deploy() {
  local sha="${1:?usage: release.sh deploy <sha>}" wf since _ run
  wf="$(workflow)"; since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gh workflow run "$wf" --repo "$OWNER/$REPO" -f ref="$sha" -f production=true >/dev/null
  for _ in $(seq 1 20); do   # the new run shows up after a few seconds
    sleep 5
    run="$(gh run list --repo "$OWNER/$REPO" --workflow "$wf" --event workflow_dispatch --limit 10 \
             --json databaseId,url,createdAt \
           | jq -c --arg s "$since" '[.[] | select(.createdAt >= $s)] | sort_by(.createdAt) | last // empty')"
    [[ -n "$run" ]] && { jq -c '{id: .databaseId, url}' <<<"$run"; return; }
  done
  die "the deploy run did not appear within 100 s (check: gh run list --workflow $wf)"
}

cmd_wait() {
  local run="${1:?usage: release.sh wait <run> <job> [--timeout SEC]}" job="${2:?usage: release.sh wait <run> <job>}"
  local timeout=1800 start j st rs; shift 2
  [[ "${1:-}" == --timeout ]] && timeout="${2:?}"
  start=$SECONDS
  while :; do
    j="$(gh run view "$run" --repo "$OWNER/$REPO" --json status,jobs)"
    # a job behind an environment approval does not exist yet while the run is "waiting"
    st="$(jq -r --arg n "$job" '[.jobs[] | select(.name == $n)][0].status // empty' <<<"$j")"
    rs="$(jq -r .status <<<"$j")"
    if [[ "$st" == completed || "$rs" == completed || ( "$rs" == waiting && "$job" == production ) ]]; then
      jq -c --arg n "$job" '{run_status: .status, job: $n,
          job_status: ([.jobs[] | select(.name == $n)][0].status // "not started"),
          conclusion: ([.jobs[] | select(.name == $n)][0].conclusion // null),
          jobs: [.jobs[] | {name, status, conclusion}]}' <<<"$j"
      return
    fi
    (( SECONDS - start < timeout )) || { EXIT_CODE=4 die "timeout after ${timeout}s waiting for job $job of run $run"; }
    sleep 30
  done
}

cmd_publish() {
  local ms="${1:?usage: release.sh publish <milestone> [--note <text>]...}"; shift
  local notes=() m tag body
  while [[ $# -gt 0 ]]; do
    case "$1" in --note) notes+=("${2:?--note needs text}"); shift 2 ;; *) die "unknown option $1" ;; esac
  done
  m="$(milestone_json "$ms")"; [[ -n "$m" ]] || die "milestone '$ms' not found"
  tag="$(jq -r '.title | split(" ")[0]' <<<"$m")"
  body="$(mktemp)"
  gh release view "$tag" --repo "$OWNER/$REPO" --json body -q .body > "$body" || die "no draft release $tag"
  if ((${#notes[@]})) && ! grep -q '^### Known limitations' "$body"; then
    { printf '\n### Known limitations\n'; printf -- '- %s\n' "${notes[@]}"; } >> "$body"
  fi
  gh release edit "$tag" --repo "$OWNER/$REPO" --draft=false --latest --notes-file "$body" >/dev/null
  rm -f "$body"
  gh release view "$tag" --repo "$OWNER/$REPO" --json tagName,url,isDraft -q '{tag: .tagName, url, draft: .isDraft}'
}

need gh jq
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  gate|notes|draft|deploy|wait|publish|finish) load_project; "cmd_$cmd" "$@" ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
