# Board conventions

Every squad skill and agent follows these rules. The GitHub Projects board is the single
source of truth: no work state lives in local files, and every role decides its next action
by reading the board, issues and PRs.

Project settings and IDs live in `.squad/config.yml` in the target repository. Numeric limits
quoted below are defaults; always read the real values from `limits` and `parallel` in the config.

## 1. Status column

| Status | Meaning | Moved there by |
|---|---|---|
| `Backlog` | Approved story, not yet split into tasks | PM (after GATE 2) |
| `Todo` | Task ready to be picked up | Team Lead; QA (bugs); Reviewer (rework) |
| `In Progress` | A developer is working on it | Dev |
| `In Review` | PR open, awaiting review | Dev |
| `QA` | Merged, awaiting testing | Reviewer |
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
`review:changes`, `needs-split`, `needs-rebase`, `needs-human`, `blocked`

## 4. Issue relationships

- Epic → Story → Task are linked as GitHub **sub-issues** (GraphQL `addSubIssue`).
- A QA bug is a sub-issue of the original task (or story) and states `Found in #<PR>`.
- Dependencies are written in the task body: `Depends on #12, #15`. A task is ready only when
  every dependency is `Done` or `Released`.
- Every task body has a `Files (expected)` section listing the files/modules it will touch.
  The Team Lead uses it for conflict detection.

## 5. Git

- Branches: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`
- Worktrees: `.worktrees/<issue>` (git-ignored)
- Conventional Commits (`feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`)
- PR title: `<type>: <summary> (#<issue>)`; body contains `Closes #<issue>` and the
  acceptance-criteria checklist
- **Squash** merge only. `main` is protected and CI must be green.

## 6. Sizing rules

### Stories (BA)
- A story is a vertical slice: the user can see or use something, however small.
- At most `limits.story_max_ac` (default 5) acceptance criteria. More means split.
- A story needing more than `limits.story_max_tasks` (default 5) tasks goes back to the BA.
- Preferred splitting patterns: by workflow (happy path first, errors/edge cases later), by
  CRUD operation, by business rule, by user role, by data type or channel, simple version first.

### Tasks (Team Lead)

| Size | Description | PR limit (excluding tests, lockfiles, generated files) |
|---|---|---|
| `XS` | Config, one function, one field | ≤ 50 changed lines, ≤ 3 files |
| `S` | One logical unit: endpoint, component, migration | ≤ 150 lines, ≤ 6 files |
| `M` | Maximum allowed | ≤ 300 lines, ≤ 10 files |

- Target XS and S. M only when no sensible split exists, with a `Why not smaller` section.
- One task does **one thing** in **one layer** (schema, service, API, UI, job), unless splitting
  would leave dead or untestable code.
- Every task is **independently mergeable**: CI green, nothing broken. Unfinished work sits
  behind a feature flag or stays unwired.
- Every task has its own Definition of Done, verifiable by tests.
- Suggested order: data/schema → logic/service → API → UI → wiring/feature flag → e2e.

## 7. Parallel development

- Tasks share a wave **only if** they do not depend on each other **and** their
  `Files (expected)` lists do not overlap.
- Always serialized (alone in their wave relative to the same area): database
  migrations/schema, dependency changes (`package.json`, lockfiles), shared routing/config
  files, CI/build config.
- At most `parallel.max_parallel_dev` developers at once.
- Each developer slot gets its own worktree, port (`port_base + slot`) and test database
  (`<test_db_prefix>_<slot>`).
- Developers rebase on the latest `main` before opening a PR. When a merge makes another open
  PR conflict, the Reviewer labels it `needs-rebase`; the PM dispatches a developer in
  `rebase` mode.
- If more than `parallel.max_open_prs` PRs wait in `In Review`, the PM dispatches no new
  developers until the queue drains.

## 8. Bounded loops

A task sent back more than `limits.max_attempts` times (by review or QA) stops, gets
`needs-human`, and is escalated to the stakeholder by the PM.

## 9. Language

- Every artifact is in **English**: analysis, questions, PRD, epics, stories, acceptance
  criteria, tasks, bugs, PRs, review comments, commits, release notes, reports.
- Conversation with the stakeholder uses the stakeholder's language. Vietnamese answers are
  recorded verbatim **and** with a meaning-preserving English translation.
- Vietnamese business terms without a clean English equivalent: English first, original in
  parentheses, e.g. `household registration book (sổ hộ khẩu)`.

## 10. Human gates

Exactly three; never skip or infer them:
1. **Requirement sign-off** (before any story is written)
2. **Story approval** (before any task breakdown)
3. **Production deploy approval** (GitHub Environment required reviewers)
