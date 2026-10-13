#!/usr/bin/env bash
# worktree.sh: one git worktree per task, with a per-slot port and test database.
#
# Usage:
#   worktree.sh <issue> <slot>        Create or reuse .worktrees/<issue> on the task branch and
#                                     (re)write its .env.local for the slot. Prints JSON.
#   worktree.sh clean <issue> [--force] [--delete-branch [--pr-merged]]
#                                     Remove .worktrees/<issue>. Refuses when it has uncommitted
#                                     changes unless --force. --delete-branch also deletes the
#                                     local branch when it has no commits outside origin/main,
#                                     or when --pr-merged says its PR was (squash-)merged.
#   worktree.sh list                  JSON list of task worktrees.
#
# Branch: an existing local or remote branch feat|fix/<issue>-* is reused; otherwise a new
# branch feat/<issue>-<slug> (fix/ for type:bug issues) is created from the latest origin/main.
# Nothing is ever committed to main. .worktrees/ and .env.local are added to .git/info/exclude.
# Slot environment (.env.local): SQUAD_SLOT, SQUAD_ISSUE, PORT = parallel.port_base + slot,
# TEST_DB_NAME = <parallel.test_db_prefix>_<slot>.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

main_root() { dirname "$(git rev-parse --path-format=absolute --git-common-dir)"; }

exclude() { # add ignore patterns locally (no commit needed)
  local f p; f="$(git rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "$(dirname "$f")"; touch "$f"
  for p in "/.worktrees/" ".env.local"; do grep -qxF "$p" "$f" || echo "$p" >> "$f"; done
}

slugify() { # lowercase, ascii, dash-separated, max 40 chars
  iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null <<<"$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//'
}

find_branch() { # existing branch for the issue: local first, then origin
  local n="$1" b
  b="$(git for-each-ref --format='%(refname:short)' "refs/heads/feat/$n-*" "refs/heads/fix/$n-*" | head -n1)"
  [[ -n "$b" ]] && { echo "$b"; return; }
  b="$(git for-each-ref --format='%(refname:short)' "refs/remotes/origin/feat/$n-*" "refs/remotes/origin/fix/$n-*" \
       | head -n1)"
  [[ -z "$b" ]] || echo "${b#origin/}"
}

write_env() { # write_env <dir> <issue> <slot>
  local port_base prefix
  port_base="$(cfg '.parallel.port_base')"; port_base="${port_base:-4100}"
  prefix="$(cfg '.parallel.test_db_prefix')"; prefix="${prefix:-app_test}"
  cat > "$1/.env.local" <<EOF
# Written by squad worktree.sh for slot $3. Do not commit.
SQUAD_ISSUE=$2
SQUAD_SLOT=$3
PORT=$((port_base + $3))
TEST_DB_NAME=${prefix}_$3
EOF
}

cmd_create() {
  local n="$1" slot="$2"
  [[ "$n" =~ ^[0-9]+$ ]] || die "issue must be a number"
  [[ "$slot" =~ ^[0-9]+$ && "$slot" -ge 1 ]] || die "slot must be a positive integer"
  local max; max="$(cfg '.parallel.max_parallel_dev')"
  [[ -z "$max" || "$slot" -le "$max" ]] || die "slot $slot exceeds parallel.max_parallel_dev ($max)"
  local root dir; root="$(main_root)"; dir="$root/.worktrees/$n"
  exclude
  git -C "$root" fetch --quiet origin || die "git fetch failed"

  local branch created=false
  if git -C "$root" worktree list --porcelain | grep -qxF "worktree $dir"; then
    branch="$(git -C "$dir" branch --show-current)"
  else
    [[ ! -e "$dir" ]] || die "$dir exists but is not a registered worktree; remove it first"
    branch="$(cd "$root" && find_branch "$n")"
    if [[ -n "$branch" ]]; then
      if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$root" worktree add --quiet "$dir" "$branch"
      else
        git -C "$root" worktree add --quiet --track -b "$branch" "$dir" "origin/$branch"
      fi
    else
      local meta kind title
      meta="$(gh issue view "$n" --repo "$OWNER/$REPO" --json title,labels)" || die "issue #$n not found"
      title="$(jq -r .title <<<"$meta")"
      kind=feat; jq -e '.labels | map(.name) | index("type:bug")' >/dev/null <<<"$meta" && kind=fix
      branch="$kind/$n-$(slugify "$title")"; branch="${branch%-}"
      git -C "$root" worktree add --quiet --no-track -b "$branch" "$dir" origin/main
      created=true
    fi
  fi
  case "$branch" in main|master|"") die "refusing to use branch '$branch' for a task worktree" ;; esac
  write_env "$dir" "$n" "$slot"
  local port_base prefix
  port_base="$(cfg '.parallel.port_base')"; prefix="$(cfg '.parallel.test_db_prefix')"
  jq -nc --argjson n "$n" --argjson s "$slot" --arg d "$dir" --arg b "$branch" --argjson c "$created" \
    --argjson port "$(( ${port_base:-4100} + slot ))" --arg db "${prefix:-app_test}_$slot" \
    '{issue:$n, slot:$s, path:$d, branch:$b, new_branch:$c, port:$port, test_db:$db}'
}

cmd_clean() {
  local n="${1:?usage: worktree.sh clean <issue> [--force] [--delete-branch [--pr-merged]]}" force=0 delb=0 prmerged=0; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in --force) force=1 ;; --delete-branch) delb=1 ;; --pr-merged) prmerged=1 ;;
      *) die "unknown option $1" ;; esac; shift
  done
  local root dir branch=""; root="$(main_root)"; dir="$root/.worktrees/$n"
  if git -C "$root" worktree list --porcelain | grep -qxF "worktree $dir"; then
    branch="$(git -C "$dir" branch --show-current)"
    if [[ "$force" == 0 && -n "$(git -C "$dir" status --porcelain --untracked-files=normal | grep -v ' .env.local$' || true)" ]]; then
      die "$dir has uncommitted changes; commit/push them or use --force"
    fi
    git -C "$root" worktree remove --force "$dir"
  else
    info "no worktree for #$n"
  fi
  git -C "$root" worktree prune
  local deleted=false
  if [[ "$delb" == 1 && -n "$branch" ]]; then
    git -C "$root" fetch --quiet --prune origin || true
    if [[ "$prmerged" == 1 ]] \
       || git -C "$root" branch --merged origin/main --format='%(refname:short)' | grep -qxF "$branch" \
       || [[ -z "$(git -C "$root" rev-list "origin/main..$branch" 2>/dev/null)" ]]; then
      git -C "$root" branch -D "$branch" >/dev/null && deleted=true
    else
      warn "branch $branch has commits that are not in main; kept"
    fi
  fi
  jq -nc --argjson n "$n" --arg b "$branch" --argjson d "$deleted" '{issue:$n, removed:true, branch:$b, branch_deleted:$d}'
}

cmd_list() {
  local root; root="$(main_root)"
  git -C "$root" worktree list --porcelain | awk -v pre="$root/.worktrees/" '
    /^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8); sub("refs/heads/","",b)
      if (index(p,pre)==1) printf "%s\t%s\n", substr(p,length(pre)+1), b}' \
  | jq -R -s --arg root "$root" 'split("\n") | map(select(length>0) | split("\t")
      | {issue:(.[0]|tonumber), branch:.[1], path:($root + "/.worktrees/" + .[0])})'
}

need git jq gh
cmd="${1:-}"
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  clean) shift; load_config; cmd_clean "$@" ;;
  list) load_config; cmd_list ;;
  *) [[ $# -eq 2 ]] || die "usage: worktree.sh <issue> <slot> (see --help)"
     load_config; OWNER="$(cfg_req .owner)"; REPO="$(cfg_req .repo)"; cmd_create "$1" "$2" ;;
esac
