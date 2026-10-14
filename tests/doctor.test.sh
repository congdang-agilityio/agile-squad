# shellcheck shell=bash disable=SC2016,SC2034
# doctor.sh --offline
R="$(new_repo)"; cd "$R" || exit 1
out="$("$S/doctor.sh" --offline)"; rc=$?
eq "no config: fails with a setup hint" "$rc $(jq -r '.checks[] | select(.check == "config") | .fix' <<<"$out")" "1 run /squad:setup"
squad_config "$R"
out="$("$S/doctor.sh" --offline)"
check "missing ids are a failure with the bootstrap fix" 'jq -e ".checks[] | select(.check == \"ids\" and .status == \"fail\") | .fix | test(\"bootstrap\")" <<<"$out" >/dev/null'
check "missing .gitignore lines are a warning" 'jq -e ".checks[] | select(.check == \"gitignore\" and .status == \"warn\")" <<<"$out" >/dev/null'
sed -i.bak 's/^  platform: railway.*/  platform: none/' .squad/config.yml
out="$("$S/doctor.sh" --offline)"
check "deploy.platform none: no deploy workflow needed" 'jq -e ".checks[] | select(.check == \"deploy_workflow\" and .status == \"ok\")" <<<"$out" >/dev/null'
cd / && rm -rf "$(dirname "$R")"
