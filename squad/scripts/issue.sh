#!/usr/bin/env bash
# issue.sh: issues, sub-issues and labels for squad.
#
# Usage:
#   issue.sh create <type> <title> <body-file> [--parent N] [--priority P] [--size S]
#                   [--milestone TITLE] [--status STATUS | --no-board]
#       type: epic|story|task|bug|report. Creates the issue with label type:<type>, adds it
#       to the board, sets fields and links it as a sub-issue of --parent. Default status:
#       epic/story -> Backlog, task/bug -> Todo; reports are not added to the board.
#       Re-running with the same type and title reuses the open issue instead of duplicating it.
#   issue.sh link <parent> <child>     Make <child> a sub-issue of <parent> (idempotent)
#   issue.sh children <issue>          JSON list of sub-issues with state, labels and board status
#   issue.sh parent <issue>            Parent issue number, or empty if none
#   issue.sh labels                    Create or update every squad label (idempotent)
#
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOARD="$SQUAD_SCRIPTS/board.sh"

LABELS='[
 {"name":"type:epic","color":"5319e7","description":"Epic: a group of related stories"},
 {"name":"type:story","color":"1d76db","description":"User story (vertical slice)"},
 {"name":"type:task","color":"0e8a16","description":"Technical task, one PR"},
 {"name":"type:bug","color":"d73a4a","description":"Defect found by QA or in production"},
 {"name":"type:report","color":"c5def5","description":"Stakeholder progress report"},
 {"name":"qa:failed","color":"b60205","description":"QA found at least one bug"},
 {"name":"review:changes","color":"fbca04","description":"Reviewer requested changes"},
 {"name":"needs-split","color":"f9d0c4","description":"Too large; must be split into smaller tasks"},
 {"name":"needs-rebase","color":"fef2c0","description":"PR conflicts with main; needs a rebase"},
 {"name":"needs-human","color":"000000","description":"Escalated to the stakeholder"},
 {"name":"blocked","color":"e4e669","description":"Cannot proceed until something else changes"}
]'

cmd_labels() {
  local n
  for n in $(jq -r '.[].name' <<<"$LABELS"); do
    gh label create "$n" --repo "$OWNER/$REPO" --force \
      --color "$(jq -r --arg n "$n" '.[] | select(.name == $n) | .color' <<<"$LABELS")" \
      --description "$(jq -r --arg n "$n" '.[] | select(.name == $n) | .description' <<<"$LABELS")" >/dev/null \
      || die "cannot create label $n"
  done
  jq -c '[.[].name]' <<<"$LABELS"
}

cmd_parent() {
  local n="${1:?usage: issue.sh parent <issue>}"
  gql 'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){parent{number}}}}' \
    -F o="$OWNER" -F r="$REPO" -F n="$n" | jq -r '.data.repository.issue.parent.number // empty'
}

cmd_link() {
  local p="${1:?usage: issue.sh link <parent> <child>}" c="${2:?usage: issue.sh link <parent> <child>}"
  local cur; cur="$(cmd_parent "$c")"
  if [[ "$cur" == "$p" ]]; then info "#$c is already a sub-issue of #$p"; return; fi
  [[ -z "$cur" ]] || die "#$c already has parent #$cur; refusing to move it"
  local pid cid
  pid="$(issue_node_id "$p")"; [[ -n "$pid" ]] || die "parent #$p not found"
  cid="$(issue_node_id "$c")"; [[ -n "$cid" ]] || die "child #$c not found"
  gql 'mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{number}}}' \
    -F p="$pid" -F c="$cid" >/dev/null
  info "linked #$c as a sub-issue of #$p"
}

cmd_children() {
  local n="${1:?usage: issue.sh children <issue>}" subs board
  subs="$(gql 'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){
              subIssues(first:100){nodes{number title state labels(first:30){nodes{name}}}}}}}' \
          -F o="$OWNER" -F r="$REPO" -F n="$n" | jq '.data.repository.issue.subIssues.nodes')"
  board="$("$BOARD" list all)"
  jq --argjson b "$board" 'map(. as $i | {number, title, state, labels: [.labels.nodes[].name],
       status: ([$b[] | select(.number == $i.number) | .status] | first)})' <<<"$subs"
}

cmd_create() {
  [[ $# -ge 3 ]] || die "usage: issue.sh create <type> <title> <body-file> [options]"
  local type="$1" title="$2" body="$3"; shift 3
  local parent="" priority="" size="" milestone="" status="" board=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent) parent="${2:?}"; shift 2 ;;
      --priority) priority="${2:?}"; shift 2 ;;
      --size) size="${2:?}"; shift 2 ;;
      --milestone) milestone="${2:?}"; shift 2 ;;
      --status) status="${2:?}"; shift 2 ;;
      --no-board) board=0; shift ;;
      *) die "unknown option $1" ;;
    esac
  done
  in_list "$type" "${ISSUE_TYPES[@]}" || die "type must be one of: ${ISSUE_TYPES[*]}"
  [[ -s "$body" ]] || die "body file '$body' is missing or empty"
  [[ -z "$priority" ]] || in_list "$priority" "${PRIORITIES[@]}" || die "priority must be one of ${PRIORITIES[*]}"
  [[ -z "$size" ]] || in_list "$size" "${SIZES[@]}" || die "size must be one of ${SIZES[*]}"
  [[ -z "$status" ]] || in_list "$status" "${STATUSES[@]}" || die "unknown status '$status'"
  if [[ -z "$status" ]]; then
    case "$type" in epic|story) status=Backlog ;; task|bug) status=Todo ;; report) board=0 ;; esac
  fi

  local num url
  num="$(gh issue list --repo "$OWNER/$REPO" --label "type:$type" --state open --limit 500 --json number,title \
         | jq -r --arg t "$title" '[.[] | select(.title == $t)][0].number // empty')"
  if [[ -n "$num" ]]; then
    info "reusing open issue #$num with the same title"
  else
    local args=(--repo "$OWNER/$REPO" --title "$title" --body-file "$body" --label "type:$type")
    [[ -z "$milestone" ]] || args+=(--milestone "$milestone")
    url="$(gh issue create "${args[@]}")" || die "cannot create issue"
    num="${url##*/}"
  fi
  [[ -z "$parent" ]] || cmd_link "$parent" "$num"
  if [[ "$board" == 1 ]]; then
    "$BOARD" move "$num" "$status" >/dev/null
    [[ -z "$priority" ]] || "$BOARD" set-field "$num" priority "$priority" >/dev/null
    [[ -z "$size" ]] || "$BOARD" set-field "$num" size "$size" >/dev/null
  fi
  jq -nc --argjson n "$num" --arg t "$type" --arg u "https://github.com/$OWNER/$REPO/issues/$num" \
    --arg s "$([[ "$board" == 1 ]] && echo "$status")" --arg p "$parent" \
    '{issue:$n, type:$t, url:$u, status:(if $s == "" then null else $s end),
      parent:(if $p == "" then null else ($p | tonumber) end)}'
}

need gh jq git awk
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  create|link|children|parent) load_project; "cmd_$cmd" "$@" ;;
  labels)
    load_config; OWNER="$(cfg_req .owner)"; REPO="$(cfg_req .repo)"; cmd_labels ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
