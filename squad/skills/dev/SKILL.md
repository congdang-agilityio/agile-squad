---
name: dev
description: "Developer procedure: implement exactly one task issue with TDD in its own git worktree, keep the change within the task's size, and open a small PR; or rework a PR after review/QA feedback; or rebase a PR labeled needs-rebase. Use when a task in Todo is dispatched to a developer slot, when review or QA sends a task back, or when a PR conflicts with main."
---

# squad: dev (one task, one PR)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

The PM dispatches a fresh `developer` subagent per task:
`mode=implement|rework|rebase issue=<n> slot=<k> agent=dev-<k>@<machine> config=.squad/config.yml`
(rework and rebase also get `pr=<n>`). Several machines may work on one board: the claim in
step 2 makes sure only one worker takes a task. One task per invocation. When invoked directly
(`/squad:dev <issue>`), dispatch the `developer` subagent instead of doing the work here.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`worktree.sh`, `board.sh`, `issue.sh`,
`pr-size.sh`), called with literal arguments. Rules: `references/conventions/`
(`core`, `git`, `sizing`). Commands and limits come from the config.

## Mode implement
1. **Check.** `board.sh get <n>`: the task is in `Todo` (or `In Progress` with your own
   `agent`, a resumed run), not labeled `blocked`/`needs-human`/`needs-split`, and every
   `Depends on` issue is `Done` or `Released`. Otherwise return `blocked`.
2. **Claim.** `board.sh claim <n> dev-<k>` (posts "Started by dev-<k>@<machine>" and sets
   `Agent`). Exit 3 = another worker or machine has it: change nothing, return
   `claimed_elsewhere`. Then `board.sh move <n> "In Progress"`.
3. **Worktree first.** `worktree.sh <n> <k>` creates `.worktrees/<n>` on
   `feat|fix/<n>-<slug>` from the latest `origin/main`. Work, run and commit **only there**
   (absolute paths). `.env.local` holds this slot's `PORT`, `TEST_DB_NAME`, `DATABASE_URL`:
   use them for servers and tests, never the defaults or another slot's. Make tools read
   `.env.local` (most frameworks do; else load it in the test/server config): inline
   `VAR=… cmd` prefixes are refused by permission rules. Keep helper scripts inside the worktree.
4. **Read.** The task (Goal, Out of scope, Files (expected), DoD, ACs covered), the parent
   story (`issue.sh parent <n>`, then `gh issue view`), all comments, and the code you will
   touch. Unclear or contradictory task → comment the question on the task, return `blocked`.
5. **Set up.** Run `commands.install` when dependencies are missing or the lockfile changed,
   and `commands.services` when tests need services (database).
6. **TDD.** For each DoD item / AC: write a failing test, see it fail, implement until it
   passes. Validate every external input. Stay inside the task scope; anything else you notice
   becomes a comment on the task, not code.
7. **Green.** `commands.lint` and `commands.test` (and `commands.e2e` when the task has UI or
   e2e items) all pass. Never skip, delete or weaken tests to get there.
8. **Commit** with Conventional Commits ending in `(#<n>)`.
9. **Size.** `pr-size.sh <branch>` (task size from the board). Exit 3 = over the limit:
   - do not open the PR; comment on the task with a split proposal (2–3 smaller tasks, each
     with goal, files and size), `gh issue edit <n> --add-label needs-split`,
     `board.sh move <n> Todo`, push the branch so the work is kept, return `needs_split`.
10. **Rebase and push.** `git fetch origin`, `git rebase origin/main`, re-run tests if anything
    changed, `git push -u origin HEAD`.
11. **PR.** If an open PR already exists for the branch (`gh pr list --head <branch>`), update
    its title/body with `gh pr edit` instead. Otherwise
    `gh pr create --base main --title "<type>: <summary> (#<n>)" --body-file -` with:
    `Closes #<n>`, a one-paragraph summary, the DoD/AC checklist ticked with the test that
    proves each item, manual test steps, the `pr-size.sh` numbers, and any small extra file
    outside `Files (expected)` with the reason.
12. `board.sh release <n>`, `board.sh move <n> "In Review"`. Return `pr_opened` with `pr`, `slot`, `size`.

**Returning `blocked` after step 2** (any mode): give the slot back so the task is not stuck
`In Progress`: comment the question on the task, `gh issue edit <n> --add-label blocked`,
`board.sh release <n>`, `board.sh move <n> Todo`.

## Mode rework
After `review:changes` (review comments on the PR). QA bugs are separate `type:bug` issues:
they are implemented in mode `implement` on their own `fix/<bug>-…` branch and PR.
1. Claim as in step 2 (`board.sh claim`, then `In Progress`).
2. `worktree.sh <n> <k>` reuses the task branch. `git pull --rebase` so it matches the PR.
3. Read the newest `Verdict: CHANGES` review, or the newest "Team Lead final check: **not
   merged**" comment if it is newer (`gh pr view <pr> --json reviews,comments`).
   Fix **every** blocker and should-fix, each with a test that fails before the fix. Nits are
   optional.
4. Green, commit (`fix: … (#<n>)`), size check, push (no force push).
5. Comment on the PR: one line per finding → what changed and where. Remove the label
   (`gh pr edit <pr> --remove-label review:changes`).
6. `board.sh release <n>`, `board.sh move <n> "In Review"`. Return `pr_opened`.

## Mode rebase
For a PR labeled `needs-rebase`.
1. `board.sh claim <n> dev-<k>` (exit 3 → return `claimed_elsewhere`); `worktree.sh <n> <k>`;
   `git fetch origin`; `git rebase origin/main`.
2. Resolve conflicts keeping the behavior of **both** sides; no new features. If the conflict
   cannot be resolved without changing behavior, `git rebase --abort`, comment why, return
   `blocked`.
3. Lint and tests green, then `git push --force-with-lease`.
4. `gh pr edit <pr> --remove-label needs-rebase --remove-label review:passed` (the new head
   needs a fresh review), comment "Rebased on main by dev-<k>; needs review", keep the task in
   `In Review`, `board.sh release <n>`. Return `rebased`.

## Never
- Commit or push to `main`, merge any PR, or approve one.
- Write code before the worktree exists, or outside your own `.worktrees/<n>`.
- Work on more than one task, or beyond the task scope ("while I'm here" refactors need a task).
- Disable, skip or delete tests, or weaken assertions, to get green.
- Open a PR over the size limit, or force-push except in rebase mode (`--force-with-lease`).
- Put secrets in code, tests, commits or PR text.

End with the result block from `references/agent-output.md` and `references/results/dev.md`.
