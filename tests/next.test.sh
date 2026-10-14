# shellcheck shell=bash disable=SC2016,SC2034
# next.sh against a fake board (gh stub)
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
T="$(mktemp -d)"; export GH_STUB="$T/stub.sh" GH_LOG="$T/gh.log"
cat > "$T/items.json" <<'JSON'
[
 {"number": 10, "type": "story", "status": "Todo", "priority": "P1"},
 {"number": 11, "type": "task", "status": "Todo", "parent": 10, "size": "XS", "wave": 1, "priority": "P1", "body": "- **Depends on:** none"},
 {"number": 12, "type": "task", "status": "Todo", "parent": 10, "size": "M", "wave": 1, "body": "- **Depends on:** #13"},
 {"number": 13, "type": "task", "status": "In Progress", "parent": 10, "size": "S", "agent": "dev-1"},
 {"number": 14, "type": "task", "status": "In Review", "parent": 10, "size": "S"},
 {"number": 15, "type": "task", "status": "QA", "size": "XS", "labels": ["quick"]},
 {"number": 16, "type": "task", "status": "In Review", "parent": 10, "size": "S"},
 {"number": 17, "type": "bug", "status": "Todo", "priority": "P0"},
 {"number": 20, "type": "story", "status": "Done", "milestone": null},
 {"number": 21, "type": "task", "status": "Done", "parent": 20, "size": "S"}
]
JSON
python3 "$FIX/board.py" "$T/items.json" next > "$T/next.json"
python3 "$FIX/board.py" "$T/items.json" board > "$T/board.json"
cat > "$T/prs.json" <<'JSON'
[{"number": 101, "title": "feat: a (#14)", "body": "Closes #14", "labels": [], "headRefName": "feat/14-a", "isDraft": false, "closingIssuesReferences": []},
 {"number": 102, "title": "feat: b (#16)", "body": "Closes #16", "labels": [{"name": "needs-rebase"}], "headRefName": "feat/16-b", "isDraft": false, "closingIssuesReferences": [{"number": 16}]}]
JSON
cat > "$GH_STUB" <<STUB
respond() {
  case "\$*" in
    *graphql*fieldValueByName*) cat "$T/next.json" ;;
    *graphql*fieldValues*) cat "$T/board.json" ;;
    "pr list"*) cat "$T/prs.json" ;;
    *milestones*|*releases*|"run list"*) echo '[]' ;;
    *) echo "unexpected gh call: \$*" >&2; return 1 ;;
  esac
}
STUB
out="$("$S/next.sh")" || bad "next.sh runs" "$(tail -3 "$GH_LOG")"
act() { jq -c --arg a "$1" "[.actions[] | select(.action == \$a) | $2]" <<<"$out"; }
eq "ready XS task gets the free slot 2 and the XS dev model" "$(act dev '{issue, slot, model}')" '[{"issue":11,"slot":2,"model":"sonnet"}]'
eq "PR without a verdict is reviewed (S review model: opus)" "$(act review '{pr, issue, model}')" '[{"pr":101,"issue":14,"model":"opus"}]'
eq "quick task in QA is a quick check (XS QA model)" "$(act qa '{issue, quick, model}')" '[{"issue":15,"quick":true,"model":"sonnet"}]'
eq "rebase waits when no developer slot is left" "$(act rebase '.pr')" '[]'
check "the held rebase is explained in notes" 'jq -e ".notes | map(test(\"rebase of PR #102\")) | any" <<<"$out" >/dev/null'
eq "unplanned P0 bug goes to planning" "$(act plan '.tasks')" '[[17]]'
check "batch respects parallel.max_agents (3)" 'jq -e ".batch | length <= 3" <<<"$out" >/dev/null'
eq "Done story with tasks in no milestone is unreleased" "$(jq -c .unreleased <<<"$out")" '[20]'
jq '(.[] | select(.number == 11)).status = "Done"' "$T/items.json" > "$T/i2.json"
python3 "$FIX/board.py" "$T/i2.json" next > "$T/next.json"; python3 "$FIX/board.py" "$T/i2.json" board > "$T/board.json"
out="$("$S/next.sh")"
eq "with no developer to start, the rebase gets the free slot" "$(act rebase '{pr, slot}')" '[{"pr":102,"slot":2}]'
python3 "$FIX/board.py" "$T/items.json" next > "$T/next.json"; python3 "$FIX/board.py" "$T/items.json" board > "$T/board.json"
out="$("$S/next.sh" --scope '#10')"
eq "an open P0 bug stays in scope of an unrelated run" "$(act plan '.tasks')" '[[17]]'
check "the quick task outside the scope is left alone" '[[ "$(act qa .issue)" == "[]" ]]'
mkdir -p docs/requirements/foo
printf -- '- **Status:** confirmed\n' > docs/requirements/foo/questions.md
printf '# Foo\n' > docs/requirements/foo/requirements.md
out="$("$S/next.sh")"
eq "settled questions without sign-off: GATE 1 stands alone in the batch" "$(jq -c '[.batch[].action]' <<<"$out")" '["gate_1"]'
printf '# Foo\nSigned-off: 2026-10-14 by C\n' > docs/requirements/foo/requirements.md
mkdir -p docs/requirements/foo/stories; printf '# S-01: x\n' > docs/requirements/foo/stories/S-01-x.md
out="$("$S/next.sh")"
eq "signed requirements with unpublished stories: GATE 2" "$(jq -c '[.batch[].action]' <<<"$out")" '["gate_2"]'
rm -rf docs/requirements
sed -i.bak 's/^  platform: railway.*/  platform: none/' .squad/config.yml
out="$("$S/next.sh")"
eq "deploy.platform none: nothing is unreleased" "$(jq -c .unreleased <<<"$out")" '[]'
cd / && rm -rf "$(dirname "$R")" "$T"
