#!/usr/bin/env bash
# doctor.sh: check that squad can run in this repository. Read-only.
#
# Usage:
#   doctor.sh [--offline]
#
# Checks tools, the gh login and token scopes, the config and its board ids, the board and
# its fields, labels, conflicting project workflows, repository merge settings and branch
# protection, the deploy workflow and GitHub Environments, .gitignore, the gh pr merge
# permission rule, and leftover worktrees. --offline skips every check that calls GitHub.
# Output JSON: {ok, fails, warns, checks: [{check, status: ok|warn|fail, detail, fix}]}.
# Exit: 0 when nothing fails (warnings allowed), 1 when a check fails.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

offline=0
case "${1:-}" in
  -h|--help) usage_from "$0"; exit 0 ;;
  --offline) offline=1 ;;
  "") ;;
  *) die "unknown argument $1 (see --help)" ;;
esac

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
add() { # add <check> <ok|warn|fail> <detail> [fix]
  jq -nc --arg c "$1" --arg s "$2" --arg d "$3" --arg f "${4:-}" \
    '{check:$c, status:$s, detail:$d, fix:(if $f == "" then null else $f end)}' >> "$OUT"
}
finish() {
  jq -s '{ok: ([.[] | select(.status == "fail")] | length == 0),
          fails: ([.[] | select(.status == "fail")] | length),
          warns: ([.[] | select(.status == "warn")] | length), checks: .}' "$OUT"
  [[ "$(jq -s '[.[] | select(.status == "fail")] | length' "$OUT")" == 0 ]]
}

# ---------------------------------------------------------------- local
missing=()
for t in gh jq git python3 awk; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
if ((${#missing[@]})); then add tools fail "missing: ${missing[*]}" "install ${missing[*]}"; finish; exit; fi
add tools ok "gh, jq, git, python3, awk"

git rev-parse --git-dir >/dev/null 2>&1 || { add repo fail "not inside a git repository" "cd into a clone of the target repository"; finish; exit; }
path="$(config_path)"; root="$(dirname "$(dirname "$path")")"
if [[ ! -f "$path" ]]; then
  add config fail "$path not found" "run /squad:setup"; finish; exit
fi
if ! CFG_JSON="$(yaml_to_json "$path" 2>&1)" || ! jq -e . >/dev/null 2>&1 <<<"$CFG_JSON"; then
  add config fail "cannot parse $path" "fix the YAML (see templates/squad.config.yml)"; finish; exit
fi
OWNER="$(cfg .owner)"; REPO="$(cfg .repo)"; PROJECT_ID="$(cfg .ids.project_id)"
remote="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$OWNER" || -z "$REPO" ]]; then add config fail "owner or repo is empty" "run /squad:setup"
elif [[ "$remote" != *"$OWNER/$REPO"* ]]; then add config warn "owner/repo $OWNER/$REPO does not match origin $remote" "correct owner and repo in the config"
else add config ok "$OWNER/$REPO, project #$(cfg .project_number)"; fi

need_ids=(.ids.project_id .ids.status_field_id .ids.priority_field_id .ids.size_field_id
          .ids.wave_field_id .ids.agent_field_id .ids.attempts_field_id)
miss=()
for k in "${need_ids[@]}"; do [[ -n "$(cfg "$k")" ]] || miss+=("${k#.ids.}"); done
for s in "${STATUSES[@]}"; do [[ -n "$(cfg ".ids.status_options[\"$s\"]")" ]] || miss+=("status:$s"); done
for s in "${PRIORITIES[@]}"; do [[ -n "$(cfg ".ids.priority_options[\"$s\"]")" ]] || miss+=("priority:$s"); done
for s in "${SIZES[@]}"; do [[ -n "$(cfg ".ids.size_options[\"$s\"]")" ]] || miss+=("size:$s"); done
if ((${#miss[@]})); then
  add ids fail "missing: ${miss[*]}" "board.sh bootstrap --project $(cfg .project_number)"
else add ids ok "all board ids present"; fi

cmds=()
for k in install test lint build start; do [[ -n "$(cfg ".commands.$k")" ]] || cmds+=("$k"); done
if ((${#cmds[@]})); then add commands warn "empty: ${cmds[*]}" "fill commands.* in the config"
else add commands ok "install, test, lint set$([[ -n "$(cfg .commands.e2e)" ]] && echo ", e2e set")"; fi

gi=()
for p in .worktrees/ .squad/reports/; do grep -qxF "$p" "$root/.gitignore" 2>/dev/null || gi+=("$p"); done
if ((${#gi[@]})); then add gitignore warn "not ignored: ${gi[*]}" "append ${gi[*]} to .gitignore"
else add gitignore ok ".worktrees/ and .squad/reports/ ignored"; fi

rule=""
for f in "$root/.claude/settings.json" "$root/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
  if [[ -f "$f" ]] && jq -e '.permissions.allow // [] | index("Bash(gh pr merge:*)")' "$f" >/dev/null 2>&1; then rule="$f"; break; fi
done
if [[ -n "$rule" ]]; then add merge_permission ok "Bash(gh pr merge:*) allowed in ${rule#"$root/"}"
else add merge_permission warn "no Bash(gh pr merge:*) allow rule: auto mode blocks the Team Lead's merge" \
  'add "Bash(gh pr merge:*)" to permissions.allow in .claude/settings.json'; fi

wf="$(cfg .deploy.staging_workflow)"; wf="${wf:-deploy.yml}"
deploys=1; [[ "$(cfg .deploy.platform)" == none ]] && deploys=0
if [[ "$deploys" == 0 ]]; then add deploy_workflow ok "deploys are off (deploy.platform: none)"
elif [[ -f "$root/.github/workflows/$wf" ]]; then add deploy_workflow ok ".github/workflows/$wf"
else add deploy_workflow warn ".github/workflows/$wf not found: releases cannot deploy" "copy templates/deploy.yml (setup step 8)"; fi

stale=()
while read -r wt; do
  n="$(basename "$wt")"; [[ "$n" =~ ^[0-9]+$ ]] && stale+=("$n")
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep '/\.worktrees/' || true)

# ---------------------------------------------------------------- GitHub
if [[ "$offline" == 1 ]]; then
  ((${#stale[@]})) && add worktrees ok "task worktrees: ${stale[*]} (not checked against the board offline)"
  finish; exit
fi

auth="$(gh auth status --active 2>&1 || true)"
acct="$(sed -n 's/.*Logged in to github.com account \([^ ]*\).*/\1/p' <<<"$auth" | head -n1)"
if [[ -z "$acct" ]]; then add gh_auth fail "gh is not logged in" "! gh auth login"; finish; exit; fi
scopes=()
for s in project workflow repo; do grep -q "Token scopes:.*'$s'" <<<"$auth" || scopes+=("$s"); done
if ((${#scopes[@]})); then add gh_auth fail "account $acct lacks scopes: ${scopes[*]}" "! gh auth refresh -h github.com -s project,workflow"
else add gh_auth ok "account $acct with project, workflow, repo scopes"; fi

if [[ -n "$PROJECT_ID" ]]; then
  fields="$(gh api graphql -f query='query($id:ID!){node(id:$id){... on ProjectV2{title closed
             fields(first:50){nodes{... on ProjectV2FieldCommon{name}
             ... on ProjectV2SingleSelectField{options{name}}}}}}}' -F id="$PROJECT_ID" 2>/dev/null || true)"
  if ! jq -e '.data.node.title' >/dev/null 2>&1 <<<"$fields"; then
    add board fail "project ${PROJECT_ID} cannot be read" "check the account, then board.sh bootstrap --project <n>"
  else
    have="$(jq -c '[.data.node.fields.nodes[].name]' <<<"$fields")"
    statuses="$(jq -c '[.data.node.fields.nodes[] | select(.name == "Status") | .options[].name]' <<<"$fields")"
    lack="$(jq -r --argjson h "$have" --argjson s "$statuses" --arg want "$(IFS=,; echo "${STATUSES[*]}")" \
      '(["Status","Priority","Size","Wave","Agent","Attempts"] - $h) + (($want | split(",")) - $s | map("Status:" + .)) | join(", ")' <<<'null')"
    if [[ "$(jq -r .data.node.closed <<<"$fields")" == true ]]; then add board fail "the project is closed" "reopen it on GitHub"
    elif [[ -n "$lack" ]]; then add board fail "missing on the board: $lack" "board.sh bootstrap --project $(cfg .project_number)"
    else add board ok "$(jq -r .data.node.title <<<"$fields"): fields and Status columns present"; fi
    if ! wfs="$("$SQUAD_SCRIPTS/board.sh" workflows 2>/dev/null)"; then
      add project_workflows warn "cannot list the project's built-in workflows" "board.sh workflows (check the project scope)"
    elif conf="$(jq -r '[.[] | select(.conflicts and .enabled) | .name] | join(", ")' <<<"$wfs")" && [[ -n "$conf" ]]; then add project_workflows fail "enabled workflows that set Status behind squad: $conf" "board.sh workflows --fix (deletes them), or disable them in the project settings"
    else add project_workflows ok "no conflicting built-in workflow"; fi
  fi
fi

if [[ -n "$OWNER" && -n "$REPO" ]]; then
  want="$(jq -r '.[]' <<<'["type:epic","type:story","type:task","type:bug","type:report","qa:failed","review:changes","review:passed","needs-split","needs-rebase","needs-human","blocked","quick"]')"
  got="$(gh label list --repo "$OWNER/$REPO" --limit 200 --json name -q '.[].name' 2>/dev/null || true)"
  lbl=(); while read -r l; do grep -qxF "$l" <<<"$got" || lbl+=("$l"); done <<<"$want"
  if ((${#lbl[@]})); then add labels fail "missing labels: ${lbl[*]}" "issue.sh labels"
  else add labels ok "all squad labels exist"; fi

  rs="$(gh api "repos/$OWNER/$REPO" 2>/dev/null || echo '{}')"
  if [[ "$(jq -r '.allow_squash_merge' <<<"$rs")" == true && "$(jq -r '.delete_branch_on_merge' <<<"$rs")" == true ]]; then
    add merge_settings ok "squash merge on, branches deleted after merge"
  else add merge_settings warn "squash merge or delete-branch-on-merge is off" "setup step 5 (gh repo edit …)"; fi

  if gh api "repos/$OWNER/$REPO/branches/main/protection" >/dev/null 2>&1; then add branch_protection ok "main is protected"
  else add branch_protection warn "main is not protected (or not visible): nothing stops a push to main" "setup step 5; needs a public repo or GitHub Pro/Team"; fi

  envs="$(gh api "repos/$OWNER/$REPO/environments" --jq '[.environments[] | {name, reviewers: ([.protection_rules[]? | select(.type == "required_reviewers")] | length)}]' 2>/dev/null || echo '[]')"
  pe="$(cfg .deploy.production_environment)"; pe="${pe:-production}"
  [[ "$deploys" == 1 ]] || pe=""
  for e in ${pe:+staging "$pe"}; do
    if ! jq -e --arg e "$e" '.[] | select(.name == $e)' >/dev/null <<<"$envs"; then
      add "environment:$e" warn "GitHub Environment $e is missing" "setup step 8"; continue
    fi
    sec="$(gh secret list --repo "$OWNER/$REPO" --env "$e" --json name -q '.[].name' 2>/dev/null || true)"
    if [[ "$e" == "$pe" && "$(jq -r --arg e "$e" '.[] | select(.name == $e) | .reviewers' <<<"$envs")" == 0 ]]; then
      add "environment:$e" fail "no required reviewer: production would deploy without GATE 3" "setup step 8 (required reviewer = the stakeholder)"
    elif [[ "$(cfg .deploy.platform)" == railway ]] && ! grep -qx RAILWAY_TOKEN <<<"$sec"; then
      add "environment:$e" warn "secret RAILWAY_TOKEN is not set" "the stakeholder runs: gh secret set RAILWAY_TOKEN --env $e"
    else add "environment:$e" ok "exists$([[ "$e" == "$pe" ]] && echo ", with a required reviewer")"; fi
  done

  if ((${#stale[@]})); then
    old=()
    for n in "${stale[@]}"; do
      st="$(gh issue view "$n" --repo "$OWNER/$REPO" --json state -q .state 2>/dev/null || echo UNKNOWN)"
      [[ "$st" == OPEN ]] || old+=("$n")
    done
    if ((${#old[@]})); then add worktrees warn "worktrees of closed issues: ${old[*]}" "worktree.sh clean <issue> --delete-branch --pr-merged for each"
    else add worktrees ok "task worktrees: ${stale[*]} (all open)"; fi
  fi
fi
finish
