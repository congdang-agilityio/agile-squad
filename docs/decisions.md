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

## D-11 (2026-10-14): Quick lane (`/squad:fix`)
The final review found no path for small changes: a one-line fix went through BA, two gates,
story planning and story QA. `/squad:fix` sends the stakeholder's words to the Team Lead
(mode `quick`), which creates one XS/S task labeled `quick` with no parent story and no wave,
or refuses (`too_big_for_fix`) when the request needs several tasks or a product decision.
Developer, review, Team Lead merge and QA run unchanged; QA checks the task's DoD and request
only. No gate before the task: the request is the stakeholder's own. Done quick tasks without
a milestone are listed as `unreleased`.

## D-12 (2026-10-14): Model per dispatch and a token budget
Run 8 cost $37.72 for three stories with every subagent on Opus. Config `models` names a model
per role and task size (default Sonnet for XS/S development, XS review and XS/S QA; Opus for M,
S review and story QA); `next.sh` puts it on each action and the PM passes it to the Agent
call. `/squad:run max-tokens=N` (default `budget.max_tokens_per_run`) stops new dispatches once
the subagents' reported tokens reach N. It is an approximate guard; the hard dollar cap for
headless runs is `claude -p --max-budget-usd`.

## D-13 (2026-10-14): `/squad:doctor`
Thirteen troubleshooting rows in the README were symptoms of setup drift (lost ids, missing
scopes, conflicting project workflows, the merge permission). `doctor.sh` checks them all
read-only and prints a fix per problem; the `doctor` skill applies fixes after a yes. Setup
ends with it, and the run loop calls it when `next.sh` fails.

## D-14 (2026-10-14): Final review fixes before publishing
Two independent read-only reviews (cross-file consistency; script bugs) found 52 issues. The
ones that changed behavior:
- A developer that returns `blocked` after claiming a task gives the slot back (label
  `blocked`, Agent cleared, task to `Todo`); before, the slot stayed busy forever.
- A failed smoke test deletes the draft release, so the fixed milestone can be released
  again; the P0 bug carries the milestone, and open P0/P1 bugs are always in a run's scope.
- `next.sh` reports GATE 1 and GATE 2 (`gate_1`, `gate_2`), gives a rebase its own developer
  slot, and passes the PR number for rework.
- A Team Lead merge rejection for rework labels `review:changes` and counts an attempt, like a
  review; the developer reads that comment.
- DevOps uses `release.sh draft | deploy | wait | publish` instead of pipes, sleep loops and
  multi-line arguments that permission rules refuse; known limitations become `--note` lines.
- `cfg` returns `false` (so `merge.require_ci: false` works); CI lookup errors block a merge.
- Portability: bash 4+ is required and checked; BSD `sed`/`date` forms replaced.
- QA starts the app with new `commands.build` / `commands.start` instead of npm.
Not fixed (documented limits): fixed listing caps (projects 100, open PRs 200, issues 500)
and a rewave that file overlaps cannot improve (the PM rewaves at most once per run).

## D-15 (2026-10-15): Hard rules as a hook, evals, per-role reading, Sonnet for triage
- The rules that matter most (no push to `main`, no admin merges or self-approvals, each
  role writes only in its own area) are enforced by a PreToolUse hook (`scripts/guard.sh`)
  that reads `agent_type`; prompts alone had let a developer edit the main checkout once
  (phase 7). Plugin agents cannot carry their own hooks, so one plugin hook filters by agent.
  The main session stays unrestricted beyond the global rules: users may work in it.
- Conventions and result statuses are split per role; each subagent reads 20–59% less.
- `models.quick: sonnet`: on 10 dry-run requests Sonnet decided like Opus (10/10) at ~1/4 of
  the cost once the agent definitions spelled out the fenced-JSON, English result block
  (before: 1/10 blocks in format). The rule now applies to every agent.
- Behavior evals (`squad/evals/`, `claude plugin eval`) cover routing and gate discipline;
  they run on demand because they cost API credits. Script tests run in CI on every push.
- `deploy.platform: none` and `/squad:setup quick` let a team start without a hosting setup.

## D-16 (2026-10-15): DevOps operates Railway with the CLI; no tokens anywhere
Replaces the GitHub Actions deploy (D-3 era): DevOps could not provision a database, set the
pre-deploy command or read logs, so the stakeholder did it by hand (phase 7, v0.2.0), and
GitHub held one Railway token per environment.
- The Railway CLI runs under the stakeholder's own `railway login` on the machine running
  squad. `scripts/railway.sh` is the only entry point (enforced by the guard hook): it prints
  variable names, never values; refuses secret-looking variables (the stakeholder sets those);
  and requires approval for every production change, recorded on the issue.
- GATE 3 stays a GitHub approval for its audit trail and because it cannot be forged by the
  agents: `release-gate.yml` has one job behind the `production` Environment, deploys nothing
  and needs no secrets. `railway.sh deploy production --gate-run <id>` checks that the run
  approved that commit.
- Deploys use `railway up` from a clean worktree at the tested commit, so production gets
  exactly what staging ran.
- Platform work is planned as `infra` tasks; staging changes are autonomous, production
  changes need the stakeholder's explicit yes.

## D-17 (2026-10-15): Models by complexity, not size; escalate on retry
Size measures lines, not risk: a 20-line change to session handling is hard, 250 lines of
boilerplate are easy. Borrowed from super-board's per-card router, but without its extra
run-time classifier call: the Team Lead sets `Complexity` while planning, with a written
rubric, and `next.sh` maps role × complexity to a model (Size remains the fallback for tasks
planned before). A task sent back by review or QA runs one tier higher next time, so the
cheap model is tried first and the expensive one is paid for only where it failed. The
savings are not measured yet: compare the PM's end-of-run token totals per role (or
`claude -p` total_cost_usd) for similar work before and after, on a real project.

## D-18 (2026-10-15): Claims across machines through issue comments
Slots were board-wide names (`dev-1`), so a second developer's machine could take the same
task and treat it as its own resumed run. GitHub has no atomic compare-and-set on project
fields, but issue comments are totally ordered: a worker posts a claim comment and the
earliest claim of the last 10 minutes wins; the loser deletes its comment and backs off. The
Agent field then records `who@machine time`, which `next.sh` reads to keep slots per machine
and to skip items another machine is working on. Claims expire (`claim_ttl_minutes`) so a
crashed machine never blocks an item for good; stale claims are reported, not silently taken.
The "Started by" prefix is kept so cycle-time metrics still work.
