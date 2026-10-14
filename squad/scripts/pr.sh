#!/usr/bin/env bash
# pr.sh: Team Lead final check and merge of reviewed PRs (one GitHub account, D-1).
#
# Usage:
#   pr.sh check <pr>          JSON facts for the final check: linked task, head SHA, latest
#                             reviewer verdict and whether it is for the head commit, CI state,
#                             mergeability, changed files vs the task's Files (expected).
#                             "ok" is true only when every hard condition holds.
#   pr.sh merge <pr>          Run check; if ok: squash-merge pinned to the checked head SHA,
#                             delete the remote branch, remove the task worktree, move the task
#                             to QA, then label other open PRs that now conflict needs-rebase.
#   pr.sh reject <pr> <review|rework> -
#                             Final check failed: remove review:passed and comment the reason
#                             (stdin) on the PR. review: the task stays In Review for a new
#                             review (stale or missing verdict). rework: label review:changes,
#                             Attempts + 1, task back to Todo (the developer reworks the PR).
#   pr.sh conflicts           Label every open PR that conflicts with main needs-rebase.
#
# Reviewer verdict: the newest review whose body has a line "Verdict: PASS" or
# "Verdict: CHANGES" (gh pr review --comment). It counts only for the commit it was posted on.
# Hard conditions: PR open, base main, label review:passed, verdict PASS on the head commit,
# CI green (or no checks and merge.require_ci is false), mergeable, a linked task (Closes #N),
# no needs-split/needs-rebase/needs-human label. "unexpected_files" is advisory: the Team Lead
# judges scope.
# Config: $SQUAD_CONFIG or .squad/config.yml in the main worktree.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOARD="$SQUAD_SCRIPTS/board.sh"

pr_json() { # mergeability is computed lazily by GitHub: poll while UNKNOWN
  local pr="$1" j i
  for i in 1 2 3 4 5 6; do
    j="$(gh pr view "$pr" --repo "$OWNER/$REPO" --json number,state,baseRefName,headRefName,headRefOid,mergeable,labels,reviews,closingIssuesReferences,files,title,url)" \
      || die "PR #$pr not found"
    [[ "$(jq -r .mergeable <<<"$j")" != UNKNOWN || "$(jq -r .state <<<"$j")" != OPEN ]] && break
    sleep 5
  done
  echo "$j"
}

ci_state() { # pass | fail | pending | none | error
  local out
  # exit 8 = checks pending; "no checks reported" = none; anything else (auth, network) = error
  local err rc=0; err="$(mktemp)"
  out="$(gh pr checks "$1" --repo "$OWNER/$REPO" --json bucket 2>"$err")" || rc=$?
  if [[ "$rc" != 0 && ( "$rc" != 8 || -z "$out" ) ]]; then
    if grep -qi "no checks reported" "$err"; then echo none; else echo error; fi
    rm -f "$err"; return
  fi
  rm -f "$err"
  jq -r 'if length == 0 then "none"
         elif any(.[]; .bucket == "fail" or .bucket == "cancel") then "fail"
         elif any(.[]; .bucket == "pending") then "pending" else "pass" end' <<<"$out"
}

cmd_check() {
  local pr="${1:?usage: pr.sh check <pr>}" j ci req issue body
  j="$(pr_json "$pr")"
  ci="$(ci_state "$pr")"
  req="$(cfg '.merge.require_ci')"; [[ "$req" == false ]] || req=true
  issue="$(jq -r '.closingIssuesReferences[0].number // empty' <<<"$j")"
  if [[ -z "$issue" ]]; then   # GitHub links "Closes #N" with a delay: use the body or branch name
    issue="$(gh pr view "$pr" --repo "$OWNER/$REPO" --json body -q .body | grep -oiE '(closes|fixes|resolves) #[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)"
    [[ -n "$issue" ]] || issue="$(jq -r '.headRefName' <<<"$j" | sed -nE 's#^(feat|fix)/([0-9]+)-.*#\2#p')"
    [[ -z "$issue" ]] || j="$(jq --argjson n "$issue" '.closingIssuesReferences = [{number: $n}]' <<<"$j")"
  fi
  body=""; [[ -z "$issue" ]] || body="$(gh issue view "$issue" --repo "$OWNER/$REPO" --json body -q .body)"
  local expected excl; excl="$(cfg '.limits.pr_size_exclude')"; excl="${excl:-[]}"
  expected="$(awk '/^##+[ \t]*Files \(expected\)/{f=1;next} f&&/^#+[ \t]/{f=0} f&&/^[ \t]*[-*]/{print}' <<<"$body" \
    | sed -E 's/^[[:blank:]]*[-*][[:blank:]]*//; s/^[^`]*`([^`]+)`.*/\1/; s/[[:blank:]].*//; s#^\./##' | jq -R -s 'split("\n") | map(select(length > 0))')"
  jq --arg ci "$ci" --argjson req "$req" --argjson expected "$expected" --argjson excl "$excl" '
    def glob2re: gsub("\\."; "\\.") | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002") | gsub("\\*"; "[^/]*")
                 | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*") | "^" + . + "$";
    (.labels | map(.name)) as $labels
    | ([.reviews[] | select(.body | test("(?m)^\\s*\\**Verdict:?\\**:?\\s*\\**(PASS|CHANGES)"))] | last) as $rv
    | ($rv.body // "" | capture("(?m)^\\s*\\**Verdict:?\\**:?\\s*\\**(?<v>PASS|CHANGES)").v // null) as $verdict
    | ([.files[].path] | map(select(. as $f | [$excl[] | glob2re] | any(. as $re | $f | test($re)) | not))) as $code
    | ([$code[] | select(. as $f | $expected | any(. as $x | $f == $x or ($x | endswith("/")) and ($f | startswith($x))
                                                     or (($x | contains("*")) and ($f | test($x | glob2re)))) | not)]) as $unexpected
    | {pr: .number, url, title, issue: (.closingIssuesReferences[0].number // null), branch: .headRefName,
       head_sha: .headRefOid, state, base: .baseRefName, labels: $labels,
       verdict: $verdict, verdict_commit: ($rv.commit.oid // null),
       verdict_on_head: ($rv != null and $rv.commit.oid == .headRefOid),
       ci: $ci, require_ci: $req, mergeable,
       changed_files: [.files[].path], expected_files: $expected, unexpected_files: $unexpected}
    | .failed = ([
        (if .state != "OPEN" then "PR is not open" else empty end),
        (if .base != "main" then "base is not main" else empty end),
        (if ($labels | index("review:passed")) then empty else "label review:passed missing" end),
        (if .verdict != "PASS" then "latest reviewer verdict is not PASS" else empty end),
        (if .verdict == "PASS" and (.verdict_on_head | not) then "PASS verdict is for an older commit, not the head" else empty end),
        (if .ci == "fail" then "CI failed" elif .ci == "pending" then "CI still running"
         elif .ci == "error" then "CI state could not be read (gh error)"
         elif .ci == "none" and $req then "no CI checks reported (merge.require_ci is true)" else empty end),
        (if .mergeable == "CONFLICTING" then "conflicts with main" elif .mergeable != "MERGEABLE" then "mergeability unknown" else empty end),
        (if .issue == null then "no linked task (Closes #N)" else empty end),
        ($labels[] | select(. == "needs-split" or . == "needs-rebase" or . == "needs-human") | "label \(.) present")])
    | .ok = (.failed | length == 0)' <<<"$j"
}

label_conflicts() { # label_conflicts [except-pr] : prints JSON list of PRs labeled needs-rebase
  local except="${1:-0}" n m out='[]' open
  # skip PRs already labeled: no duplicate comments
  open="$(gh pr list --repo "$OWNER/$REPO" --state open --base main --limit 200 --json number,labels \
          -q '.[] | select([.labels[].name] | index("needs-rebase") | not) | .number')"
  for n in $open; do
    [[ "$n" == "$except" ]] && continue
    m="$(pr_json "$n" | jq -r .mergeable)"
    if [[ "$m" == CONFLICTING ]]; then
      gh pr edit "$n" --repo "$OWNER/$REPO" --add-label needs-rebase >/dev/null
      gh pr comment "$n" --repo "$OWNER/$REPO" \
        --body "Conflicts with \`main\` after a merge. Labeled \`needs-rebase\`: a developer will rebase it (squad)." >/dev/null
      out="$(jq -c --argjson n "$n" '. + [$n]' <<<"$out")"
    fi
  done
  echo "$out"
}

cmd_merge() {
  local pr="${1:?usage: pr.sh merge <pr>}" c sha issue branch
  c="$(cmd_check "$pr")"
  if [[ "$(jq -r .ok <<<"$c")" != true ]]; then
    if jq -e '.mergeable == "CONFLICTING"' >/dev/null <<<"$c"; then
      gh pr edit "$pr" --repo "$OWNER/$REPO" --add-label needs-rebase >/dev/null
    fi
    jq '{merged:false, pr, issue, failed}' <<<"$c"; return 3
  fi
  sha="$(jq -r .head_sha <<<"$c")"; issue="$(jq -r .issue <<<"$c")"; branch="$(jq -r .branch <<<"$c")"
  gh pr merge "$pr" --repo "$OWNER/$REPO" --squash --match-head-commit "$sha" >/dev/null \
    || die "merge of PR #$pr failed (head moved or protection rule)"
  gh api -X DELETE "repos/$OWNER/$REPO/git/refs/heads/$branch" >/dev/null 2>&1 || true
  if [[ -d "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/$issue" ]]; then
    "$SQUAD_SCRIPTS/worktree.sh" clean "$issue" --delete-branch --pr-merged >/dev/null || warn "worktree for #$issue kept (uncommitted changes?)"
  fi
  # the merge is done: bookkeeping failures are warnings, never a silent stop
  "$BOARD" move "$issue" QA >/dev/null || warn "merged, but #$issue could not be moved to QA: move it by hand"
  local rb; rb="$(label_conflicts "$pr" 2>/dev/null)" || { warn "merged; conflict check of other PRs failed"; rb='[]'; }
  jq -n --argjson pr "$pr" --argjson i "$issue" --arg s "$sha" --argjson rb "$rb" \
    '{merged:true, pr:$pr, issue:$i, merged_head:$s, rebase_needed:$rb}'
}

cmd_reject() {
  local pr="${1:?usage: pr.sh reject <pr> <review|rework> -}" next="${2:-}" reason issue
  [[ ( "$next" == review || "$next" == rework ) && "${3:-}" == "-" ]] \
    || die "usage: pr.sh reject <pr> <review|rework> - (reason on stdin)"
  reason="$(cat)"; [[ -n "$reason" ]] || die "empty reason"
  issue="$(gh pr view "$pr" --repo "$OWNER/$REPO" --json closingIssuesReferences,headRefName \
           -q '.closingIssuesReferences[0].number // (.headRefName | capture("^(feat|fix)/(?<n>[0-9]+)-").n) // empty')"
  gh pr edit "$pr" --repo "$OWNER/$REPO" --remove-label review:passed >/dev/null
  gh pr comment "$pr" --repo "$OWNER/$REPO" \
    --body "$(printf 'Team Lead final check: **not merged** (next: %s).\n\n%s' "$next" "$reason")" >/dev/null
  if [[ -n "$issue" ]]; then
    if [[ "$next" == rework ]]; then
      # same path as a reviewer's CHANGES: the developer reworks and reads this comment
      gh pr edit "$pr" --repo "$OWNER/$REPO" --add-label review:changes >/dev/null
      "$BOARD" bump-attempts "$issue" >/dev/null
      "$BOARD" move "$issue" Todo >/dev/null
    else "$BOARD" move "$issue" "In Review" >/dev/null; fi
  fi
  jq -nc --argjson pr "$pr" --arg i "$issue" --arg nx "$next" \
    '{rejected:true, pr:$pr, issue:(if $i == "" then null else ($i|tonumber) end), next:$nx}'
}

need gh jq git
cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  -h|--help|help|"") usage_from "$0"; [[ -n "$cmd" ]] ;;
  check|merge|reject) load_project; "cmd_$cmd" "$@" ;;
  conflicts) load_project; label_conflicts 0 ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
