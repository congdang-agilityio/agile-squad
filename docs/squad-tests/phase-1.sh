#!/usr/bin/env bash
# Phase 1 acceptance test. Run from a clone of the sandbox repository after `board.sh bootstrap`.
#   bash phase-1.sh /path/to/squad/scripts
set -euo pipefail
shopt -s inherit_errexit
S="${1:?path to squad/scripts}"; B="$S/board.sh"; I="$S/issue.sh"
R="$(date +%H%M%S)"   # run id: closed issues are never reused, so each run uses fresh titles
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok()   { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
# The board listing is eventually consistent (~30 s after adding an issue): wait for it.
wait_listed() {
  local n i
  for i in $(seq 1 30); do
    n=$("$B" list all | jq -c --argjson w "[$(IFS=,; echo "$*")]" '[.[].number] as $have | $w - $have | length')
    [[ "$n" == 0 ]] && return 0; sleep 3
  done
  fail "issues $* never appeared in the board listing"
}
cleanup_issues() { # close and archive the issues this run created
  local n id
  for n in "$@"; do
    id=$("$B" get "$n" | jq -r .item_id)
    gh issue close "$n" -c "Phase 1 board test issue; closing." </dev/null >/dev/null 2>&1 || true
    gh project item-archive "$(cfg_number)" --owner "$(cfg_owner)" --id "$id" </dev/null >/dev/null
  done
}
cfg_owner()  { gh repo view --json owner -q .owner.login; }
cfg_number() { grep '^project_number:' .squad/config.yml | awk '{print $2}'; }

printf 'Phase 1 smoke-test epic.\n' > "$T/epic.md"
printf 'As a tester, I want a story, so that sub-issues work.\n' > "$T/story.md"
printf '## Goal\nDependency target.\n\nDepends on: none\n' > "$T/t1.md"

e=$("$I" create epic "[test $R] Phase 1 epic" "$T/epic.md" --priority P1 | jq .issue)
s=$("$I" create story "[test $R] Phase 1 story" "$T/story.md" --parent "$e" --priority P1 | jq .issue)
a=$("$I" create task "[test $R] Dependency task" "$T/t1.md" --parent "$s" --priority P2 --size XS | jq .issue)
printf '## Goal\nMoves through every status.\n\nDepends on #%s\n' "$a" > "$T/t2.md"
x=$("$I" create task "[test $R] Status walk task" "$T/t2.md" --parent "$s" --priority P1 --size S | jq .issue)
echo "epic=#$e story=#$s dep=#$a walk=#$x"

again=$("$I" create task "[test $R] Status walk task" "$T/t2.md" --parent "$s" 2>/dev/null | jq .issue)
[[ "$again" == "$x" ]] && ok "re-running create reuses #$x" || fail "duplicate issue #$again"
[[ "$("$I" parent "$x")" == "$s" ]] && ok "#$x is a sub-issue of story #$s" || fail "parent link"
[[ "$("$I" parent "$s")" == "$e" ]] && ok "#$s is a sub-issue of epic #$e" || fail "parent link"
kids=$("$I" children "$s" | jq -c '[.[].number] | sort')
[[ "$kids" == "[$a,$x]" ]] && ok "story children are $kids" || fail "children: $kids"

"$B" move "$x" Todo >/dev/null; "$B" move "$a" Todo >/dev/null
wait_listed "$e" "$s" "$a" "$x"; ok "all four issues visible in the board listing"
"$B" set-field "$x" attempts "" >/dev/null
ready=$("$B" ready-tasks | jq -c '[.[].number]')
has() { jq -e --argjson n "$2" 'index($n) != null' <<<"$1" >/dev/null; }
has "$ready" "$a" && ! has "$ready" "$x" && ok "ready-tasks has #$a but not #$x while #$a is not Done" || fail "ready-tasks: $ready"

"$B" set-field "$x" wave 1 >/dev/null; "$B" set-field "$x" agent dev-1 >/dev/null
"$B" bump-attempts "$x" >/dev/null; "$B" bump-attempts "$x" >/dev/null
got=$("$B" get "$x" | jq -c '{priority,size,wave,agent,attempts}')
[[ "$got" == '{"priority":"P1","size":"S","wave":1,"agent":"dev-1","attempts":2}' ]] \
  && ok "fields set: $got" || fail "fields: $got"

for st in Backlog Todo "In Progress" "In Review" QA Done Released; do
  "$B" move "$x" "$st" >/dev/null
  now=$("$B" get "$x" | jq -r .status)
  [[ "$now" == "$st" ]] && ok "#$x moved to $st" || fail "expected $st, got $now"
done
[[ "$("$B" list Released | jq --argjson x "$x" 'map(.number) | index($x) != null')" == true ]] \
  && ok "list Released contains #$x" || fail "list"

"$B" move "$x" Todo >/dev/null; "$B" move "$a" Done >/dev/null
ready=$("$B" ready-tasks | jq -c '[.[].number]')
has "$ready" "$x" && ! has "$ready" "$a" && ok "ready-tasks has #$x once #$a is Done" || fail "ready-tasks: $ready"

"$B" move "$x" Doing 2>/dev/null && fail "accepted unknown status" || ok "rejects unknown status"
"$B" set-field "$x" size L 2>/dev/null && fail "accepted size L" || ok "rejects size L"
"$B" get 99999 2>/dev/null && fail "found #99999" || ok "unknown issue fails cleanly"
cleanup_issues "$x" "$a" "$s" "$e"; ok "test issues closed and archived"
echo "ALL PASSED"
