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
        '. + [{id:$id, created_at:$t, updated_at:$t, body:$b}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json"; echo ok ;;
    "api repos/acme/app/issues/7/comments?since="*) # like GitHub: since filters by updated_at
      local since="${all#*since=}"; since="${since%%&*}"
      jq --arg s "$since" 'map(select((.updated_at // .created_at) >= $s))' "$S/comments.json" ;;
    "api -X PATCH repos/acme/app/issues/comments/"*)
      local rest="${all#*comments/}" id body; id="${rest%% *}"; body="${all#*-f body=}"
      jq --argjson id "$id" --arg b "$body" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        'map(if .id == $id then .body = $b | .updated_at = $t else . end)' "$S/comments.json" > "$S/c.tmp" \
        && mv "$S/c.tmp" "$S/comments.json"; echo '{}' ;;
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
# handoffs: a released claim must not win the next claim (dev -> review -> dev rework)
: > "$T/agent"; echo '[]' > "$T/comments.json"
SQUAD_HOST=tank "$S/board.sh" claim 7 dev-1 >/dev/null
out="$(SQUAD_HOST=tank "$S/board.sh" release 7)"
eq "release marks this machine's claim comment" "$(jq -r .claim_comments <<<"$out")" 1
check "...keeping the Started by prefix and the nonce" \
  'jq -e ".[0].body | test(\"^Started by dev-1@tank · claim [0-9a-f]{8} · released [0-9T:-]+Z$\")" "$T/comments.json" >/dev/null'
out="$(SQUAD_HOST=tank "$S/board.sh" claim 7 review)"; rc=$?
eq "the reviewer claims right after the developer released" "$rc $(jq -r .agent <<<"$out")" "0 review@tank"
SQUAD_HOST=tank "$S/board.sh" release 7 >/dev/null
SQUAD_HOST=tank "$S/board.sh" claim 7 dev-1 >/dev/null; eq "the same developer can claim again for rework" "$?" 0
SQUAD_HOST=tank "$S/board.sh" release 7 >/dev/null
SQUAD_HOST=laptop-b "$S/board.sh" claim 7 qa >/dev/null; eq "another machine claims right after a release" "$?" 0
# release touches only this machine's comments, unless --force
echo "[{\"id\":901,\"created_at\":\"$NOW\",\"updated_at\":\"$NOW\",\"body\":\"Started by dev-2@laptop-c · claim bbbbbbbb\"}]" > "$T/comments.json"; : > "$T/agent"
SQUAD_HOST=tank "$S/board.sh" release 7 >/dev/null
eq "a release leaves another machine's claim comment alone" "$(jq -r '.[0].body' "$T/comments.json")" "Started by dev-2@laptop-c · claim bbbbbbbb"
SQUAD_HOST=tank "$S/board.sh" release 7 --force >/dev/null
check "release --force marks it too" 'jq -e ".[0].body | test(\"^Started by dev-2@laptop-c · claim bbbbbbbb · released \")" "$T/comments.json" >/dev/null'
# an old claim comment edited just now (updated_at recent, created_at old) is not in the race
OLD="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
echo "[{\"id\":902,\"created_at\":\"$OLD\",\"updated_at\":\"$NOW\",\"body\":\"Started by dev-3@laptop-d · claim cccccccc\"}]" > "$T/comments.json"; : > "$T/agent"
SQUAD_HOST=tank "$S/board.sh" claim 7 dev-1 >/dev/null; eq "an old comment edited recently does not win the race" "$?" 0
cd / && rm -rf "$(dirname "$R")" "$T"
