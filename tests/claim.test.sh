# shellcheck shell=bash disable=SC2016,SC2034
# board.sh claim/release across machines, against a stateful fake gh
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
# fill the ids the claim needs
sed -i.bak 's/^ids:.*/ids:\n  project_id: "PVT_1"\n  agent_field_id: "F_AGENT"/' .squad/config.yml
sed -i.bak '/^  project_id: null/d' .squad/config.yml
T="$(mktemp -d)"; export GH_STUB="$T/stub.sh" GH_LOG="$T/gh.log" STATE="$T"
echo '[]' > "$T/comments.json"; : > "$T/agent"; echo 0 > "$T/seq"
cat > "$GH_STUB" <<'STUB'
respond() {
  local S="$STATE" all="$*"
  case "$all" in
    *"graphql"*"projectItems(first:50){nodes{id isArchived"*)
      jq -n --arg a "$(cat "$S/agent")" '{data:{repository:{issue:{__typename:"Issue",number:7,title:"t",state:"OPEN",body:"",url:"u",
        repository:{nameWithOwner:"acme/app"},labels:{nodes:[]},milestone:null,
        projectItems:{nodes:[{id:"PVTI_7",isArchived:false,project:{id:"PVT_1"},fieldValues:{nodes:(
          [{__typename:"ProjectV2ItemFieldSingleSelectValue",name:"Todo",field:{name:"Status"}}]
          + (if $a == "" then [] else [{__typename:"ProjectV2ItemFieldTextValue",text:$a,field:{name:"Agent"}}] end))}}]}}}}}' ;;
    *"graphql"*"projectItems(first:50){nodes{id project{id}}}"*)
      echo '{"data":{"repository":{"issue":{"id":"I_7","projectItems":{"nodes":[{"id":"PVTI_7","project":{"id":"PVT_1"}}]}}}}}' ;;
    "issue comment 7"*)
      local body="${all##*--body }" n; n=$(( $(cat "$S/seq") + 1 )); echo "$n" > "$S/seq"
      jq --arg b "$body" --argjson id "$((1000 + n))" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [{id:$id, created_at:$t, body:$b}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json"; echo ok ;;
    "api repos/acme/app/issues/7/comments"*) cat "$S/comments.json" ;;
    "api -X DELETE repos/acme/app/issues/comments/"*)
      local id="${all##*/}"; jq --argjson id "$id" 'map(select(.id != $id))' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json" ;;
    "project item-edit"*"--text"*) echo "${all##*--text }" > "$S/agent" ;;
    "project item-edit"*"--clear"*) : > "$S/agent" ;;
    *) echo "unexpected gh call: $*" >&2; return 1 ;;
  esac
}
STUB
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
out="$(SQUAD_HOST=laptop-a "$S/board.sh" claim 7 dev-1)"; rc=$?
eq "a free task is claimed" "$rc $(jq -r .agent <<<"$out")" "0 dev-1@laptop-a"
check "the Agent field holds the claim and its time" 'grep -qE "^dev-1@laptop-a [0-9T:-]+Z$" "$T/agent"'
check "the claim comment keeps the metrics prefix" 'jq -e ".[0].body | test(\"^Started by dev-1@laptop-a · claim [0-9a-f]{8}$\")" "$T/comments.json" >/dev/null'
SQUAD_HOST=laptop-b "$S/board.sh" claim 7 dev-1 >/dev/null 2>&1; eq "another machine is refused while the claim is fresh" "$?" 3
eq "...without posting a comment" "$(jq length "$T/comments.json")" 1
# a race: laptop-b posted its claim comment first, before laptop-a's Agent write landed
: > "$T/agent"; echo "[{\"id\":900,\"created_at\":\"$NOW\",\"body\":\"Started by dev-2@laptop-b · claim aaaaaaaa\"}]" > "$T/comments.json"
SQUAD_HOST=laptop-a "$S/board.sh" claim 7 dev-1 >/dev/null 2>&1; eq "the later claim loses the race" "$?" 3
eq "...and deletes its own comment" "$(jq -c '[.[].id]' "$T/comments.json")" '[900]'
check "...and does not touch the Agent field" '[[ ! -s "$T/agent" ]]'
echo "dev-1@laptop-b 2020-01-01T00:00:00Z" > "$T/agent"; echo '[]' > "$T/comments.json"
SQUAD_HOST=laptop-a "$S/board.sh" claim 7 qa >/dev/null; eq "a stale claim (crashed machine) can be taken over" "$?" 0
SQUAD_HOST=laptop-b "$S/board.sh" release 7 >/dev/null 2>&1; eq "a machine cannot release another machine's claim" "$?" 3
SQUAD_HOST=laptop-b "$S/board.sh" release 7 --force >/dev/null; check "--force clears it" '[[ ! -s "$T/agent" ]]'
cd / && rm -rf "$(dirname "$R")" "$T"
