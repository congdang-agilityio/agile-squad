#!/usr/bin/env bash
# board.sh: GitHub Projects board operations for squad.
#
# Usage:
#   board.sh bootstrap [--project N] [--title T]   Create/reuse the project, ensure the
#                                                  Status/Priority/Size/Wave/Agent/Attempts
#                                                  fields, link the repo, write ids to config
#   board.sh list <status|all> [--label L]         JSON list of board items
#   board.sh get <issue>                           JSON for one item
#   board.sh move <issue> <status>                 Set Status (adds the issue to the board if needed)
#   board.sh set-field <issue> <field> <value>     Field: priority|size|wave|agent|attempts
#                                                  (empty value clears the field)
#   board.sh ready-tasks                           Todo tasks/bugs whose dependencies are all
#                                                  Done/Released (excludes blocked, needs-human,
#                                                  needs-split), sorted by priority, wave, number
#   board.sh bump-attempts <issue>                 Attempts += 1, prints the new value
#   board.sh workflows [--fix]                     List built-in project workflows that fight squad
#                                                  status ownership; --fix deletes them (permanent;
#                                                  GitHub's API has no "disable")
#
# Statuses: Backlog, Todo, "In Progress", "In Review", QA, Done, Released
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
# Requires: gh (with the project scope), jq, git.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------- items

# GraphQL selections shared by the board-wide and single-issue queries
ISSUE_SEL='number title state body url repository{nameWithOwner} labels(first:30){nodes{name}} milestone{title}'
VALUES_SEL='fieldValues(first:30){nodes{__typename
  ... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}}
  ... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2FieldCommon{name}}}
  ... on ProjectV2ItemFieldTextValue{text field{... on ProjectV2FieldCommon{name}}}}}'

ITEMS_QUERY="query(\$id:ID!,\$endCursor:String){node(id:\$id){... on ProjectV2{items(first:100,after:\$endCursor){
  pageInfo{hasNextPage endCursor}
  nodes{id isArchived content{__typename ... on Issue{$ISSUE_SEL}} $VALUES_SEL}}}}}"

ONE_QUERY="query(\$o:String!,\$r:String!,\$n:Int!){repository(owner:\$o,name:\$r){issue(number:\$n){
  __typename $ISSUE_SEL projectItems(first:50){nodes{id isArchived project{id} $VALUES_SEL}}}}}"

# jq: turn a project item node {id, isArchived, content, fieldValues} into a squad item
NORMALIZE='def item:
  (reduce (.fieldValues.nodes[] | select(.field.name != null)) as $f
     ({}; .[$f.field.name] = ($f.name // ($f.number | if . != null and . == floor then floor else . end) // $f.text))) as $v
  | { item_id: .id, number: .content.number, title: .content.title,
      state: .content.state, url: .content.url, milestone: .content.milestone.title,
      labels: [.content.labels.nodes[].name],
      status: $v.Status, priority: $v.Priority, size: $v.Size, wave: $v.Wave,
      agent: $v.Agent, attempts: ($v.Attempts // 0), body: .content.body };'

# all_items: every issue of this repo on the board, with bodies (cached per process).
# Note: GitHub's project item listing is eventually consistent; an issue added in the last
# ~30 seconds may be missing here. Single-issue commands use one_item, which is consistent.
ITEMS_JSON=""
all_items() {
  if [[ -z "$ITEMS_JSON" ]]; then
    local raw
    raw="$(gh api graphql --paginate -f query="$ITEMS_QUERY" -F id="$PROJECT_ID" 2>&1)" \
      || die "cannot read project items: $raw"
    ITEMS_JSON="$(jq -s --arg repo "$OWNER/$REPO" "$NORMALIZE"'
      [ .[].data.node.items.nodes[]
        | select((.isArchived | not) and .content.__typename == "Issue"
                 and .content.repository.nameWithOwner == $repo)
        | item ]' <<<"$raw")"
  fi
  echo "$ITEMS_JSON"
}

# one_item <issue> : the issue's item on this board (with body), read directly; empty if absent
one_item() {
  local out
  out="$(gh api graphql -f query="$ONE_QUERY" -F o="$OWNER" -F r="$REPO" -F n="$1" 2>/dev/null)" || true
  [[ -n "$out" ]] || die "cannot read issue #$1"
  # a missing issue comes back as NOT_FOUND with issue: null; any other error is fatal
  jq -e '[.errors[]? | select(.type != "NOT_FOUND")] | length == 0' >/dev/null <<<"$out" \
    || die "GraphQL error: $(jq -r '[.errors[].message] | join("; ")' <<<"$out")"
  jq -c --arg p "$PROJECT_ID" "$NORMALIZE"'
    .data.repository.issue as $i | select($i != null)
    | [$i.projectItems.nodes[] | select(.project.id == $p and (.isArchived | not))
       | . + {content: $i} | item] | first // empty' <<<"$out"
}

strip_body() { jq 'map(del(.body))'; }

item_id() { # item_id <issue> : project item id, adding the issue to the board if missing
  local n="$1" out id node try
  for try in 1 2 3 4 5; do
    out="$(gql 'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id
              projectItems(first:50){nodes{id project{id}}}}}}' -F o="$OWNER" -F r="$REPO" -F n="$n")"
    node="$(jq -r '.data.repository.issue.id // empty' <<<"$out")"
    [[ -n "$node" ]] || die "issue #$n not found in $OWNER/$REPO"
    id="$(jq -r --arg p "$PROJECT_ID" '.data.repository.issue.projectItems.nodes[] | select(.project.id == $p) | .id' <<<"$out" | head -n1)"
    if [[ -n "$id" ]]; then echo "$id"; return; fi
    # GitHub may be auto-adding the issue (e.g. sub-issue auto-add) at the same moment:
    # "Content already exists" means it is there, so look it up again.
    out="$(gh api graphql -F p="$PROJECT_ID" -F c="$node" \
           -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' 2>&1)" || true
    id="$(jq -r '.data.addProjectV2ItemById.item.id // empty' <<<"$out" 2>/dev/null || true)"
    if [[ -n "$id" ]]; then info "added #$n to the board"; echo "$id"; return; fi
    grep -q "already exists" <<<"$out" || die "cannot add #$n to the board: $out"
    sleep "$try"
  done
  die "issue #$n is reported on the board but its item cannot be found"
}

edit_item() { # edit_item <issue> <field-id> <gh item-edit value args...>
  local n="$1" fid="$2"; shift 2
  local iid; iid="$(item_id "$n")"
  gh project item-edit --id "$iid" --project-id "$PROJECT_ID" --field-id "$fid" "$@" >/dev/null \
    || die "failed to update #$n"
}

# ---------------------------------------------------------------- commands

cmd_list() {
  local status="${1:-}" label=""
  [[ -n "$status" ]] || die "usage: board.sh list <status|all> [--label L]"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in --label) label="${2:?--label needs a value}"; shift 2 ;; *) die "unknown option $1" ;; esac
  done
  [[ "$status" == "all" ]] || in_list "$status" "${STATUSES[@]}" || die "unknown status '$status'"
  all_items | jq --arg s "$status" --arg l "$label" \
    'map(select(($s == "all" or .status == $s) and ($l == "" or (.labels | index($l)))))' | strip_body
}

cmd_get() {
  local n="${1:?usage: board.sh get <issue>}" it
  it="$(one_item "$n")"
  [[ -n "$it" ]] || die "#$n is not on the board"
  jq 'del(.body)' <<<"$it"
}

cmd_move() {
  local n="${1:?usage: board.sh move <issue> <status>}" s="${2:?usage: board.sh move <issue> <status>}"
  in_list "$s" "${STATUSES[@]}" || die "unknown status '$s' (one of: ${STATUSES[*]})"
  local opt; opt="$(cfg_req ".ids.status_options[\"$s\"]")"
  edit_item "$n" "$(cfg_req .ids.status_field_id)" --single-select-option-id "$opt"
  jq -nc --argjson n "$n" --arg s "$s" '{issue:$n, status:$s}'
}

cmd_set_field() {
  [[ $# -eq 3 ]] || die "usage: board.sh set-field <issue> <field> <value>"
  local n="$1" f="${2,,}" v="$3" fid
  case "$f" in
    priority|size)
      fid="$(cfg_req ".ids.${f}_field_id")"
      if [[ -z "$v" ]]; then edit_item "$n" "$fid" --clear; else
        if [[ "$f" == priority ]]; then in_list "$v" "${PRIORITIES[@]}" || die "priority must be one of ${PRIORITIES[*]}"
        else in_list "$v" "${SIZES[@]}" || die "size must be one of ${SIZES[*]} (anything bigger must be split)"; fi
        edit_item "$n" "$fid" --single-select-option-id "$(cfg_req ".ids.${f}_options[\"$v\"]")"
      fi ;;
    wave|attempts)
      fid="$(cfg_req ".ids.${f}_field_id")"
      if [[ -z "$v" ]]; then edit_item "$n" "$fid" --clear; else
        [[ "$v" =~ ^[0-9]+$ ]] || die "$f must be a non-negative integer"
        edit_item "$n" "$fid" --number "$v"
      fi ;;
    agent)
      fid="$(cfg_req .ids.agent_field_id)"
      if [[ -z "$v" ]]; then edit_item "$n" "$fid" --clear; else edit_item "$n" "$fid" --text "$v"; fi ;;
    status) cmd_move "$n" "$v"; return ;;
    *) die "unknown field '$2' (priority|size|wave|agent|attempts)" ;;
  esac
  jq -nc --argjson n "$n" --arg f "$f" --arg v "$v" '{issue:$n, field:$f, value:$v}'
}

cmd_ready_tasks() {
  local items cand missing d st extra='{}'
  items="$(all_items)"
  cand="$(jq '
    map(select(.status == "Todo"
          and (.labels | index("type:task") or index("type:bug"))
          and ([.labels[] | select(. == "blocked" or . == "needs-human" or . == "needs-split")] | length == 0)))
    | map(. + {depends_on: [ (.body // "") | split("\n")[] | select(test("depends on"; "i"))
                             | scan("#([0-9]+)")[0] | tonumber ] | unique})' <<<"$items")"
  # dependencies not in the (eventually consistent) listing are looked up one by one
  missing="$(jq -r --argjson all "$items" '[.[].depends_on[]] | unique - [$all[].number] | .[]' <<<"$cand")"
  for d in $missing; do
    st="$(one_item "$d" | jq -r '.status // empty')"
    extra="$(jq -c --arg k "$d" --arg v "$st" '. + {($k): $v}' <<<"$extra")"
  done
  jq --argjson all "$items" --argjson extra "$extra" '
    ((($all | map({key: (.number | tostring), value: .status}) | from_entries)) + $extra) as $st
    | map(select([.depends_on[] | ($st[tostring] // "") | select(. != "Done" and . != "Released")] | length == 0)
          | del(.body))
    | sort_by((.priority // "P9"), (.wave // 999999), .number)' <<<"$cand"
}

cmd_bump_attempts() {
  local n="${1:?usage: board.sh bump-attempts <issue>}" cur
  cur="$(cmd_get "$n" | jq -r '.attempts // 0')"
  cmd_set_field "$n" attempts "$((cur + 1))" >/dev/null
  jq -nc --argjson n "$n" --argjson a "$((cur + 1))" '{issue:$n, attempts:$a}'
}

# Built-in workflows that set Status behind squad's back. "Item closed" and "Pull request
# merged" would move a task to Done when its PR merges, skipping QA.
CONFLICTING_WORKFLOWS='["Item added to project","Item closed","Pull request linked to issue","Pull request merged"]'

cmd_workflows() {
  local fix=0; [[ "${1:-}" == "--fix" ]] && fix=1
  local wf; wf="$(gql 'query($id:ID!){node(id:$id){... on ProjectV2{workflows(first:50){nodes{id name enabled}}}}}' \
                 -F id="$PROJECT_ID" | jq --argjson c "$CONFLICTING_WORKFLOWS" \
                 '[.data.node.workflows.nodes[] | . + {conflicts: (.name as $n | $c | index($n) != null)}]')"
  if [[ "$fix" == 1 ]]; then
    local id
    for id in $(jq -r '.[] | select(.conflicts) | .id' <<<"$wf"); do
      gql 'mutation($w:ID!){deleteProjectV2Workflow(input:{workflowId:$w}){deletedWorkflowId}}' -F w="$id" >/dev/null
      info "deleted workflow $(jq -r --arg i "$id" '.[] | select(.id == $i) | .name' <<<"$wf")"
    done
    wf="$(jq 'map(select(.conflicts | not))' <<<"$wf")"
  fi
  jq 'map({name, enabled, conflicts})' <<<"$wf"
}

# ---------------------------------------------------------------- bootstrap

STATUS_COLORS=(GRAY BLUE YELLOW PURPLE ORANGE GREEN PINK)
STATUS_DESCS=("Approved story, not yet split into tasks" "Ready to be picked up" "A developer is working on it"
  "PR open, awaiting review" "Merged, awaiting testing" "QA passed, ready to deploy" "Live in production")

# options_json <names-csv> <colors-csv> [descs separated by |] : JSON array of option inputs
options_json() {
  jq -nc --arg n "$1" --arg c "$2" --arg d "${3:-}" '
    ($n | split(",")) as $n | ($c | split(",")) as $c | ($d | split("|")) as $d
    | [range(0; $n | length) | {name: $n[.], color: $c[.], description: ($d[.] // "")}]'
}

FIELDS_JSON=""
load_fields() {
  FIELDS_JSON="$(gql 'query($id:ID!){node(id:$id){... on ProjectV2{fields(first:50){nodes{
      __typename ... on ProjectV2FieldCommon{id name dataType}
      ... on ProjectV2SingleSelectField{options{id name}}}}}}}' -F id="$PROJECT_ID" \
    | jq '.data.node.fields.nodes')"
}
field() { jq -c --arg n "$1" 'map(select(.name == $n)) | first // empty' <<<"$FIELDS_JSON"; }

gql_body() { # gql_body <json-body> : POST a full {query, variables} body
  local out; out="$(gh api graphql --input - <<<"$1" 2>&1)" || die "GraphQL request failed: $out"
  jq -e '.errors? | length > 0' >/dev/null 2>&1 <<<"$out" \
    && die "GraphQL error: $(jq -r '[.errors[].message] | join("; ")' <<<"$out")"
  echo "$out"
}

# ensure_select <name> <options-json> : create the field or align its options (keeping ids)
ensure_select() {
  local name="$1" want="$2" have
  have="$(field "$name")"
  if [[ -z "$have" ]]; then
    gql_body "$(jq -nc --arg p "$PROJECT_ID" --arg n "$name" --argjson o "$want" '{query:
      "mutation($p:ID!,$n:String!,$o:[ProjectV2SingleSelectFieldOptionInput!]){createProjectV2Field(input:{projectId:$p,dataType:SINGLE_SELECT,name:$n,singleSelectOptions:$o}){projectV2Field{... on ProjectV2FieldCommon{id}}}}",
      variables:{p:$p, n:$n, o:$o}}')" >/dev/null
    info "created field $name"; return
  fi
  [[ "$(jq -r .dataType <<<"$have")" == SINGLE_SELECT ]] || die "field '$name' exists but is not single select"
  if [[ "$(jq -c '[.options[].name]' <<<"$have")" == "$(jq -c '[.[].name]' <<<"$want")" ]]; then
    info "field $name already up to date"; return
  fi
  local extra; extra="$(jq -r --argjson w "$want" '[.options[].name] - [$w[].name] | join(", ")' <<<"$have")"
  [[ -z "$extra" ]] || warn "removing options from $name: $extra (items using them lose that value)"
  # keep the ids of options that already exist so items keep their values
  local merged; merged="$(jq -c --argjson h "$have" '
    map(. as $o | ([$h.options[] | select(.name == $o.name) | .id] | first) as $id
        | if $id then $o + {id: $id} else $o end)' <<<"$want")"
  gql_body "$(jq -nc --arg f "$(jq -r .id <<<"$have")" --argjson o "$merged" '{query:
    "mutation($f:ID!,$o:[ProjectV2SingleSelectFieldOptionInput!]){updateProjectV2Field(input:{fieldId:$f,singleSelectOptions:$o}){projectV2Field{... on ProjectV2FieldCommon{id}}}}",
    variables:{f:$f, o:$o}}')" >/dev/null
  info "updated options of field $name"
}

ensure_plain() { # ensure_plain <name> <NUMBER|TEXT>
  local have; have="$(field "$1")"
  if [[ -n "$have" ]]; then
    [[ "$(jq -r .dataType <<<"$have")" == "$2" ]] || die "field '$1' exists but is not $2"
    info "field $1 already exists"; return
  fi
  gql 'mutation($p:ID!,$n:String!,$t:ProjectV2CustomFieldType!){createProjectV2Field(input:{projectId:$p,dataType:$t,name:$n}){projectV2Field{... on ProjectV2FieldCommon{id}}}}' \
    -F p="$PROJECT_ID" -F n="$1" -F t="$2" >/dev/null
  info "created field $1"
}

# set_top <file> <key> <value> : replace (or append) a top-level "key: value" line
set_top() {
  local f="$1" k="$2" v="$3"
  if grep -q "^$k:" "$f"; then
    awk -v k="$k" -v v="$v" 'BEGIN{p="^" k ":"} $0 ~ p {c=""; if (match($0, /[ \t]+#.*/)) c=substr($0, RSTART); print k ": " v c; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else echo "$k: $v" >> "$f"; fi
}

# write_ids <file> <ids-yaml-file> : replace the top-level ids: block
write_ids() {
  awk -v idsfile="$2" '
    function dump(  l) { while ((getline l < idsfile) > 0) print l; done = 1 }
    /^ids:/ { dump(); skip = 1; next }
    skip && /^[^ \t#]/ { skip = 0 }
    skip { next }
    { print }
    END { if (!done) dump() }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

cmd_bootstrap() {
  local number="" title=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) number="${2:?}"; shift 2 ;;
      --title) title="${2:?}"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  gh auth status --active 2>&1 | grep -q "Token scopes:.*'project'" \
    || die "the active gh token lacks the 'project' scope; run: gh auth refresh -s project"

  local path; path="$(config_path)"
  if [[ ! -f "$path" ]]; then
    local slug; slug="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || die "cannot detect the GitHub repository"
    mkdir -p "$(dirname "$path")"
    cp "$SQUAD_ROOT/templates/squad.config.yml" "$path"
    set_top "$path" owner "${slug%%/*}"; set_top "$path" repo "${slug#*/}"
    info "created $path"
  fi
  load_config
  OWNER="$(cfg_req .owner)"; REPO="$(cfg_req .repo)"
  [[ -n "$number" ]] || number="$(cfg .project_number)"

  if [[ -z "$number" ]]; then
    title="${title:-$REPO squad}"
    number="$(gh project list --owner "$OWNER" --format json --limit 100 \
              | jq -r --arg t "$title" '[.projects[] | select(.title == $t and (.closed | not))][0].number // empty')"
    if [[ -n "$number" ]]; then info "reusing project #$number ($title)"
    else
      number="$(gh project create --owner "$OWNER" --title "$title" --format json | jq -r .number)" \
        || die "cannot create project"
      info "created project #$number ($title)"
    fi
  fi
  PROJECT_ID="$(gh project view "$number" --owner "$OWNER" --format json | jq -r .id)" \
    || die "project #$number not found for $OWNER"
  PROJECT_NUMBER="$number"

  local linked
  linked="$(gql 'query($o:String!,$r:String!){repository(owner:$o,name:$r){projectsV2(first:50){nodes{id}}}}' \
            -F o="$OWNER" -F r="$REPO" | jq -r --arg p "$PROJECT_ID" '[.data.repository.projectsV2.nodes[].id] | index($p) // empty')"
  if [[ -z "$linked" ]]; then
    gh project link "$number" --owner "$OWNER" --repo "$OWNER/$REPO" >/dev/null || die "cannot link project to repo"
    info "linked project #$number to $OWNER/$REPO"
  fi

  load_fields
  local names; names="$(IFS=,; echo "${STATUSES[*]}")"
  ensure_select Status "$(options_json "$names" "$(IFS=,; echo "${STATUS_COLORS[*]}")" "$(IFS='|'; echo "${STATUS_DESCS[*]}")")"
  ensure_select Priority "$(options_json "P0,P1,P2,P3" "RED,ORANGE,YELLOW,GRAY" "Critical|High|Normal|Low")"
  ensure_select Size "$(options_json "XS,S,M" "GREEN,BLUE,YELLOW" "<=50 lines, <=3 files|<=150 lines, <=6 files|<=300 lines, <=10 files")"
  ensure_plain Wave NUMBER
  ensure_plain Agent TEXT
  ensure_plain Attempts NUMBER
  load_fields

  local ids; ids="$(mktemp)"
  jq -r --arg p "$PROJECT_ID" '
    def opts(n): (map(select(.name == n)) | first | .options) | map("    \"\(.name)\": \"\(.id)\"") | join("\n");
    def fid(n): map(select(.name == n)) | first | .id;
    "ids:                              # filled in by setup; do not edit by hand",
    "  project_id: \"\($p)\"",
    "  status_field_id: \"\(fid("Status"))\"",   "  status_options:",   opts("Status"),
    "  priority_field_id: \"\(fid("Priority"))\"", "  priority_options:", opts("Priority"),
    "  size_field_id: \"\(fid("Size"))\"",       "  size_options:",     opts("Size"),
    "  wave_field_id: \"\(fid("Wave"))\"",
    "  agent_field_id: \"\(fid("Agent"))\"",
    "  attempts_field_id: \"\(fid("Attempts"))\""' <<<"$FIELDS_JSON" > "$ids"
  set_top "$path" project_number "$number"
  write_ids "$path" "$ids"; rm -f "$ids"
  load_config
  jq -nc --arg o "$OWNER" --arg r "$REPO" --argjson n "$number" --arg id "$PROJECT_ID" --arg c "$path" \
    '{owner:$o, repo:$r, project_number:$n, project_id:$id, config:$c}'
}

# ---------------------------------------------------------------- main

need gh jq git awk
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  bootstrap) cmd_bootstrap "$@" ;;
  list|get|move|set-field|ready-tasks|bump-attempts|workflows)
    load_project
    case "$cmd" in
      list) cmd_list "$@" ;; get) cmd_get "$@" ;; move) cmd_move "$@" ;;
      set-field) cmd_set_field "$@" ;; ready-tasks) cmd_ready_tasks ;; bump-attempts) cmd_bump_attempts "$@" ;;
      workflows) cmd_workflows "$@" ;;
    esac ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
