---
name: review
description: "Code review procedure for one PR in In Review: check size and scope, verify every acceptance criterion and DoD item has a test, review correctness and security against the review checklist, and post the verdict as a review comment (PASS adds review:passed for the Team Lead to merge; CHANGES sends the task back). Never approves or merges. Use when a PR is waiting for review."
---

# squad: review (one PR, verdict by comment)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

The PM dispatches a fresh `reviewer` subagent: `pr=<n> config=.squad/config.yml`.
When invoked directly (`/squad:review <pr>`), dispatch the `reviewer` subagent instead.
The Reviewer has no Write/Edit and never changes code, approves (`--approve`) or merges:
one GitHub account cannot approve its own PR (decision D-1). The Team Lead merges.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`pr-size.sh`, `board.sh`), literal arguments.
Checklist: `references/review-checklist.md`. Verdict format: `references/conventions/git.md`
"Review and merge".

## Steps
0. **Claim** the linked task: `board.sh claim <task> review`; exit 3 → another machine is
   reviewing it: return `claimed_elsewhere`. Always `board.sh release <task>` before you return.
1. **Load.** `gh pr view <pr> --json number,title,body,headRefOid,headRefName,labels,mergeable,closingIssuesReferences,reviews,comments`.
   The linked task (`Closes #<n>`), its parent story (`gh issue view`) and their ACs/DoD.
   Earlier review rounds: what was asked and whether it was fixed.
2. **Size.** `pr-size.sh <pr>`. Exit 3 (over the task size), or the PR clearly does two
   things → skip the detailed review:
   - `gh pr review <pr> --comment --body-file -` with `Verdict: CHANGES`, "PR too large,
     please split" and the numbers; `gh pr edit <pr> --add-label needs-split --remove-label review:passed`;
   - `gh issue edit <task> --add-label needs-split`; `board.sh move <task> Todo`;
   - return `needs_split`.
3. **Conflicts.** `mergeable` is `CONFLICTING` → `gh pr edit <pr> --add-label needs-rebase`,
   return `needs_rebase` (review after the rebase).
4. **Read the change.** `gh pr diff <pr>` and, for context, whole files at the head commit:
   `git fetch origin pull/<pr>/head` then `git show <sha>:<path>`. Read the tests as
   carefully as the code. CI state: `gh pr checks <pr>`.
5. **Review** every section of the checklist: scope, AC/DoD ↔ test mapping, correctness,
   security (input validation!), tests, conventions. Each finding: severity, `path:line`,
   problem, why it matters, concrete fix. Evidence only; no guesses about code you did not read.
6. **Verdict** (always `gh pr review <pr> --comment --body-file -`, never `--approve`). The
   body starts with the verdict line, then the AC/DoD → test table and the findings:
   - **Any blocker or should-fix** → `Verdict: CHANGES`.
     `gh pr edit <pr> --add-label review:changes --remove-label review:passed`,
     `board.sh bump-attempts <task>`, `board.sh move <task> Todo`.
     If the new Attempts exceeds `limits.max_attempts`: `gh issue edit <task> --add-label needs-human`,
     comment why on the task, return `needs_human`. Otherwise return `changes_requested`.
   - **Only nits or nothing, and CI is not failing** → `Verdict: PASS` (list nits).
     `gh pr edit <pr> --add-label review:passed --remove-label review:changes`. The task stays
     `In Review`. Return `review_passed` with `head_sha` (the commit you reviewed).
   CI failing on the head commit is a blocker even if the code looks right.

Inline comments are optional: `gh api repos/<owner>/<repo>/pulls/<pr>/comments -f body=… -f commit_id=<sha> -f path=… -F line=…`.
Every finding must also be in the review body, so the developer sees all of them in one place.

## Never
- Edit, commit, push, check out branches in the main worktree, or run code that writes files.
- `gh pr review --approve`, `gh pr merge`, or remove `needs-human`.
- Pass a PR with missing input validation, an untested AC/DoD item, skipped or deleted tests,
  or failing CI.
- Review more than one PR per invocation.

End with the result block from `references/agent-output.md` and `references/results/review.md`.
