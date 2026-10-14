# shellcheck shell=bash disable=SC2016,SC2034
# railway.sh against a fake Railway CLI and a fake gh
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
sed -i.bak 's/^    project: ""/    project: "PRJ"/' .squad/config.yml
git add .squad; git commit -q -m config; git push -q origin main 2>/dev/null
SHA="$(git rev-parse HEAD)"
T="$(mktemp -d)"; export RW_STUB="$T/rw.sh" RW_LOG="$T/rw.log" GH_STUB="$T/gh.sh" GH_LOG="$T/gh.log"
PROJECT='{"data":{"project":{"id":"PRJ","name":"app","environments":{"edges":[
 {"node":{"id":"E1","name":"staging","serviceInstances":{"edges":[{"node":{"serviceId":"S1","serviceName":"web","startCommand":null,"preDeployCommand":["npm run db:deploy"],"healthcheckPath":"/api/health","latestDeployment":{"id":"D0","status":"SUCCESS","createdAt":"2026-01-01T00:00:00Z","staticUrl":"web-staging.up.railway.app"}}}]}}},
 {"node":{"id":"E2","name":"production","serviceInstances":{"edges":[{"node":{"serviceId":"S2","serviceName":"web","startCommand":null,"preDeployCommand":null,"healthcheckPath":null,"latestDeployment":null}}]}}}]}}}}'
cat > "$RW_STUB" <<STUB
respond() {
  case "\$*" in
    "whoami --json") [[ -f "$T/logged-out" ]] && return 1; echo '{"name":"Ann","email":"ann@example.com"}' ;;
    api*"project(id"*) echo '$PROJECT' | tr -d '\n' ;;
    api*deployments*) echo '{"data":{"deployments":{"edges":[{"node":{"id":"D9","status":"SUCCESS","createdAt":"2999-01-01T00:00:00Z","staticUrl":"web.up.railway.app","canRollback":true,"meta":{"commitHash":"abc"}}}]}}}' ;;
    api*serviceInstanceUpdate*) echo '{"data":{"serviceInstanceUpdate":true}}' ;;
    api*deploymentRollback*) echo '{"data":{"deploymentRollback":true}}' ;;
    "variable list"*) echo '{"DATABASE_URL":"postgresql://u:supersecret@db/x","APP_BASE_URL":"https://x"}' ;;
    "variable set"*|"environment edit"*|"service redeploy"*|"link"*) echo '{}' ;;
    "add --database"*) echo '{"name":"Postgres"}' ;;
    up*) [[ "\$*" == *--detach* ]] || { echo "up without --detach would hang" >&2; return 1; }
         echo "  Deployment: https://railway.com/project/PRJ/service/S1?id=11111111-2222-3333-4444-555555555555" ;;
    api*"deployment(id"*) echo '{"data":{"deployment":{"id":"11111111-2222-3333-4444-555555555555","status":"SUCCESS","staticUrl":"web.up.railway.app"}}}' ;;
    *"logs"*"@level:error"*"--json"*) printf '%s\n' '{"message":"TypeError: x is undefined"}' '{"message":"TypeError: x is undefined"}' '{"message":"DB timeout"}' ;;
    *"logs"*"--http"*"500..599"*"--json"*) printf '%s\n' '{"method":"POST","path":"/api/tasks","httpStatus":500}' '{"method":"POST","path":"/api/tasks","httpStatus":500}' ;;
    logs*) echo "log line" ;;
    *) echo "unexpected railway call: \$*" >&2; return 1 ;;
  esac
}
STUB
cat > "$GH_STUB" <<STUB
respond() {
  case "\$*" in
    "issue comment"*) echo ok ;;
    "run view 77"*) echo '{"displayTitle":"release gate v1 $SHA","url":"https://gh/run/77","jobs":[{"name":"production","conclusion":"success"}]}' ;;
    "run view 78"*) echo '{"displayTitle":"release gate v1 0000000","url":"https://gh/run/78","jobs":[{"name":"production","conclusion":"success"}]}' ;;
    *) echo "unexpected gh call: \$*" >&2; return 1 ;;
  esac
}
STUB
RS="$S/railway.sh"
eq "check reports user, project and environments" "$("$RS" check | jq -c '[.user, .project, [.environments[].name]]')" '["ann@example.com","app",["staging","production"]]'
eq "status shows the pre-deploy command and URL" "$("$RS" status staging | jq -c '.services[0] | [.pre_deploy, .url]')" '[["npm run db:deploy"],"https://web-staging.up.railway.app"]'
out="$("$RS" vars staging)"
eq "vars prints names only" "$out" '["APP_BASE_URL","DATABASE_URL"]'
check "no secret value reaches the output" '! grep -q supersecret <<<"$out"'
"$RS" set-var staging LOG_LEVEL=debug >/dev/null; eq "a plain staging variable is set" "$?" 0
check "it went to the right project, environment and service" 'grep -q "variable set LOG_LEVEL=debug -p PRJ -e staging -s web" "$RW_LOG"'
"$RS" set-var staging SMTP_PASSWORD=x >/dev/null 2>&1; eq "a secret-looking name is refused" "$?" 3
"$RS" set-var staging API_URL=https://u:p@host >/dev/null 2>&1; eq "credentials inside a URL are refused" "$?" 3
"$RS" set-var staging 'DATABASE_URL=${{Postgres.DATABASE_URL}}' >/dev/null; eq "a reference variable is allowed" "$?" 0
"$RS" set-var production LOG_LEVEL=info >/dev/null 2>&1; eq "production change without approval is refused" "$?" 3
"$RS" set-var production LOG_LEVEL=info --approved "ok, làm đi" --issue 12 >/dev/null; eq "production change with approval and issue works" "$?" 0
check "the approval is recorded on the issue" 'grep -q "issue comment 12" "$GH_LOG"'
"$RS" config staging variables.X 1 >/dev/null 2>&1; eq "variables cannot be set through config" "$?" 3
eq "config sets a service setting through the API" "$("$RS" config staging deploy.preDeployCommand "npm run db:deploy" | jq -c .set)" '{"preDeployCommand":["npm run db:deploy"]}'
"$RS" config staging dockerImage x >/dev/null 2>&1; eq "an unsupported setting is refused" "$?" 3
eq "add-db adds a database" "$("$RS" add-db staging postgres | jq -r .added)" "postgres"
check "add-db links a throwaway directory, not the repository" '! [[ -e .railway ]]'
eq "deploy staging runs railway up and waits for SUCCESS" "$("$RS" deploy staging "$SHA" | jq -c '[.status, .deployment]')" '["SUCCESS","11111111-2222-3333-4444-555555555555"]'
check "the deploy ran from a clean worktree at the commit" '[[ "$(git -C .worktrees/deploy-staging rev-parse HEAD)" == "$SHA" ]]'
"$RS" deploy production "$SHA" >/dev/null 2>&1; eq "production deploy without GATE 3 is refused" "$?" 3
"$RS" deploy production "$SHA" --gate-run 78 --issue 5 >/dev/null 2>&1; eq "a gate run for another commit is refused" "$?" 3
eq "production deploy with the approved gate run" "$("$RS" deploy production "$SHA" --gate-run 77 --issue 5 | jq -r .status)" "SUCCESS"
"$RS" rollback production D1 >/dev/null 2>&1; eq "rollback without approval is refused" "$?" 3
eq "rollback with approval" "$("$RS" rollback production D1 --approved "yes roll back" --issue 9 | jq -r .rollback_to)" "D1"
out="$("$RS" errors production --since 2h)"
eq "errors counts app errors and 5xx" "$(jq -c '[.app_errors, .http_5xx, .since]' <<<"$out")" '[3,2,"2h"]'
eq "errors groups identical messages" "$(jq -c '.top_errors[0]' <<<"$out")" '{"message":"TypeError: x is undefined","count":2}'
eq "errors groups 5xx by request" "$(jq -c '.top_paths[0]' <<<"$out")" '{"request":"POST /api/tasks","status":500,"count":2}'
check "logs passes --since and --status" '"$RS" logs staging --http --since 30m --status 500..599 >/dev/null && grep -q -- "--since 30m --status 500..599" "$RW_LOG"'
touch "$T/logged-out"
"$RS" status staging >/dev/null 2>&1; eq "not logged in exits 5" "$?" 5
cd / && rm -rf "$(dirname "$R")" "$T"
