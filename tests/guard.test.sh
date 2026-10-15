# shellcheck shell=bash disable=SC2016,SC2034
# guard.sh: the PreToolUse hook
R="$(new_repo)"; squad_config "$R"
git -C "$R" worktree add -q -b feat/12-x "$R/.worktrees/12" main
hook() { # hook <agent> <tool> <json tool_input> [cwd] ; prints the exit code
  jq -nc --arg a "$1" --arg t "$2" --argjson i "$3" --arg c "${4:-$R}" \
    '{tool_name:$t, tool_input:$i, cwd:$c} + (if $a == "" then {} else {agent_type:$a} end)' \
    | "$S/guard.sh" 2>/dev/null; echo $?
}
bash_in() { jq -nc --arg c "$1" '{command:$c}'; }
eq "push to main is blocked" "$(hook "" Bash "$(bash_in 'git push origin main')")" 2
eq "push HEAD:main is blocked" "$(hook "" Bash "$(bash_in 'git push origin HEAD:main')")" 2
eq "force push to main in a compound command is blocked" "$(hook "" Bash "$(bash_in 'git fetch && git push -f origin +main')")" 2
eq "bare push while on main is blocked" "$(hook "" Bash "$(bash_in 'git push')")" 2
eq "push -u origin HEAD while on main is blocked" "$(hook "" Bash "$(bash_in 'git push -u origin HEAD')")" 2
eq "push of a task branch is allowed" "$(hook squad:developer Bash "$(bash_in 'git push -u origin HEAD')" "$R/.worktrees/12")" 0
eq "branch name containing main is allowed" "$(hook "" Bash "$(bash_in 'git push origin feat/12-main-page')")" 0
eq "gh pr merge --admin is blocked" "$(hook squad:team-lead Bash "$(bash_in 'gh pr merge 5 --squash --admin')")" 2
eq "gh pr merge --squash is allowed" "$(hook squad:team-lead Bash "$(bash_in 'gh pr merge 5 --squash')")" 0
eq "gh pr review --approve is blocked" "$(hook squad:reviewer Bash "$(bash_in 'gh pr review 5 --approve')")" 2
eq "gh pr review --comment is allowed" "$(hook squad:reviewer Bash "$(bash_in 'gh pr review 5 --comment --body-file -')")" 0
fp() { jq -nc --arg p "$1" '{file_path:$p, content:"x"}'; }
eq "developer writes in its worktree" "$(hook squad:developer Write "$(fp "$R/.worktrees/12/src/a.ts")")" 0
eq "developer write in the main checkout is blocked" "$(hook squad:developer Edit "$(fp "$R/package.json")")" 2
eq "developer ../ escape is blocked" "$(hook squad:developer Write "$(fp "$R/.worktrees/12/../../package.json")")" 2
eq "BA writes under docs/requirements" "$(hook squad:ba-analyst Write "$(fp "$R/docs/requirements/x/requirements.md")")" 0
eq "BA write elsewhere is blocked" "$(hook squad:ba-analyst Write "$(fp "$R/src/a.ts")")" 2
eq "reporter writes under .squad/reports" "$(hook squad:reporter Write "$(fp "$R/.squad/reports/2026-10-14.md")")" 0
eq "reviewer can never edit" "$(hook squad:reviewer Edit "$(fp "$R/.worktrees/12/a.ts")")" 2
eq "main session (PM) is not restricted" "$(hook "" Write "$(fp "$R/src/a.ts")")" 0
eq "relative path is resolved from cwd" "$(hook squad:developer Write "$(fp "src/a.ts")" "$R/.worktrees/12")" 0
L="$(mktemp -d)"; ln -s "$(dirname "$R")" "$L/link"   # like macOS /var -> /private/var
eq "a repo reached through a symlink is the same repo" "$(hook squad:developer Write "$(fp "$L/link/work/.worktrees/12/a.ts")" "$L/link/work")" 0
eq "a symlinked path outside the worktree is still blocked" "$(hook squad:developer Write "$(fp "$L/link/work/package.json")" "$L/link/work")" 2
rm -rf "$L"
eq "agents may not call the railway CLI directly" "$(hook squad:qa-tester Bash "$(bash_in 'railway logs --lines 50')")" 2
eq "QA may read logs through railway.sh" "$(hook squad:qa-tester Bash "$(bash_in '/p/scripts/railway.sh logs staging --lines 50')")" 0
eq "QA may scan errors through railway.sh" "$(hook squad:qa-tester Bash "$(bash_in '/p/scripts/railway.sh errors staging --since 1h')")" 0
eq "QA may not change Railway" "$(hook squad:qa-tester Bash "$(bash_in '"/p/scripts/railway.sh" set-var staging A=1')")" 2
eq "DevOps may change Railway through railway.sh" "$(hook squad:devops Bash "$(bash_in '/p/scripts/railway.sh add-db staging postgres')")" 0
eq "DevOps may not use the railway CLI directly either" "$(hook squad:devops Bash "$(bash_in 'npx @railway/cli@5 up')")" 2
eq "the main session may use the railway CLI" "$(hook "" Bash "$(bash_in 'railway login')")" 0
# cd changes the directory of the commands after it (issue #2)
eq "cd into a task worktree, then push HEAD, is allowed" "$(hook squad:developer Bash "$(bash_in "cd $R/.worktrees/12 && git commit -m 'x' && git push -u origin HEAD")")" 0
eq "a relative cd into the worktree counts too" "$(hook squad:developer Bash "$(bash_in 'cd .worktrees/12; git push -u origin HEAD')")" 0
eq "cd back to the main checkout, then push HEAD, is blocked" "$(hook squad:developer Bash "$(bash_in "cd $R/.worktrees/12 && cd ../.. && git push -u origin HEAD")" "$R")" 2
eq "cd into the main checkout from a worktree, then push, is blocked" "$(hook squad:developer Bash "$(bash_in "cd $R && git push")" "$R/.worktrees/12")" 2
eq "an explicit push to main after cd is still blocked" "$(hook squad:developer Bash "$(bash_in "cd $R/.worktrees/12 && git push origin main")")" 2
# heredoc bodies and quoted text are data, not commands
eq "git push inside a heredoc is not a command" "$(hook "" Bash "$(bash_in $'cat > notes.md <<\'EOF\'\ngit push -u origin HEAD\nEOF\ngh issue create --body-file notes.md')")" 0
eq "git push inside a quoted argument is not a command" "$(hook "" Bash "$(bash_in 'gh issue create --title t --body "steps: commit; git push -u origin HEAD"')")" 0
eq "a real push after a heredoc is still checked" "$(hook "" Bash "$(bash_in $'cat > a <<EOF\nx\nEOF\ngit push')")" 2
eq "an unclosed quote falls back to the plain split (blocked)" "$(hook "" Bash "$(bash_in 'echo "x; git push')")" 2
O="$(new_repo)"
eq "outside a squad repo nothing is blocked" "$(hook "" Bash "$(bash_in 'git push origin main')" "$O")" 0
eq "other tools pass" "$(hook squad:reviewer Read '{"file_path":"/etc/hosts"}')" 0
rm -rf "$(dirname "$R")" "$(dirname "$O")"
