# Phase 3: Team Lead — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Board: https://github.com/users/congdang-agilityio/projects/1

## Built
- `scripts/worktree.sh <issue> <slot>` / `clean <issue> [--force] [--delete-branch [--pr-merged]]` /
  `list`: one worktree per task in `.worktrees/<issue>` on `feat|fix/<issue>-<slug>` (new
  branches from the latest `origin/main`; existing local or remote branches reused), `.env.local`
  with `SQUAD_SLOT`, `PORT = port_base + slot`, `TEST_DB_NAME = <prefix>_<slot>`. `.worktrees/`
  and `.env.local` go to `.git/info/exclude` (no commit). `clean` refuses uncommitted changes
  and keeps a branch that has commits not in `main` unless its PR was merged.
- `scripts/waves.sh plan <issue>... [--write]` (and `--from-json` for offline tests): computes
  waves from `Depends on`, `Files (expected)` overlap and serial rules (explicit `Serial: yes`,
  layers schema/config/infra, or shared files: migrations, manifests, lockfiles, CI, build
  config, `.env`, shared routers, middleware), capped at `parallel.max_parallel_dev`;
  critical-path list scheduling; reports cycles, unplanned dependencies, missing file lists.
- `scripts/pr.sh check|merge|reject|conflicts`: the Team Lead's final check and merge (D-1).
  `check` returns facts and hard conditions (open, base main, `review:passed`, latest
  `Verdict: PASS` posted **on the head commit**, CI green, mergeable, linked task, no blocking
  label) plus advisory `unexpected_files`. `merge` squash-merges with `--match-head-commit`,
  deletes the remote branch, cleans the worktree, moves the task to `QA` and labels newly
  conflicting PRs `needs-rebase`. `reject <pr> review|rework -` removes `review:passed`,
  comments the reason, keeps the task `In Review` (fresh review) or sends it to `Todo` (rework).
- `issue.sh create … -` reads the body from stdin.
- `skills/plan/SKILL.md` (95 lines): modes `plan` and `merge`.
- `references/task-template.md`, `references/dispatch-plan-template.md`.
- Config: `stack` (D-5), `merge.require_ci` (D-6). `setup` offers the `Bash(gh pr merge:*)`
  allow rule and no longer allows committing to `main`.
- Decisions D-4 (dispatch plan as epic comment, waves by script), D-5 (stack is the
  stakeholder's choice), D-6 (merge permission) in `docs/decisions.md`.

## Acceptance
| Check | Result |
|---|---|
| New repo with empty `stack`: Team Lead creates nothing and returns `blocked` with a stack proposal; PM asks the stakeholder ("Duyệt"), writes `stack` | PASS |
| Stories #34, #35, #36 → 14 tasks #95–#108 as sub-issues, each with Goal, Out of scope, `Files (expected)` (real paths), `Depends on`, DoD with tests, ACs covered | PASS |
| ≥ 80% XS or S; every M has `Why not smaller` | PASS — 13/14 (92%); the one M (scaffold #95) explains why |
| Story ≤ `story_max_tasks` (5): 4 + 5 + 5 tasks | PASS |
| Migrations serialized: #99 (User) and #104 (Session) are alone in their waves; scaffold, dependency changes and middleware too | PASS |
| Independent, non-overlapping tasks share a wave: `[97,101]`, `[98,105]`, `[102,106]` | PASS (after the waves.sh fix below) |
| `Wave` written on the board for every task; stories moved to `Todo`; dispatch plan posted on epic #33 (re-plan with the fixed script: 11 waves, comment supersedes the first) | PASS |
| `phase-3.sh`: waves rules (10 offline cases + 3 regression cases on the real plan) and worktree.sh (11 cases on the sandbox) | PASS (24/24) |
| Merge mode, stale verdict (PASS on an older commit): not merged, `review:passed` removed, reason commented | PASS (PR #111, `merge_rejected`, next `review`) |
| Merge mode, valid PR: squash-merged pinned to head, remote branch + worktree + local branch removed, task → `QA`, the other open PR that now conflicts labeled `needs-rebase` | PASS (PR #111 → aad25a5, task #109 → QA, PR #112 labeled) |
| Merge mode, conflicting PR: not merged, `needs_rebase` | PASS (PR #112) |

Merge fixtures #109–#112 were closed and archived from the board; the smoke CI check
(`.github/workflows/squad-smoke.yml`) stays on `main` as a harmless always-green check.

Not tested: `story_too_big` (no story in the sample needed more than 5 tasks) and re-splitting
a `needs-split` task (comes with Phase 4).

## Findings fixed during testing
1. **Waves were a chain of 14 single-task waves.** Placing each task greedily in its earliest
   wave let serial tasks push everything apart. Replaced by wave-by-wave list scheduling ranked
   by critical path: 14 → 11 waves on the same tasks (the minimum is about 10 with 6 serial
   tasks), with three parallel pairs.
2. **Next.js `route.ts` endpoints were treated as shared routing** (regex `routes?\.ts`). Now
   only `routes.*`/`router.*` and `middleware.*` count. The Team Lead had worked around it by
   listing endpoint directories, which is also fine.
3. **`pr.sh reject` sent every rejected task back to `Todo`**, which would make the PM dispatch
   a developer when only a fresh review was needed. It now takes `review|rework`.
4. **`worktree.sh clean --delete-branch` could delete a branch with unpushed commits.** It now
   keeps such branches unless `--pr-merged` (used by `pr.sh merge` after a squash merge).
5. **`waves.sh` dropped the leading dot of paths** (`lstrip("./")` strips characters, so
   `.github/workflows/ci.yml` became `github/workflows/ci.yml`), found by the Team Lead in its
   re-plan. Overlap detection was unaffected (both sides lost the dot); fixed and tested.
6. `worktree.sh` exited silently when no branch existed (`[[ … ]] && …` as the last command
   under `set -e`).

## Observations for later phases
- **Planning time:** creating 14 tasks took longer than a 10-minute headless timeout (each
  `issue.sh create` makes several API calls; most time is the model reading code and writing
  bodies). The run was idempotent: the re-run reused #95–#108. The `run` loop must not put a
  short timeout on the Team Lead.
- **`gh pr close --delete-branch`** cannot delete a local branch that a worktree uses;
  `pr.sh` deletes the remote branch through the API instead.
- After a rebase the old `review:passed` label stays while the verdict becomes stale;
  `pr.sh check` catches it, but the Phase 4 developer `rebase` mode should remove
  `review:passed` so the PM sends the PR back to review rather than to merge.
