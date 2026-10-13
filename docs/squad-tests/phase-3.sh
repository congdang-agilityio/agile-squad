#!/usr/bin/env bash
# Phase 3 script tests: waves.sh (offline fixtures) and worktree.sh (on the sandbox clone).
# Usage: cd <sandbox clone> && bash phase-3.sh <path>/squad/scripts
# Self-cleaning: removes the worktrees and remote branches it creates.
set -uo pipefail
S="${1:?usage: phase-3.sh <squad/scripts dir>}"
FIX="$(cd "$(dirname "$0")" && pwd)/fixtures"
pass=0 fail=0
ok()  { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- waves.sh (offline)
W="$("$S/waves.sh" plan --from-json "$FIX/waves-tasks.json")"
check "waves: scaffold (config layer) is alone in the first wave" \
  '[[ "$(jq -c ".waves[0]" <<<"$W")" == "[1]" ]]'
check "waves: migration (Serial: yes) is alone in its wave" \
  'jq -e ".waves[] | select(index(2)) | length == 1" <<<"$W" >/dev/null'
check "waves: independent tasks with distinct files share a wave" \
  'jq -e ".wave_of[\"3\"] == .wave_of[\"4\"]" <<<"$W" >/dev/null'
check "waves: every task comes after all its dependencies" \
  'jq -e --slurpfile t "$FIX/waves-tasks.json" "
     . as \$r | [\$t[0][] | .number as \$n | (.body | [scan(\"#([0-9]+)\")[0] | tonumber] - [34])[]
       | select(\$r.wave_of[tostring] >= \$r.wave_of[\$n | tostring])] | length == 0" <<<"$W" >/dev/null'
check "waves: directory entry src/lib/ never shares a wave with src/lib/*.ts tasks" \
  'jq -e ".wave_of[\"9\"] != .wave_of[\"3\"] and .wave_of[\"9\"] != .wave_of[\"4\"]" <<<"$W" >/dev/null'
check "waves: shared routing file (src/routes.ts) is serialized" \
  'jq -e ".serial | index(8)" <<<"$W" >/dev/null'
check "waves: no wave exceeds max parallel (2)" \
  'jq -e "[.waves[] | length] | max <= 2" <<<"$W" >/dev/null'
W3="$("$S/waves.sh" plan --from-json "$FIX/waves-tasks.json" --max-parallel 3 --start 5)"
check "waves: --start and --max-parallel are honored" \
  'jq -e ".first_wave == 5 and ([.waves[] | length] | max) == 3" <<<"$W3" >/dev/null'
jq '.[0].body |= sub("none"; "#9")' "$FIX/waves-tasks.json" > "$TMP/cycle.json"   # 1 -> 9 -> 1
check "waves: a dependency cycle is an error" \
  '! "$S/waves.sh" plan --from-json "$TMP/cycle.json" >/dev/null 2>&1'
jq '.[2].body |= sub("## Files \\(expected\\)\n[^#]*"; "")' "$FIX/waves-tasks.json" > "$TMP/nofiles.json"
WN="$("$S/waves.sh" plan --from-json "$TMP/nofiles.json")"
check "waves: a task without Files (expected) is warned about and serialized" \
  'jq -e "(.warnings | length) == 1 and (.serial | index(3))" <<<"$WN" >/dev/null'

WT="$("$S/waves.sh" plan --from-json "$FIX/waves-todonow.json")"
check "waves: real TodoNow plan (14 tasks, 6 serial) packs into <= 11 waves with parallel pairs" \
  'jq -e "(.waves | length) <= 11 and ([.waves[] | select(length == 2)] | length) >= 3" <<<"$WT" >/dev/null'
check "waves: dotfile paths keep their leading dot" \
  'jq -e ".files[\"95\"] | index(\".github/workflows/ci.yml\")" <<<"$WT" >/dev/null'
check "waves: Next.js route.ts endpoints are not treated as shared routing" \
  'jq -e "(.serial | index(102) | not) and (.serial | index(106) | not)" <<<"$WT" >/dev/null'

# ---------------------------------------------------------------- worktree.sh (sandbox)
ROOT="$(git rev-parse --show-toplevel)"
J="$("$S/worktree.sh" 35 1)"
check "worktree: creates .worktrees/35 on a new feat/35-* branch from origin/main" \
  '[[ "$(jq -r .branch <<<"$J")" == feat/35-* && -d "$ROOT/.worktrees/35" ]] && jq -e .new_branch <<<"$J" >/dev/null'
check "worktree: slot 1 gets port 4101 and test db app_test_1" \
  'grep -qx "PORT=4101" "$ROOT/.worktrees/35/.env.local" && grep -qx "TEST_DB_NAME=app_test_1" "$ROOT/.worktrees/35/.env.local"'
check "worktree: main worktree stays clean (.worktrees and .env.local excluded)" \
  '[[ -z "$(git -C "$ROOT" status --porcelain -- .worktrees)" ]] && [[ -z "$(git -C "$ROOT/.worktrees/35" status --porcelain)" ]]'
J2="$("$S/worktree.sh" 35 2)"
check "worktree: re-run reuses the worktree and rewrites the slot env" \
  'jq -e ".new_branch == false and .port == 4102" <<<"$J2" >/dev/null && grep -qx "PORT=4102" "$ROOT/.worktrees/35/.env.local"'
check "worktree: config is found from inside a worktree" \
  '(cd "$ROOT/.worktrees/35" && "$S/worktree.sh" list | jq -e "map(.issue) | index(35)" >/dev/null)'
check "worktree: slot above max_parallel_dev is refused" '! "$S/worktree.sh" 36 9 >/dev/null 2>&1'
echo dirty > "$ROOT/.worktrees/35/dirty.txt"
check "worktree: clean refuses a worktree with uncommitted changes" '! "$S/worktree.sh" clean 35 >/dev/null 2>&1'
rm -f "$ROOT/.worktrees/35/dirty.txt"
git -C "$ROOT/.worktrees/35" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m "test: local work"
JK="$("$S/worktree.sh" clean 35 --delete-branch 2>/dev/null)"
check "worktree: clean keeps a branch with unpushed local commits" \
  '[[ ! -e "$ROOT/.worktrees/35" ]] && jq -e ".branch_deleted == false" <<<"$JK" >/dev/null && git -C "$ROOT" show-ref --quiet --verify "refs/heads/$(jq -r .branch <<<"$JK")"'
"$S/worktree.sh" 35 1 >/dev/null
JC="$("$S/worktree.sh" clean 35 --delete-branch --pr-merged)"
check "worktree: clean --pr-merged removes the worktree and the branch" \
  '[[ ! -e "$ROOT/.worktrees/35" ]] && jq -e .branch_deleted <<<"$JC" >/dev/null'
# a branch that already exists on origin (rework after review) is reused, not recreated
git -C "$ROOT" push --quiet origin "origin/main:refs/heads/feat/36-existing-branch" 2>/dev/null
JR="$("$S/worktree.sh" 36 1)"
check "worktree: an existing remote branch feat/36-* is reused with tracking" \
  '[[ "$(jq -r .branch <<<"$JR")" == feat/36-existing-branch ]] && [[ -n "$(git -C "$ROOT/.worktrees/36" rev-parse --abbrev-ref @{u} 2>/dev/null)" ]]'
"$S/worktree.sh" clean 36 >/dev/null
git -C "$ROOT" push --quiet origin --delete feat/36-existing-branch 2>/dev/null
git -C "$ROOT" branch -D feat/36-existing-branch >/dev/null 2>&1
check "worktree: never uses main" '[[ "$(git -C "$ROOT" branch --show-current)" == main ]]'

echo "----"; echo "passed $pass, failed $fail"
[[ "$fail" == 0 ]]
