#!/usr/bin/env bash
# release.sh: deploy entry gate, release notes and post-release bookkeeping for a milestone.
#
# Usage:
#   release.sh gate <milestone>      JSON: ok + reasons. Every issue in the milestone is Done or
#                                    Released (epics and stories may be open), no open P0/P1
#                                    bug in the repo, latest CI run on main succeeded.
#   release.sh notes <milestone>     Markdown release notes from the merged PRs that closed the
#                                    milestone's issues, grouped by PR title type.
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
  gh api "repos/$OWNER/$REPO/milestones?state=all&per_page=100" \
    | jq -c --arg m "$1" '[.[] | select(.title == $m or (.number | tostring) == $m)] | first // empty'
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
  bugs="$(jq --slurpfile b "$tmp" '[.[] | . as $i | ($b[0][] | select(.number == $i.number) | .priority) as $p
            | select($p == "P0" or $p == "P1") | {number, title, priority: $p}]' <<<"$bugs")"
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
  local title num moved='[]' n; title="$(jq -r .title <<<"$m")"; num="$(jq -r .number <<<"$m")"
  for n in $(ms_issues "$title" | jq -r '.[] | select(.status == "Done") | .number'); do
    "$BOARD" move "$n" Released >/dev/null
    moved="$(jq -c --argjson n "$n" '. + [$n]' <<<"$moved")"
  done
  gh api -X PATCH "repos/$OWNER/$REPO/milestones/$num" -f state=closed >/dev/null
  jq -n --arg t "$title" --argjson moved "$moved" '{milestone:$t, released:$moved, closed:true}'
}

need gh jq
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  gate|notes|finish) load_project; "cmd_$cmd" "$@" ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
