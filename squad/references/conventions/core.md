# Conventions: core (every role)

Every squad skill and agent follows these rules. The GitHub Projects board is the single
source of truth: no work state lives in local files, and every role decides its next action
by reading the board, issues and PRs.

Project settings and IDs live in `.squad/config.yml` in the target repository. Numeric limits
quoted below are defaults; always read the real values from `limits` and `parallel` in the config.

Hard rules are also enforced by the guard hook (`scripts/guard.sh`): no push to `main`, no
`--admin` merge or self-approval, and each role writes files only in its own area. A blocked
call returns "squad guard: …" with what to do instead; never try to work around it.

## 1. Status column

| Status | Meaning | Moved there by |
|---|---|---|
| `Backlog` | Approved story, not yet split into tasks | PM (after GATE 2) |
| `Todo` | Task ready to be picked up; a planned story waits here until its tasks are done | Team Lead (also a merge rejected for rework); QA (bugs); Reviewer (rework); Dev (needs-split, or blocked after claiming) |
| `In Progress` | A developer (or DevOps, for an `infra` task) is working on it | Dev; DevOps |
| `In Review` | PR open, awaiting review | Dev; Team Lead (merge rejected for a new review) |
| `QA` | Merged (or platform change applied), awaiting testing | Team Lead (after final check and merge); DevOps (`infra`) |
| `Done` | QA passed, ready to deploy | QA |
| `Released` | Live in production | DevOps |

Never move an item to a status owned by another role, except as listed above.
Only squad scripts set Status: setup removes GitHub's built-in project workflows that would
(for example "Item closed" moving a task to Done when its PR merges, skipping QA).
The board listing (`board.sh list`, `ready-tasks`) can lag ~30 seconds behind newly added
issues; `board.sh get <issue>` always reads the current state.

## 2. Custom fields

| Field | Type | Values / meaning |
|---|---|---|
| `Priority` | single select | `P0`, `P1`, `P2`, `P3` |
| `Size` | single select | `XS`, `S`, `M` (no L: anything bigger must be split) |
| `Wave` | number | Set by the Team Lead; tasks in the same wave may run in parallel |
| `Agent` | text | Developer slot working on the task, e.g. `dev-1` |
| `Attempts` | number | Times the task has been sent back by review or QA |

Releases are grouped by repository **milestones**.

## 3. Labels

`type:epic`, `type:story`, `type:task`, `type:bug`, `type:report`, `qa:failed`,
`review:changes`, `review:passed`, `needs-split`, `needs-rebase`, `needs-human`, `blocked`,
`quick` (quick-lane task from `/squad:fix`: no parent story, no wave; QA checks its DoD only),
`infra` (platform change: DevOps does it with `scripts/railway.sh`, no PR; QA checks the effect)

## 4. Issue relationships

- Epic → Story → Task are linked as GitHub **sub-issues** (GraphQL `addSubIssue`).
- A QA bug is a sub-issue of the original task (or story) and states `Found in #<PR>`. The
  failed task keeps label `qa:failed` and stays in `QA`; it reaches `Done` only when all its
  bugs are `Done` and QA re-checks it. A story moves to `Done` when all its tasks are `Done`
  and QA has verified the story's ACs.
- Dependencies are written in the task body: `Depends on #12, #15`. A task is ready only when
  every dependency is `Done` or `Released`.
- Every task body has a `Files (expected)` section listing the files/modules it will touch.
  The Team Lead uses it for conflict detection.

## 5. Bounded loops

A task sent back more than `limits.max_attempts` times (by review or QA) stops, gets
`needs-human`, and is escalated to the stakeholder by the PM.

## 6. Language

- Every artifact is in **English**: analysis, questions, PRD, epics, stories, acceptance
  criteria, tasks, bugs, PRs, review comments, commits, release notes, reports.
- Conversation with the stakeholder uses the stakeholder's language. Vietnamese answers are
  recorded verbatim **and** with a meaning-preserving English translation.
- Vietnamese business terms without a clean English equivalent: English first, original in
  parentheses, e.g. `household registration book (sổ hộ khẩu)`.

## 7. Human gates

Exactly three; never skip or infer them:
1. **Requirement sign-off** (before any story is written)
2. **Story approval** (before any task breakdown)
3. **Production deploy approval** (GitHub Environment required reviewers)
