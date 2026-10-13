# Phase 4: Dev + Review (including parallel) — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Board: https://github.com/users/congdang-agilityio/projects/1
Stakeholder: Cong. Every role ran as a fresh headless subagent (`squad:developer`,
`squad:reviewer`, `squad:team-lead`) dispatched by a PM prompt; one task or PR per invocation.

## Built
- `scripts/pr-size.sh <pr|branch> [--size XS|S|M]`: changed lines and files against `main`
  excluding `limits.pr_size_exclude`; size from the linked task when not given; exit 3 when over.
- `skills/dev/SKILL.md` (86 lines): modes `implement` (claim → worktree first → TDD → green →
  size check → rebase → PR → In Review), `rework` (fix every blocker/should-fix with a failing
  test first, no force push), `rebase` (keep both sides, `--force-with-lease`, removes
  `needs-rebase` **and** `review:passed`).
- `skills/review/SKILL.md` (57 lines): size → conflicts → read diff and tests → checklist →
  verdict by `gh pr review --comment` (`Verdict: PASS|CHANGES`), labels, Attempts, `needs-human`.
- `references/review-checklist.md`: severities, scope/size, AC/DoD ↔ test mapping,
  correctness, security (missing input validation is a blocker), tests, conventions.
- `worktree.sh`: `DATABASE_URL` per slot from `parallel.database_url_template`; config
  `commands.services` starts local services (sandbox: a Postgres container on port 55432).
- `plan` skill: `tasks=` parameter; a `needs-split` task may be re-sized instead of split.

## Acceptance
| Check | Result |
|---|---|
| Every task handled by a fresh `developer` invocation; `reviewer` has no Write/Edit (agent `tools: Read, Grep, Glob, Bash`) | PASS |
| Real task end to end: scaffold #95 (M, 254 lines / 10 files) → PR #113, CI lint/test/e2e green → review PASS with 3 nits → Team Lead merge → `QA` | PASS |
| **Two developers in parallel** on wave 12 (#116 slot 1, #117 slot 2): both `In Progress` at the same time (dev-1 / dev-2), separate worktrees, branches, ports 4101/4102 and test DBs `app_test_1/2`; both opened PRs (#119, #120) | PASS |
| After #119 merged, the deliberately conflicting #120 (both created `docs/api.md`) was labeled `needs-rebase` by `pr.sh merge`; a developer in `rebase` mode merged both doc entries, force-pushed with lease, removed `needs-rebase`; later merged | PASS |
| Oversized PR caught by the developer before opening: #118 (XS, 73 lines > 50) → no PR, split proposal, `needs-split`, branch pushed, `Todo` | PASS |
| Oversized PR forced through (PR #121 opened by the tester) → reviewer: `pr-size.sh` exit 3, detailed review skipped, `Verdict: CHANGES`, `needs-split` on PR and task, `Todo` | PASS |
| Planted bug (missing input validation): reviewer found it with 2 blockers + 2 should-fix (file:line), `review:changes`, Attempts 1, `Todo`; developer `rework` restored validation and tests (failing first); re-review PASS; merged; `QA` | PASS (see note) |
| Team Lead re-plans a `needs-split` task (`tasks=#118`): re-sized XS → S (one indivisible table) with a reason | PASS (closes the Phase 3 gap) |
| `phase-4.sh` (pr-size.sh, 6 cases) and `phase-3.sh` re-run | PASS (6/6, 24/24) |

**Note on the planted bug.** The tester pushed a commit to PR #120 that removed the `format`
validation and deleted its six invalid-input tests (CI stayed green), with the stakeholder's
one-time permission (the auto-mode classifier blocks "security test removal" by default). The
developer in `rebase` mode noticed the foreign commit first, refused to force-push it and
returned `blocked`; after the PM's PR comment marking it as an approved fixture, it rebased and
flagged the problem in its PR comment. The Reviewer therefore had a hint; its findings were
nevertheless independent and precise (`route.ts:11-14`, deleted tests, dead 400 branch,
docs mismatch).

## Findings fixed during testing
1. **`board.sh ready-tasks` failed with "Argument list too long"** once the board held ~80
   items with bodies (passed through `jq --argjson`). Large JSON now goes through temp files
   (`--slurpfile`), also in `issue.sh children`.
2. **A `Depends on` line with explanatory text** ("none (the scaffold from #95 …)") was read as
   a dependency on #95. Correct parser behavior; the task template now says the line holds
   only dependency numbers.
3. **`worktree.sh clean` refused after a merge** because of an untracked PR-body draft; with
   `--pr-merged` untracked leftovers no longer block the cleanup.
4. **Inline env vars (`PORT=4101 npx …`) are refused by permission rules**; the dev skill now
   says to read `.env.local` from tool configs and to keep helper scripts inside the worktree.
5. **Dev could not handle an already-open PR** for its branch; step 11 now updates it.

## Environment limits found
- **Memory:** two parallel developers (two Claude sessions, `npm ci` and Next.js in two
  worktrees) were killed by Claude Code's memory-pressure guard while ~2 GB was free. After the
  stakeholder stopped other Docker stacks (~4 GB free) the same run completed. Keep
  `parallel.max_parallel_dev` at 2 on a 16 GB machine.
- Fixtures #114–#118 stay on the board: #116 and #117 are in `QA` for the Phase 5 QA test;
  #118 (re-sized to S) has PR #121 open.
