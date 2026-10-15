# shellcheck shell=bash disable=SC2016,SC2034
# board.sh missing / relink: items GitHub's item listing leaves out (issue #3), stateful fake gh
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
python3 - .squad/config.yml <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('  project_id: "PVT_1"', '''  project_id: "PVT_1"
  status_field_id: F_STATUS
  priority_field_id: F_PRIO
  size_field_id: F_SIZE
  wave_field_id: F_WAVE
  agent_field_id: F_AGENT
  attempts_field_id: F_ATT
  status_options: {"Todo": O_TODO, "In Progress": O_PROG}
  priority_options: {"P1": O_P1}
  size_options: {"S": O_S}''')
open(p, "w").write(s)
PY
T="$(mktemp -d)"; export GH_STUB="$T/stub.sh" GH_LOG="$T/gh.log" STATE="$T" RELINK_WAIT=0
# issues 1..5 are on the board; the listing leaves out #3 (back after one relink) and #5 (two)
echo '[1,2,4]' > "$T/listed"; echo '{"3":1,"5":2}' > "$T/needs"; : > "$T/edits"
cat > "$GH_STUB" <<'STUB'
respond() {
  local S="$STATE" all="$*" n
  case "$all" in
    *"graphql"*"issues(first:100"*)
      jq -n '{data:{repository:{issues:{pageInfo:{hasNextPage:false,endCursor:null},nodes:
        ([range(1;6) | {number:., projectItems:{nodes:[{isArchived:false,project:{id:"PVT_1"}}]}}]
         + [{number:6, projectItems:{nodes:[{isArchived:true,project:{id:"PVT_1"}}]}},
            {number:7, projectItems:{nodes:[{isArchived:false,project:{id:"PVT_9"}}]}}])}}}}' ;;
    *"graphql"*"items(first:100"*)
      jq '{data:{node:{items:{pageInfo:{hasNextPage:false,endCursor:null},nodes:[.[] | {id:("PVTI_\(.)"),isArchived:false,
        content:{__typename:"Issue",number:.,title:"t",state:"OPEN",url:"u",body:"",repository:{nameWithOwner:"acme/app"},
          labels:{nodes:[]},milestone:null},fieldValues:{nodes:[]}}]}}}}' "$S/listed" ;;
    *"graphql"*"projectItems(first:50){nodes{id isArchived"*)
      n="${all##*n=}"; n="${n%% *}"
      jq -n --argjson n "$n" '{data:{repository:{issue:{__typename:"Issue",number:$n,title:"t",state:"OPEN",body:"",url:"u",
        repository:{nameWithOwner:"acme/app"},labels:{nodes:[]},milestone:null,
        projectItems:{nodes:[{id:"PVTI_\($n)",isArchived:false,project:{id:"PVT_1"},fieldValues:{nodes:[
          {__typename:"ProjectV2ItemFieldSingleSelectValue",name:"In Progress",field:{name:"Status"}},
          {__typename:"ProjectV2ItemFieldSingleSelectValue",name:"P1",field:{name:"Priority"}},
          {__typename:"ProjectV2ItemFieldSingleSelectValue",name:"S",field:{name:"Size"}},
          {__typename:"ProjectV2ItemFieldNumberValue",number:2,field:{name:"Wave"}},
          {__typename:"ProjectV2ItemFieldTextValue",text:"dev-1@tank 2026-10-16T00:00:00Z",field:{name:"Agent"}},
          {__typename:"ProjectV2ItemFieldNumberValue",number:1,field:{name:"Attempts"}}]}}]}}}}}' ;;
    *"graphql"*"deleteProjectV2Item"*)
      echo "delete ${all##*i=}" >> "$S/edits"; echo '{"data":{"deleteProjectV2Item":{"deletedItemId":"x"}}}' ;;
    *"graphql"*"projectItems(first:50){nodes{id project{id}}}"*)
      n="${all##*n=}"; n="${n%% *}"
      jq -n --argjson n "$n" '{data:{repository:{issue:{id:"I_\($n)",projectItems:{nodes:[{id:"PVTI_\($n)",project:{id:"PVT_1"}}]}}}}}' ;;
    "project item-edit"*)
      echo "edit ${all#*--field-id }" >> "$S/edits"
      # the re-added item shows up in the listing once its needed rounds are done
      n="${all#*--id PVTI_}"; n="${n%% *}"
      if [[ "$all" == *F_STATUS* ]]; then
        jq --arg n "$n" '.[$n] = ((.[$n] // 0) - 1)' "$S/needs" > "$S/n.tmp" && mv "$S/n.tmp" "$S/needs"
        if [[ "$(jq -r --arg n "$n" '.[$n]' "$S/needs")" -le 0 ]]; then
          jq --argjson n "$n" '. + [$n] | unique' "$S/listed" > "$S/l.tmp" && mv "$S/l.tmp" "$S/listed"
        fi
      fi ;;
    *) echo "unexpected gh call: $*" >&2; return 1 ;;
  esac
}
STUB
out="$("$S/board.sh" missing)"
eq "missing lists the board issues left out of the listing" "$(jq -c .missing <<<"$out")" '[3,5]'
out="$("$S/board.sh" relink 3)"
eq "relink brings the item back" "$(jq -c '[.issue, .listed]' <<<"$out")" '[3,true]'
eq "...deleting it once" "$(grep -c '^delete' "$T/edits")" 1
check "...and restoring Status, Priority, Size, Wave, Agent and Attempts" \
  'grep -q "F_STATUS --single-select-option-id O_PROG" "$T/edits" && grep -q "F_PRIO --single-select-option-id O_P1" "$T/edits" &&
   grep -q "F_SIZE --single-select-option-id O_S" "$T/edits" && grep -q "F_WAVE --number 2" "$T/edits" &&
   grep -q "F_AGENT --text dev-1@tank 2026-10-16T00:00:00Z" "$T/edits" && grep -q "F_ATT --number 1" "$T/edits"'
: > "$T/edits"
out="$("$S/board.sh" relink '#5')"
eq "an item that needs a second round gets it" "$(jq -c '[.issue, .listed]' <<<"$out") $(grep -c '^delete' "$T/edits")" '[5,true] 2'
eq "after relinking nothing is missing" "$("$S/board.sh" missing | jq -c .missing)" '[]'
cd / && rm -rf "$(dirname "$R")" "$T"
