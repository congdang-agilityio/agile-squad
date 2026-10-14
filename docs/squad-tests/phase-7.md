# Phase 7: Report + Orchestrator — test log

Date: 2026-10-13/14 · Sandbox: congdang-agilityio/squad-sandbox · Railway project `squad-sandbox-todonow`

## Built
- `scripts/metrics.sh --since/--until | --milestone`: delivery metrics as JSON (items done,
  released, PRs merged, review rounds, QA failures, bugs by priority, cycle and lead times,
  attempts, needs-human, deploys).
- `skills/report` + `references/report-template.md` + `reporter` agent: the reporter copies every
  number from the metrics JSON into `.squad/reports/<date>.md` (gitignored draft); the PM
  publishes it as a `type:report` issue and asks the decision questions.
- `scripts/next.sh [--scope]`: the PM's read-only view of the board. Prioritised `actions`; a
  `batch` (one action per independent lane: deploy, QA, PR review/merge, rebase, plan, plus all
  dev actions; capped by `parallel.max_agents`, default 3); `rewave` (free developer slots while
  ready tasks wait in later waves); `unreleased` (Done stories whose tasks are in no milestone).
- `skills/run`: the PM loop. Dispatch the whole batch in one message, follow result blocks only
  through the next `next.sh`. A requirements question stops the loop; a pending GATE 3 only
  holds the deploy lane (the stakeholder is told once, the team keeps working); stop when only
  GATE 3 is left, at max steps, or when nothing is left (then report). Asks the stakeholder for
  a milestone when stories are Done but unreleased.
- Team Lead modes `rewave` (recompute waves of unstarted tasks) and `milestone`
  (`issue.sh milestone <title> <stories>`: stories, tasks and their bugs into a release).

## Fixes found by the acceptance runs
| Found | Fix |
|---|---|
| `migration_lock.toml` pushed a task over its file budget | `**/migration_lock.toml` in `pr_size_exclude` |
| GitHub links `Closes #N` with a delay; a fresh PR had no task | `next.sh`/`pr.sh`: fall back to the PR body, then the branch name |
| PRs were handled newest first | oldest first |
| One subagent per step; QA waited for development | `batch`: lanes run in parallel |
| Stale waves left developer slots idle | `rewave` + Team Lead mode `rewave` |
| DevOps could not find the bug template | full `references/…` paths; every skill says where those paths live |
| Same task offered to `plan` and `dev` in one batch | dev candidates exclude tasks being planned |
| A story waiting only for a stakeholder answer was never re-checked | `qa` with `story: true` for open stories whose tasks are all Done; QA labels `blocked` when only the stakeholder can answer; the PM removes it with the recorded answer |
| `blocked` items in QA were offered again | QA lane skips `needs-human` and `blocked` |
| After a rejected GATE 3 the draft release kept `deploy_finish` coming back | DevOps `finish` deletes the draft on reject/cancel |
| A published release whose milestone stayed open was offered as a new release | published-but-open counts as unfinished → `deploy_finish` |
| A task was sent to QA while its bug was still in QA (a merged fix closes the bug issue) | bug wait uses board status, not issue state |
| Done stories without a milestone were never released, and nobody asked | `unreleased` in `next.sh`, the PM asks, Team Lead mode `milestone` |
| GATE 3 stopped the whole team for hours | GATE 3 holds only the deploy lane |

## Acceptance runs (headless `/squad:run`)
| Run | Scope | Steps | Time | Cost | Outcome |
|---|---|---|---|---|---|
| 1 | #34,#35 | 36 | 132 min | $21.58 | 8 tasks merged and QA passed; v0.2.0 staging smoke failed (no database) → P0 bug #140; GATE 3 rejected by the stakeholder |
| 2 | #34,#35 | 6 | 19 min | $4.01 | draft deleted; story #34 Done after the recorded approval; #140 fixed in code (PR #141); QA on staging → bug #142, `blocked` (needs Railway logs) |
| 3 | #34,#35 | 1 | — | $0.67 | QA #142 `blocked`: migration log needed (agents have no Railway access) |
| 4 | #34,#35 | 3 | 14 min | $1.85 | #142, #140 passed; v0.2.0 staging OK → GATE 3 (approved by Claude on the stakeholder's instruction) |
| 5 | #36 | 1 | 3 min | $0.89 | stopped: the rebuilt sandbox config lacked board field ids (after a machine restart) |
| 6 | #36 | 30 | ~28 min* | $18.85 | v0.2.0 released; #104–#107 Done; QA found P0 bug #147 (task page rendered for an unknown session); WebKit `Secure` cookie issue split into #151 |
| 7 | #36,#62,#63 | 13 | 62 min | $10.57 | stories #36 and #63 Done; #62 deferred (depends on #37); no release: no milestone (→ fix) |
| 8 | #37,#38,#62 | 45 | 132 min | $37.72 | milestone set by the Team Lead; v0.3.0 staging → GATE 3 (approved by Claude on instruction) → released; stories #37, #38, #62 Done (12 PRs, 2 review reworks incl. a reset-link host-injection finding); report #183 |

\* last segment of the stream; the run took longer.

Stakeholder actions between runs (the human, not the squad): rejected GATE 3 of run
38425771242; approved the privacy notice text (#34) and the sign-up length limits (#35); added
Railway Postgres to staging and production with `DATABASE_URL` on `web`; set the Railway
Pre-Deploy Command `npm run db:deploy` on `web` (Railway ignores `railway.json` for `railway up`
uploads; config-as-code is deprecated); posted the migration log on #142; named release
`v0.3.0 login and logout`; approved GATE 3 for v0.2.0 and v0.3.0 (executed by Claude).

## Parallel developers (run 8, from the board: "Started by dev-N" comment → PR opened)
| dev-1 (slot 1) | dev-2 (slot 2) | Overlap |
|---|---|---|
| #161 03:23:46 → PR #172 03:31:08 | #159 03:26:31 → PR #173 03:35:16 | 4 min 37 s |
| #166 03:32:10 → PR #174 03:38:45 | #159 (as above) | 3 min 06 s |
| #164 04:35:10 → PR #180 04:43:07 | #170 04:40:43 → PR #181 04:47:13 | 2 min 24 s |

Each developer worked in its own worktree, port and test database. The PM logged it at the
time ("Developers are on #159 and #166"), while the reviewer and QA ran in their own lanes.

## Acceptance
| Check | Result |
|---|---|
| Main session only talks to the stakeholder and dispatches | PASS. Run 8: 60 Agent dispatches, 53 `next.sh`, 1 `issue.sh create report`, 1 Read (report draft), 1 Skill (report). Runs 1–7: only Agent, `next.sh` and a few read-only `gh` calls. No code, review, test, merge or deploy in the main session |
| An approved story goes all the way to staging using parallel developers and stops at the production gate | PASS. Stories #35 (v0.2.0) and #36/#63 (v0.3.0) went plan → tasks → review → merge → QA → staging smoke → GATE 3; run 8 used two developers in parallel (table above) |
| Report numbers match the board | PASS. `.squad/reports/2026-10-13.md` (run 1) and report #183 (run 8): every number is from the `metrics.sh` JSON |

## Real defects the squad caught itself
Missing input length limits (#102, review); no database on staging (#140, smoke); migration not
run on Railway (#142, QA); task page rendered for an unknown session token (#147, QA); `Secure`
cookie breaking WebKit login (#151, review/dev); reset link pointable at a forged host (PR #177,
review).

## Open items
- Requirements gap: the sign-up screen had no way in from the home page (fixed by #36's
  redirect to `/login` + link). Lesson for the BA skill: every new screen needs an entry point.
- Sandbox only: #37/#38/#62 are Done but unreleased; e-mail provider not configured; fixture
  leftovers #118 (PR #121) and #126/#127.
- A process in run 5 edited `package.json` in the main checkout (not in a worktree); not
  reproduced in later runs.
