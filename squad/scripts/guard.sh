#!/usr/bin/env bash
# guard.sh: PreToolUse hook (hooks/hooks.json). Enforces squad's hard rules in code, so they
# do not depend on a subagent following its prompt.
#
# Usage (Claude Code runs it; the tool call JSON arrives on stdin):
#   guard.sh < hook-input.json
#
# Active only in repositories with .squad/config.yml (elsewhere it allows everything).
# Rules:
#   everyone           no `git push` to main/master (explicit, or a bare push from main);
#                      no `gh pr merge --admin`; no `gh pr review --approve`
#   squad:* agents     Railway only through scripts/railway.sh, never the railway CLI itself;
#                      only squad:devops may run railway.sh changes (others: read commands)
#   squad:developer    Write/Edit only inside <repo>/.worktrees/<issue>/
#   squad:ba-analyst   Write/Edit only inside <repo>/docs/requirements/
#   squad:reporter     Write/Edit only inside <repo>/.squad/reports/
#   squad:reviewer, squad:qa-tester, squad:team-lead, squad:devops
#                      no Write/Edit at all
# The main session (PM) is not restricted beyond the "everyone" rules.
# Exit: 0 allow, 2 block (the reason on stderr is shown to Claude).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
in="$(cat)"
field() { jq -r "$1 // empty" <<<"$in" 2>/dev/null; }
tool="$(field .tool_name)"; agent="$(field .agent_type)"; cwd="$(field .cwd)"
[[ -n "$cwd" && -d "$cwd" ]] || cwd="$PWD"

common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
root="$(dirname "$common")"
[[ -f "$root/.squad/config.yml" ]] || exit 0

block() { echo "squad guard: $*" >&2; exit 2; }

if [[ "$tool" == Bash ]]; then
  cmd="$(field .tool_input.command)"
  # one simple command per line of the compound command
  while IFS= read -r part; do
    part="${part#"${part%%[![:space:]]*}"}"
    if [[ "$part" =~ ^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$) ]]; then
      if [[ "$part" =~ ([[:space:]:/+]|^)(main|master)([[:space:]]|$) ]]; then
        block "pushing to main is not allowed; push the task branch and open a PR"
      fi
      dir="$cwd"; [[ "$part" =~ -C[[:space:]]+([^[:space:]]+) ]] && dir="${BASH_REMATCH[1]}"
      [[ "$dir" = /* ]] || dir="$cwd/$dir"
      branch="$(git -C "$dir" branch --show-current 2>/dev/null)"
      if [[ "$branch" == main || "$branch" == master ]]; then
        # arguments after "push" without options: <remote> [<refspec>...]
        read -ra args <<<"$(sed -E 's/^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push//; s/(^|[[:space:]])-[^[:space:]]+//g' <<<"$part")"
        if ((${#args[@]} <= 1)) || [[ " ${args[*]:1} " =~ [[:space:]]\+?HEAD(:|[[:space:]]) ]]; then
          block "a push of the current branch ($branch) would update main; push the task branch and open a PR"
        fi
      fi
    fi
    if [[ "$agent" == squad:* ]]; then
      # Railway only through scripts/railway.sh (no secrets printed, production needs approval)
      if [[ "$part" =~ ^(npx[[:space:]]+[^[:space:]]*@railway/cli[^[:space:]]*|railway)([[:space:]]|$) ]]; then
        block "use scripts/railway.sh for Railway, not the railway CLI directly"
      fi
      if [[ "$part" =~ railway\.sh[\"\']?[[:space:]]+([a-z-]+) && "$agent" != squad:devops ]]; then
        case "${BASH_REMATCH[1]}" in check|status|logs|errors|deployments|vars|help|-h|--help) ;;
          *) block "only DevOps changes Railway; ${agent#squad:} may use railway.sh check/status/logs/errors/deployments/vars" ;;
        esac
      fi
    fi
    if [[ "$part" =~ ^gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) && "$part" =~ [[:space:]]--admin([[:space:]]|$) ]]; then
      block "merging with --admin bypasses branch protection; fix the failing condition instead"
    fi
    if [[ "$part" =~ ^gh[[:space:]]+pr[[:space:]]+review([[:space:]]|$) && "$part" =~ [[:space:]](--approve|-a)([[:space:]]|$) ]]; then
      block "squad never approves PRs (one shared account); post the verdict with gh pr review --comment"
    fi
  done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$cmd")
  exit 0
fi

case "$tool" in Write|Edit|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
path="$(field .tool_input.file_path)"; [[ -n "$path" ]] || path="$(field .tool_input.notebook_path)"
[[ -n "$path" ]] || exit 0
[[ "$path" = /* ]] || path="$cwd/$path"
# resolve .. segments and symlinks (macOS /var -> /private/var) without requiring the file
# to exist, the same way git reports the repository root
path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null || echo "$path")"
root="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root" 2>/dev/null || echo "$root")"

inside() { [[ "$path" == "$root/$1"* ]]; }
case "$agent" in
  squad:developer)
    [[ "$path" =~ ^"$root"/\.worktrees/[0-9]+/ ]] \
      || block "developers write only inside their worktree $root/.worktrees/<issue>/ (got $path)" ;;
  squad:ba-analyst)
    inside docs/requirements/ || block "the BA writes only under docs/requirements/ (got $path)" ;;
  squad:reporter)
    inside .squad/reports/ || block "the reporter writes only under .squad/reports/ (got $path)" ;;
  squad:reviewer|squad:qa-tester|squad:team-lead|squad:devops)
    block "${agent#squad:} never edits files; report findings on the PR or issue instead" ;;
esac
exit 0
