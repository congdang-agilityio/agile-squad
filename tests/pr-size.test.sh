# shellcheck shell=bash disable=SC2016,SC2034
# pr-size.sh <branch> (local git, no GitHub)
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
git add .squad; git commit -q -m config; git push -q origin main 2>/dev/null
git switch -q -c feat/5-thing
mkdir -p src; seq 1 40 > src/a.ts; seq 1 30 > src/a.test.ts; seq 1 500 > package-lock.json
printf 'x\n' > "src/é ü.ts"
git add -A; git commit -q -m "feat: thing (#5)"; git push -q -u origin feat/5-thing 2>/dev/null
out="$("$S/pr-size.sh" feat/5-thing --size XS)"; rc=$?
eq "XS within limits (tests and lockfile excluded)" "$rc $(jq -c '[.lines, .files]' <<<"$out")" "0 [41,2]"
check "non-ASCII path is counted by its real name" 'jq -e ".counted | map(.path) | index(\"src/é ü.ts\")" <<<"$out" >/dev/null'
seq 1 60 >> src/a.ts; git commit -q -am more
"$S/pr-size.sh" feat/5-thing --size XS >/dev/null; eq "over the XS limit exits 3" "$?" 3
cd / && rm -rf "$(dirname "$R")"
