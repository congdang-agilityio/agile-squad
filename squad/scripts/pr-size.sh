#!/usr/bin/env bash
# pr-size.sh: measure a PR or branch against the task size limits (board-conventions §6).
#
# Usage:
#   pr-size.sh <pr-number|branch> [--size XS|S|M]
#
# Counts changed lines (additions + deletions) and changed files against main, excluding
# limits.pr_size_exclude (tests, lockfiles, generated files). For a PR the numbers come from
# GitHub; for a branch from `git diff origin/main...<branch>`. Without --size, the Size field of
# the linked task (PR "Closes #N", or the issue number in feat|fix/<N>-* branch names) is used.
# Limits come from limits.pr_max_lines / limits.pr_max_files.
# Output JSON: {size, lines, files, max_lines, max_files, over, counted, excluded}.
# Exit: 0 within limits, 3 over the limit, 1 on errors.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need gh jq git
target="${1:-}"
case "$target" in -h|--help|help|"") usage_from "$0"; [[ -n "$target" ]]; exit ;; esac
shift
size=""
while [[ $# -gt 0 ]]; do
  case "$1" in --size) size="${2:?--size needs XS|S|M}"; shift 2 ;; *) die "unknown option $1" ;; esac
done
load_project

issue=""
if [[ "$target" =~ ^[0-9]+$ ]]; then
  files="$(gh api --paginate "repos/$OWNER/$REPO/pulls/$target/files?per_page=100" \
           --jq '.[] | {path: .filename, lines: (.additions + .deletions)}' | jq -s .)" \
    || die "PR #$target not found"
  issue="$(gh pr view "$target" --repo "$OWNER/$REPO" --json closingIssuesReferences \
           -q '.closingIssuesReferences[0].number // empty')"
else
  git fetch --quiet origin main 2>/dev/null || true
  git rev-parse --verify --quiet "$target" >/dev/null || die "branch '$target' not found"
  files="$(git diff --numstat "origin/main...$target" \
           | awk -F'\t' '{a=($1=="-")?0:$1; d=($2=="-")?0:$2; printf "{\"path\":\"%s\",\"lines\":%d}\n", $3, a+d}' | jq -s .)"
  [[ "$target" =~ ^(feat|fix)/([0-9]+)- ]] && issue="${BASH_REMATCH[2]}"
fi

if [[ -z "$size" ]]; then
  [[ -n "$issue" ]] || die "cannot find the linked task; pass --size XS|S|M"
  size="$("$SQUAD_SCRIPTS/board.sh" get "$issue" | jq -r '.size // empty')"
  [[ -n "$size" ]] || die "task #$issue has no Size on the board; pass --size XS|S|M"
fi
in_list "$size" "${SIZES[@]}" || die "size must be one of ${SIZES[*]}"

max_lines="$(cfg ".limits.pr_max_lines.$size")"; max_files="$(cfg ".limits.pr_max_files.$size")"
[[ -n "$max_lines" ]] || max_lines="$(case "$size" in XS) echo 50 ;; S) echo 150 ;; M) echo 300 ;; esac)"
[[ -n "$max_files" ]] || max_files="$(case "$size" in XS) echo 3 ;; S) echo 6 ;; M) echo 10 ;; esac)"
excl="$(cfg '.limits.pr_size_exclude')"; excl="${excl:-[]}"

res="$(jq --arg size "$size" --argjson ml "$max_lines" --argjson mf "$max_files" --argjson excl "$excl" '
  def glob2re: gsub("\\."; "\\.") | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002") | gsub("\\*"; "[^/]*")
               | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*") | "^" + . + "$";
  ([$excl[] | glob2re]) as $res
  | map(. + {excluded: (.path as $p | $res | any(. as $r | $p | test($r)))}) as $all
  | ($all | map(select(.excluded | not))) as $counted
  | {size: $size, lines: ($counted | map(.lines) | add // 0), files: ($counted | length),
     max_lines: $ml, max_files: $mf,
     counted: [$counted[] | {path, lines}], excluded: [$all[] | select(.excluded) | .path]}
  | .over = (.lines > $ml or .files > $mf)' <<<"$files")"
echo "$res"
[[ "$(jq -r .over <<<"$res")" == false ]] || exit 3
