# Decisions that change plan.md

## D-1 (2026-10-13): Review by comment, Team Lead merges, one GitHub account
Stakeholder decision after verifying that GitHub rejects self-approval
("Can not approve your own pull request", sandbox PR #31).

- All roles use **one** GitHub account.
- **Reviewer** (plan 5.5): posts its verdict with `gh pr review --comment`, never `--approve`,
  never merges. PASS → label `review:passed` (new label). Otherwise → `review:changes`,
  Attempts + 1, task back to `Todo`. Result status `review_passed` replaces `approved_merged`.
- **Team Lead** gets a `merge` mode: final check of PRs labeled `review:passed` (PASS comment
  is for the current head SHA, CI green, no conflicts, scope matches the task), then squash-merge,
  delete branch, task → `QA`, label conflicting open PRs `needs-rebase`. Result statuses
  `merged | merge_rejected | needs_rebase`. Team Lead tools now include
  `gh pr view/checks/diff/edit/comment/merge --squash` (merge mode only).
- **Status `QA`** is set by the Team Lead after merging, not by the Reviewer (plan 3.1).
- `run` loop (plan 5.9) gains a step: PRs labeled `review:passed` → `team-lead` in `merge` mode.

## D-2 (2026-10-13): Developers never push to main
- A developer creates the task branch from the latest `main` before writing any code and
  delivers only through a PR.
- Branch protection on `main` has `enforce_admins: true`, so even the shared (admin) account
  cannot push to `main`. Verified on the sandbox: a direct push is rejected with GH006, while a
  comment review + `review:passed` + squash merge of PR #32 succeeds.

## D-3 (2026-10-13): Sandbox is public
`congdang-agilityio/squad-sandbox` was made public so branch protection works on the free plan.

## D-4 (2026-10-13): Dispatch plan is an epic comment, waves are computed by a script
- Plan 5.3 step 6 asks for `docs/plans/<date>-dispatch.md`. Writing it would need a commit to
  `main` (forbidden, D-2) or a docs PR per plan. Instead the Team Lead posts the dispatch plan
  (`references/dispatch-plan-template.md`) as a **comment on the epic**; the `Wave` field on the
  board stays the source of truth.
- Waves are computed by `scripts/waves.sh` from `Depends on`, `Files (expected)` and serial
  rules (precision-critical, so not left to the model), capped at `parallel.max_parallel_dev`.

## D-5 (2026-10-13): Stack choice belongs to the stakeholder
- New config key `stack`. In a repo without application code and an empty `stack`, the Team
  Lead creates no tasks and returns `blocked` with a proposed stack; the PM asks the stakeholder.

## D-6 (2026-10-13): Merge permission
- Claude Code auto mode blocks `gh pr merge` ("Merge Without Review"). `setup` offers the
  allow rule `Bash(gh pr merge:*)`; new config key `merge.require_ci` (default true).

## D-7 (2026-10-14): Report drafts stay local, the issue is the record
Plan 2.1 puts reporter output in `docs/reports/`. Committing it would need a PR per report
(D-2). The reporter writes `.squad/reports/<date>.md` (gitignored); the PM publishes it as a
`type:report` issue, which is the record.

## D-8 (2026-10-14): GATE 3 holds only the deploy lane
Plan 5.9 stops the run at every human gate. A production approval happens on GitHub and can
take hours, so a pending GATE 3 no longer stops the team: the PM tells the stakeholder once and
keeps dispatching the other lanes; the run stops when only GATE 3 is left. GATE 1/2 and
requirements questions still stop the loop.

## D-9 (2026-10-14): Releases are named by the stakeholder
Stories become releasable only through a milestone. `next.sh` lists Done stories whose tasks
are in no milestone (`unreleased`); the PM asks the stakeholder for a milestone title and the
Team Lead (mode `milestone`) puts the stories, their tasks and bugs into it. The deploy gate
then releases it.

## D-10 (2026-10-14): Parallel lanes and rewave
The run loop dispatches one action per lane (deploy, QA, PR review/merge, rebase, plan) plus
all developer actions in one message, capped by `parallel.max_agents` (default 3, memory).
When developer slots are idle while ready tasks wait in later waves, the Team Lead recomputes
waves (mode `rewave`). Serial tasks still stand alone in their wave.
