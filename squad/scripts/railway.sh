#!/usr/bin/env bash
# railway.sh: squad's only way to Railway. Uses the Railway CLI with the stakeholder's own
# login (`railway login`, OAuth, once per machine): no Railway token is stored anywhere.
#
# Usage:
#   railway.sh check                    CLI installed, logged in, project reachable. JSON
#   railway.sh status <env>             services in <env>: latest deployment, start and
#                                       pre-deploy command, healthcheck. JSON
#   railway.sh logs <env> [--build | --http] [--service S] [--deployment ID] [--lines N]
#                     [--since 1h] [--filter QUERY] [--status 500..599] [--latest]
#                                       recent logs (deployment logs by default, 200 lines)
#   railway.sh errors <env> [--since 1h] [--service S]
#                                       error scan: app log lines at level error and HTTP 5xx
#                                       responses in the period, grouped. JSON (never fails on
#                                       errors found: read app_errors and http_5xx)
#   railway.sh deployments <env> [--service S] [--limit N]
#                                       recent deployments: id, status, time, can roll back
#   railway.sh vars <env> [--service S] variable NAMES only; values are never printed
#  Changes (production also needs --approved "<the stakeholder's words>" and --issue N):
#   railway.sh deploy <env> <sha> [--service S] [--gate-run <id>]
#                                       deploy exactly that commit (clean worktree, `railway up`),
#                                       wait for the result. JSON {deployment, status, url}.
#                                       Production: --gate-run = the approved release-gate run
#                                       (checked on GitHub) instead of --approved
#   railway.sh set-var <env> KEY=VALUE [--service S] [--skip-deploys]
#                                       non-secret values and references (${{Postgres.DATABASE_URL}});
#                                       secret-looking names or values are refused (exit 3)
#   railway.sh add-db <env> postgres|mysql|redis|mongo
#   railway.sh config <env> <setting> <value> [--service S]
#                                       service setting: preDeployCommand, startCommand,
#                                       buildCommand, healthcheckPath, healthcheckTimeout,
#                                       rootDirectory, numReplicas, sleepApplication, cronSchedule
#   railway.sh domain <env> [--service S]
#                                       the public URL; generates a Railway domain when there is none
#   railway.sh redeploy <env> [--service S]
#   railway.sh rollback <env> <deployment-id>
#
# <env> is staging or production, mapped by deploy.railway.environments; the project is
# deploy.railway.project and the default service deploy.railway.service.
# Every change is recorded as a comment on --issue (required for production).
# Exit: 0 ok, 3 refused by a rule, 4 deploy failed or timed out, 5 CLI missing or not
# logged in, 1 other errors. $SQUAD_RAILWAY overrides the CLI binary (tests).
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RW="${SQUAD_RAILWAY:-railway}"

refuse() { EXIT_CODE=3 die "$*"; }
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]]; exit ;; esac

command -v "$RW" >/dev/null 2>&1 || EXIT_CODE=5 die "Railway CLI not found: install it (https://docs.railway.com/cli), then run: railway login"
need jq git
load_config
PROJECT="$(cfg .deploy.railway.project)"
[[ -n "$PROJECT" ]] || die "deploy.railway.project is empty in $(config_path) (run the setup skill)"
SERVICE="$(cfg .deploy.railway.service)"; SERVICE="${SERVICE:-web}"

# ---------------------------------------------------------------- arguments
ENV_KEY="" ENV_NAME="" gate_run="" since="" status="" latest="" approved="" issue="" service="$SERVICE" lines=200 kind="-d" deployment="" filter="" limit=10 skip=""
pos=()
parse() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --approved) approved="${2:?--approved needs the words of the stakeholder}"; shift 2 ;;
      --issue) issue="${2:?}"; issue="${issue#\#}"; shift 2 ;;
      --service) service="${2:?}"; shift 2 ;;
      --lines) lines="${2:?}"; shift 2 ;;
      --build) kind="-b"; shift ;;
      --http) kind="--http"; shift ;;
      --deployment) deployment="${2:?}"; shift 2 ;;
      --filter) filter="${2:?}"; shift 2 ;;
      --limit) limit="${2:?}"; shift 2 ;;
      --skip-deploys) skip="--skip-deploys"; shift ;;
      --gate-run) gate_run="${2:?}"; shift 2 ;;
      --since) since="${2:?}"; shift 2 ;;
      --status) status="${2:?}"; shift 2 ;;
      --latest) latest=1; shift ;;
      *) pos+=("$1"); shift ;;
    esac
  done
}
parse "$@"
env_arg() {
  ENV_KEY="${pos[0]:-}"
  [[ "$ENV_KEY" == staging || "$ENV_KEY" == production ]] || die "first argument must be staging or production"
  ENV_NAME="$(cfg ".deploy.railway.environments.$ENV_KEY")"; ENV_NAME="${ENV_NAME:-$ENV_KEY}"
}

logged_in() {
  "$RW" whoami --json >/dev/null 2>&1 \
    || EXIT_CODE=5 die "not logged in to Railway: the stakeholder runs  ! railway login  (OAuth in the browser)"
}

api() { # api <query> [--raw-var k=v ...] : GraphQL through the CLI, errors are fatal
  local q="$1" out; shift
  out="$("$RW" api --compact "$@" "$q" 2>&1)" || die "Railway API call failed: $out"
  jq -e '.errors | not' >/dev/null 2>&1 <<<"$out" || die "Railway API error: $(jq -r '[.errors[]?.message] | join("; ")' <<<"$out")"
  echo "$out"
}

project_json() {
  api 'query($id:String!){project(id:$id){id name environments{edges{node{id name
         serviceInstances{edges{node{serviceId serviceName startCommand preDeployCommand healthcheckPath
           domains{serviceDomains{domain} customDomains{domain}}
           latestDeployment{id status createdAt staticUrl}}}}}}}}}' --raw-var "id=$PROJECT"
}
env_json() { # the environment object for ENV_NAME
  project_json | jq -c --arg e "$ENV_NAME" '.data.project.environments.edges[].node | select(.name == $e)' \
    | grep . || die "environment '$ENV_NAME' not found in Railway project $PROJECT"
}

# production changes: the stakeholder's approval, quoted, and an issue to record it on
guard_change() { # guard_change <description>
  if [[ "$ENV_KEY" == production ]]; then
    [[ -n "$approved" && -n "$issue" ]] \
      || refuse "production change needs --approved \"<the stakeholder's words>\" and --issue <n> (ask the PM to get the approval)"
  fi
  CHANGE="$1"
}
record() { # record <result line> : comment the change on --issue
  [[ -n "$issue" ]] || return 0
  local body repo; repo="$(cfg .owner)/$(cfg .repo)"
  body="$(printf 'Railway change (%s, %s): %s\n\nResult: %s' "$ENV_KEY" "$ENV_NAME" "$CHANGE" "$1")"
  [[ -n "$approved" ]] && body="$(printf '%s\n\nApproved by the stakeholder: "%s"' "$body" "$approved")"
  gh issue comment "$issue" --repo "$repo" --body "$body" >/dev/null || warn "could not comment on #$issue"
}

# ---------------------------------------------------------------- read
cmd_check() {
  local who p
  who="$("$RW" whoami --json 2>/dev/null)" \
    || EXIT_CODE=5 die "not logged in to Railway: the stakeholder runs  ! railway login  (OAuth in the browser)"
  p="$(project_json)"
  jq -n --argjson w "$who" --argjson p "$p" --arg s "$SERVICE" \
    '{user: ($w.email // $w.name), project: $p.data.project.name, project_id: $p.data.project.id, service: $s,
      environments: [$p.data.project.environments.edges[].node | {name, services: [.serviceInstances.edges[].node.serviceName]}]}'
}

cmd_status() {
  env_arg; logged_in
  env_json | jq '{environment: .name, services: [.serviceInstances.edges[].node | {service: .serviceName,
      start: .startCommand, pre_deploy: .preDeployCommand, healthcheck: .healthcheckPath,
      deployment: .latestDeployment.id, status: .latestDeployment.status, at: .latestDeployment.createdAt,
      url: ([.domains.customDomains[]?.domain, .domains.serviceDomains[]?.domain, .latestDeployment.staticUrl]
            | map(select(. != null)) | if length > 0 then "https://" + .[0] else null end)}]}'
}

cmd_logs() {
  env_arg; logged_in
  local args=(logs -p "$PROJECT" -e "$ENV_NAME" -s "$service" --lines "$lines" "$kind")
  [[ -n "$filter" ]] && args+=(--filter "$filter")
  [[ -n "$since" ]] && args+=(--since "$since")
  [[ -n "$status" ]] && args+=(--status "$status")
  [[ -n "$latest" ]] && args+=(--latest)
  [[ -n "$deployment" ]] && args+=("$deployment")
  "$RW" "${args[@]}"
}

cmd_errors() {
  env_arg; logged_in
  local p="${since:-1h}" app http
  app="$("$RW" logs -p "$PROJECT" -e "$ENV_NAME" -s "$service" -d --since "$p" --lines 500 \
           --filter "@level:error" --json 2>/dev/null || true)"
  http="$("$RW" logs -p "$PROJECT" -e "$ENV_NAME" -s "$service" --http --since "$p" --lines 500 \
           --status 500..599 --json 2>/dev/null || true)"
  jq -n --arg e "$ENV_KEY" --arg p "$p" --arg app "$app" --arg http "$http" '
    def rows($s): [$s | split("\n")[] | select(length > 0) | (fromjson? // {message: .})];
    rows($app) as $a | rows($http) as $h
    | {environment: $e, since: $p,
       app_errors: ($a | length),
       top_errors: ($a | group_by(.message | tostring | .[0:160]) | map({message: (.[0].message | tostring | .[0:300]), count: length})
                    | sort_by(-.count) | .[0:10]),
       http_5xx: ($h | length),
       top_paths: ($h | group_by((.method // "") + " " + ((.path // .attributes.path // .message) | tostring))
                    | map({request: ((.[0].method // "") + " " + ((.[0].path // .[0].attributes.path // .[0].message) | tostring)),
                           status: (.[0].httpStatus // .[0].status // null), count: length})
                    | sort_by(-.count) | .[0:10])}'
}

ids() { # prints "<environment id> <service id>" for ENV_NAME and $service
  env_json | jq -r --arg s "$service" '.id + " " + ([.serviceInstances.edges[].node | select(.serviceName == $s) | .serviceId][0] // "")'
}

cmd_deployments() {
  env_arg; logged_in
  local e s idp; idp="$(ids)"; read -r e s <<<"$idp"; [[ -n "$s" ]] || die "service '$service' not found in $ENV_NAME"
  api 'query($p:String!,$e:String!,$s:String!,$n:Int!){deployments(first:$n,input:{projectId:$p,environmentId:$e,serviceId:$s}){
         edges{node{id status createdAt canRollback meta}}}}' \
      --raw-var "p=$PROJECT" --raw-var "e=$e" --raw-var "s=$s" --var "n=$limit" \
    | jq '[.data.deployments.edges[].node | {id, status, at: .createdAt, can_rollback: .canRollback,
            commit: (.meta.commitHash // ((.meta.cliMessage // "") | capture("deploy (?<s>[0-9a-f]{7,40})").s) // null),
            message: (.meta.cliMessage // .meta.commitMessage // .meta.reason // null)}]'
}

cmd_vars() {
  env_arg; logged_in
  # the CLI prints raw values: keep them inside this process, print the names only
  "$RW" variable list -p "$PROJECT" -e "$ENV_NAME" -s "$service" --json 2>/dev/null | jq -c 'keys' \
    || die "cannot list variables of $service in $ENV_NAME"
}

# ---------------------------------------------------------------- change
cmd_deploy() {
  env_arg; logged_in
  local sha="${pos[1]:-}"; [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || die "usage: railway.sh deploy <env> <commit sha>"
  if [[ "$ENV_KEY" == production && -n "$gate_run" ]]; then   # GATE 3 approved on GitHub
    local repo run; repo="$(cfg .owner)/$(cfg .repo)"
    run="$(gh run view "$gate_run" --repo "$repo" --json displayTitle,url,jobs)" || die "release-gate run $gate_run not found"
    jq -e --arg s "$sha" '(.displayTitle | contains($s)) and any(.jobs[]; .name == "production" and .conclusion == "success")' \
        >/dev/null <<<"$run" \
      || refuse "release-gate run $gate_run is not an approved GATE 3 for $sha (production job must have succeeded)"
    approved="GATE 3 approved on GitHub: $(jq -r .url <<<"$run")"
  fi
  guard_change "deploy commit $sha to service $service"
  local root wt log e s dep st
  root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  wt="$root/.worktrees/deploy-$ENV_KEY"; log="$root/.worktrees/deploy-$ENV_KEY.log"
  git -C "$root" fetch --quiet origin
  git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null || die "commit $sha not found (push it first)"
  if [[ -d "$wt" ]]; then git -C "$wt" checkout --quiet --detach --force "$sha"; git -C "$wt" clean -qfdx
  else git -C "$root" worktree add --quiet --detach "$wt" "$sha"; fi
  local idp; idp="$(ids)"; read -r e s <<<"$idp"
  [[ -n "$s" ]] || die "service '$service' not found in $ENV_NAME (create it, or set deploy.railway.service)"
  # --detach: `up --ci` keeps streaming the running app's logs and never returns
  if ! (cd "$wt" && "$RW" up --detach -p "$PROJECT" -e "$ENV_NAME" -s "$service" -m "squad: deploy $sha") > "$log" 2>&1; then
    tail -n 40 "$log" >&2
    record "upload failed (log: .worktrees/deploy-$ENV_KEY.log)"
    EXIT_CODE=4 die "upload of $sha to $ENV_NAME failed; log in $log"
  fi
  local id; id="$(grep -oE 'id=[0-9a-f-]{36}' "$log" | tail -n1 | cut -d= -f2 || true)"
  [[ -n "$id" ]] || die "could not read the deployment id from the railway up output ($log)"
  for _ in $(seq 1 90); do   # build + deploy, up to 15 minutes
    dep="$(api 'query($id:String!){deployment(id:$id){id status staticUrl}}' --raw-var "id=$id" | jq -c '.data.deployment')"
    st="$(jq -r '.status // empty' <<<"$dep")"
    case "$st" in
      SUCCESS)
        record "deployment $id SUCCESS"
        jq -c --arg env "$ENV_KEY" --arg sha "$sha" \
          '{environment: $env, sha: $sha, deployment: .id, status, url: (if .staticUrl then "https://" + .staticUrl else null end)}' <<<"$dep"
        return ;;
      FAILED|CRASHED|REMOVED|SKIPPED)
        { echo "--- build log"; "$RW" logs -p "$PROJECT" -e "$ENV_NAME" -s "$service" --lines 40 -b "$id" || true
          echo "--- deploy log"; "$RW" logs -p "$PROJECT" -e "$ENV_NAME" -s "$service" --lines 60 -d "$id" || true; } >&2
        record "deployment $id $st"
        EXIT_CODE=4 die "deployment $id of $sha on $ENV_NAME ended $st (logs above)" ;;
    esac
    sleep 10
  done
  record "still not finished after 15 minutes"
  EXIT_CODE=4 die "deployment of $sha on $ENV_NAME did not finish within 15 minutes"
}

secret_like() { # secret_like <key> <value>
  local k="${1^^}" v="$2"
  [[ "$v" =~ ^\$\{\{[^}]+\}\}$ ]] && return 1          # a reference to another service's variable
  [[ "$k" =~ (SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE|CREDENTIAL|_DSN$|SMTP_URL|DATABASE_URL|REDIS_URL|MONGO_URL) ]] && return 0
  [[ "$v" =~ ://[^/@:]+:[^/@]+@ ]] && return 0          # user:password@ inside a URL
  return 1
}

cmd_set_var() {
  env_arg; logged_in
  local kv="${pos[1]:-}"; [[ "$kv" == *=* ]] || die "usage: railway.sh set-var <env> KEY=VALUE"
  local k="${kv%%=*}" v="${kv#*=}"
  [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid variable name '$k'"
  if secret_like "$k" "$v"; then
    refuse "$k looks like a secret: agents never handle secrets. The stakeholder sets it:  ! railway variable set $k --stdin -p $PROJECT -e $ENV_NAME -s $service"
  fi
  guard_change "set variable $k on service $service"
  "$RW" variable set "$k=$v" -p "$PROJECT" -e "$ENV_NAME" -s "$service" ${skip:+"$skip"} --json >/dev/null \
    || die "setting $k failed"
  record "$k set"
  jq -nc --arg e "$ENV_KEY" --arg k "$k" --arg s "$service" '{environment: $e, service: $s, set: $k}'
}

cmd_add_db() {
  env_arg; logged_in
  local db="${pos[1]:-}"; in_list "$db" postgres mysql redis mongo || die "usage: railway.sh add-db <env> postgres|mysql|redis|mongo"
  guard_change "add a $db database"
  local tmp out; tmp="$(mktemp -d)"
  # `railway add` has no --project flag: link a throwaway directory, never the repository
  out="$(cd "$tmp" && "$RW" link -p "$PROJECT" -e "$ENV_NAME" --json >/dev/null && "$RW" add --database "$db" --json 2>&1)" \
    || { rm -rf "$tmp"; die "adding $db failed: $out"; }
  rm -rf "$tmp"
  record "$db added"
  # the CLI mixes prompts into its output: keep its last JSON line
  jq -nc --arg e "$ENV_KEY" --arg d "$db" --arg out "$out" \
    '{environment: $e, added: $d} + ([$out | split("\n")[] | fromjson? | objects] | last // {} | {service: .serviceName, service_id: .serviceId})'
}

# service settings that may be changed, with their GraphQL type (the CLI's
# `environment edit --service-config` reports "No changes to apply" for these: use the API)
SETTINGS='{"preDeployCommand":"list","startCommand":"string","buildCommand":"string","healthcheckPath":"string",
  "healthcheckTimeout":"int","rootDirectory":"string","numReplicas":"int","sleepApplication":"bool","cronSchedule":"string"}'

cmd_config() {
  env_arg; logged_in
  local key="${pos[1]:-}" value="${pos[2]:-}" type input e s idp
  [[ -n "$key" && ${#pos[@]} -ge 3 ]] || die "usage: railway.sh config <env> <setting> <value>"
  key="${key#deploy.}"; key="${key#build.}"
  [[ "$key" == variables.* ]] && refuse "use set-var for variables"
  type="$(jq -r --arg k "$key" '.[$k] // empty' <<<"$SETTINGS")"
  [[ -n "$type" ]] || refuse "setting '$key' is not supported; one of: $(jq -r 'keys | join(", ")' <<<"$SETTINGS")"
  input="$(jq -nc --arg k "$key" --arg v "$value" --arg t "$type" '{($k): (
            if $t == "list" then ($v | fromjson? // [$v]) elif $t == "int" then ($v | tonumber)
            elif $t == "bool" then ($v == "true") else $v end)}')" || die "invalid value for $key: $value"
  guard_change "set $key = $value on service $service"
  idp="$(ids)"; read -r e s <<<"$idp"; [[ -n "$s" ]] || die "service '$service' not found in $ENV_NAME"
  api 'mutation($s:String!,$e:String!,$i:ServiceInstanceUpdateInput!){serviceInstanceUpdate(serviceId:$s,environmentId:$e,input:$i)}' \
      --raw-var "s=$s" --raw-var "e=$e" --variables "$(jq -nc --arg s "$s" --arg e "$e" --argjson i "$input" '{s: $s, e: $e, i: $i}')" >/dev/null
  record "done (applies to the next deployment)"
  jq -nc --arg env "$ENV_KEY" --arg s "$service" --argjson i "$input" '{environment: $env, service: $s, set: $i}'
}

cmd_domain() {
  env_arg; logged_in
  local cur out
  cur="$(env_json | jq -r --arg s "$service" '[.serviceInstances.edges[].node | select(.serviceName == $s)
          | .domains.customDomains[]?.domain, .domains.serviceDomains[]?.domain][0] // empty')"
  if [[ -n "$cur" ]]; then jq -nc --arg e "$ENV_KEY" --arg d "$cur" '{environment: $e, url: ("https://" + $d), created: false}'; return; fi
  guard_change "generate a public Railway domain for $service"
  out="$("$RW" domain -s "$service" -e "$ENV_NAME" --project "$PROJECT" --json 2>&1)" || die "domain generation failed: $out"
  cur="$(grep -oE '[a-z0-9.-]+\.up\.railway\.app' <<<"$out" | head -n1 || true)"
  record "domain ${cur:-generated}"
  jq -nc --arg e "$ENV_KEY" --arg d "$cur" '{environment: $e, url: (if $d == "" then null else "https://" + $d end), created: true}'
}

cmd_redeploy() {
  env_arg; logged_in
  guard_change "redeploy the latest deployment of $service"
  "$RW" service redeploy -p "$PROJECT" -e "$ENV_NAME" -s "$service" -y --json >/dev/null || die "redeploy failed"
  record "redeploy started"
  jq -nc --arg e "$ENV_KEY" --arg s "$service" '{environment: $e, service: $s, redeploy: "started"}'
}

cmd_rollback() {
  env_arg; logged_in
  local id="${pos[1]:-}"; [[ -n "$id" ]] || die "usage: railway.sh rollback <env> <deployment-id> (see: railway.sh deployments <env>)"
  guard_change "roll back $service to deployment $id"
  api 'mutation($id:String!){deploymentRollback(id:$id)}' --raw-var "id=$id" >/dev/null
  record "rollback to $id started"
  jq -nc --arg e "$ENV_KEY" --arg id "$id" '{environment: $e, rollback_to: $id, status: "started"}'
}

case "$cmd" in
  check) cmd_check ;;
  status|logs|errors|deployments|vars|deploy|domain|redeploy|rollback) "cmd_$cmd" ;;
  set-var) cmd_set_var ;;
  add-db) cmd_add_db ;;
  config) cmd_config ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
