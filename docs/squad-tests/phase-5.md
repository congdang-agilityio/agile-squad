# Phase 5: QA loop — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Board: https://github.com/users/congdang-agilityio/projects/1
Every role ran as a fresh headless subagent dispatched by a PM prompt.

## Built
- `skills/qa/SKILL.md` (68 lines): prepare (item in `QA`, open child bugs block a pass, clean
  `.worktrees/qa` at the latest `origin/main`), verify (full suites, every criterion against
  the **running app** with the exact command and result, quick regression, stop the app),
  decide (pass: test report, `Done`, re-check request for a bug's parent, story and milestone
  closure; fail: one bug per problem from the template, `qa:failed`, Attempts + 1, item stays
  in `QA`; over `max_attempts`: `needs-human`).
- `references/bug-template.md`: task-compatible header (so `waves.sh` can schedule bugs),
  `Found in #<PR>`, failed criterion, steps, expected vs actual verbatim, evidence, DoD with a
  reproducing test.
- `worktree.sh qa`: detached checkout of the latest `origin/main` in `.worktrees/qa` with the
  QA slot (port `port_base`, database `<prefix>_qa`); refresh discards local changes.
- Output contract: QA `passed` gains `story_done` and `recheck`; new `blocked`.
- Dev skill: bugs are implemented in mode `implement` on their own `fix/` branch; `rework`
  is for review changes only. Board conventions: a failed task stays in `QA` with `qa:failed`
  until its bugs are `Done` and it is re-checked.

## Acceptance
| Check | Result |
|---|---|
| Passing task: #116 (health) verified on main against the running app (status, body, `Cache-Control` header), suites and CI green, test report, `Done` | PASS |
| **PR missing one AC → child bug, task not `Done`**: #122 (readiness, PR #123 deliberately without the `X-App-Version` header) → bug #124 sub-issue in `Todo` with `Found in #123`, reproduction and verbatim output; #122 labeled `qa:failed`, Attempts 1, stays in `QA` | PASS |
| After the fix QA passes it: Team Lead planned #124 (`tasks=#124`) → developer PR #125 (failing test first) → review PASS → Team Lead merge → QA passed #124 and returned `recheck: 122` → QA re-checked #122 → `Done`, `qa:failed` removed | PASS |
| **Task failing a 4th time stops with `needs-human`**: #126 (Attempts 3) failed again → bug #127, Attempts 4 > `max_attempts` 3 → `needs-human` + `qa:failed`, stays in `QA`, history commented | PASS |

**How the missing-AC fixture reached QA.** The tester wrote PR #123 without the header and
posted a fixture `Verdict: PASS`. The **Team Lead's final check still caught it** (it compares
the diff with the task's DoD) and rejected the merge, a useful second line of defense. With
the stakeholder's explicit permission the tester then merged #123 directly so the QA test
could run on main. #126 was created directly in `QA` with Attempts 3 to simulate earlier
returns.

Not tested: story closure (story #115 still has #117 in `QA`, #118 in `Todo` and #126 escalated)
and the milestone "Ready to deploy" note (no milestones yet); both come up again in Phase 6/7.

## Findings
1. **QA could not stop its app server** (`pkill`/`fuser` not allowed); it ended with the
   session. The skill now says: find the PID with `lsof -ti tcp:<QA port>` and `kill` only
   that PID (a `pkill` could hit other projects' servers on the same machine, and one was
   running).
2. **WebKit (iPhone profile) e2e cannot run locally**: host libraries are missing and there
   is no sudo. QA ran the Chromium profile locally and relied on CI (which installs the
   browsers) for WebKit, and said so in every report.
3. **Auto mode blocks merging without review** even for a test fixture; the stakeholder's
   explicit "Cho phép merge" was needed. squad itself never does this.
