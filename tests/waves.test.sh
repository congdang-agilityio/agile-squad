# shellcheck shell=bash disable=SC2016,SC2034
# waves.sh plan --from-json (offline)
W="$("$S/waves.sh" plan --from-json "$FIX/waves-tasks.json")"
eq "scaffold (config layer) is alone in the first wave" "$(jq -c '.waves[0]' <<<"$W")" "[1]"
check "migration (Serial: yes) is alone in its wave" 'jq -e ".waves[] | select(index(2)) | length == 1" <<<"$W" >/dev/null'
check "independent tasks with distinct files share a wave" 'jq -e ".wave_of[\"3\"] == .wave_of[\"4\"]" <<<"$W" >/dev/null'
check "a directory entry never shares a wave with files under it" 'jq -e ".wave_of[\"9\"] != .wave_of[\"3\"] and .wave_of[\"9\"] != .wave_of[\"4\"]" <<<"$W" >/dev/null'
check "shared routing file is serialized" 'jq -e ".serial | index(8)" <<<"$W" >/dev/null'
check "no wave exceeds max parallel (2)" 'jq -e "[.waves[] | length] | max <= 2" <<<"$W" >/dev/null'
W3="$("$S/waves.sh" plan --from-json "$FIX/waves-tasks.json" --max-parallel 3 --start 5)"
check "--start and --max-parallel are honored" 'jq -e ".first_wave == 5 and ([.waves[] | length] | max) == 3" <<<"$W3" >/dev/null'
T="$(mktemp -d)"
jq '.[0].body |= sub("none"; "#9")' "$FIX/waves-tasks.json" > "$T/cycle.json"
check "a dependency cycle is an error" '! "$S/waves.sh" plan --from-json "$T/cycle.json" >/dev/null 2>&1'
rm -rf "$T"
