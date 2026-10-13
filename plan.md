# PLAN: Build the "devteam" skill set for Claude Code

> This document is written for Claude Code. Read it fully before starting, follow the Phases in section 8 in order, and stop to ask whenever something is unclear.
> `cff` is a working name; the final name is decided in Phase 0.

---

## 1. Goal

Build a **brand-new skill set, written from scratch**, that lets Claude Code act as a complete software team. All work is coordinated through a **GitHub Projects board**.

```
Stakeholder ⇄ PM (main session)
   PM → BA: idea + sources → analysis + clarifying questions
   PM relays questions verbatim ⇄ Stakeholder → answers recorded → BA   (loop until BA declares "clear")
   GATE 1: requirement sign-off → BA drafts stories → GATE 2: story approval → Backlog
Team Lead: reads Backlog → splits stories into tasks, dependencies, parallel waves → returns dispatch plan
PM dispatches: Dev 1 ‖ Dev 2 ‖ … (each in its own worktree) → Reviewer → QA ⇄ Dev → DevOps
   GATE 3: production deploy approval
PM: reports to Stakeholder
```

The stakeholder is the project owner (Cong). There are exactly **3 human gates**:
1. **Requirement sign-off**: every clarifying question is answered and the stakeholder explicitly confirms the requirements. No stories are written before this.
2. **Story approval**: the stakeholder approves the story list before any task breakdown.
3. **Production deploy approval**.

Everything else runs autonomously but must leave a trace on the board, issues and PRs.

## 2. Design principles (mandatory)

1. **The board is the single source of truth.** No work state is kept in local files. Every role decides what to do next by reading the board.
2. **Lightweight.** Each `SKILL.md` is ≤ 150 lines. Details go in `references/` and are loaded only when needed. Repetitive, precision-critical operations (gh CLI, GraphQL) live in `scripts/` instead of being retyped by the model.
3. **Each role = one skill (the procedure) + one subagent (the worker).** See 2.1.
4. **Nobody grades their own work.** Every role runs in its own subagent with a clean context. Reviewer and QA never edit code; they only give feedback and create tickets.
5. **Split as small as possible.** A story is the thinnest vertical slice that still delivers user value. A task is small enough to be coded in one go and reviewed in about 15 minutes. When in doubt, split again (see 3.6).
6. **Bounded loops.** A task returned more than `max_attempts` times (by review or QA) stops, gets the `needs-human` label, and is escalated to the stakeholder.
7. **Written from scratch.** Ideas may be borrowed from CCPM, Superpowers, BMAD and pr-review-toolkit, but **do not copy their files, prompts or folder structures**.
8. **Language (hard rule):**
   - **Every document and artifact is written in English**: requirement analysis, clarifying questions, PRD, epics, user stories, acceptance criteria, tasks, bug reports, PRs, review comments, commits, release notes, reports and the README.
   - **Conversation with the stakeholder** uses **whatever language the stakeholder is using** (Vietnamese or English). When the stakeholder answers in Vietnamese, record the original answer verbatim **and** an English translation that preserves the meaning.
   - Vietnamese business terms without a clean English equivalent are written in English with the original in parentheses, e.g. `household registration book (sổ hộ khẩu)`.

### 2.1 Agent architecture

**The main session is the PM.** It is the only role that talks to the stakeholder. It owns the human gates, relays questions, dispatches subagents according to plans, reads their results and reports progress.

> Why: a subagent cannot hold a back-and-forth conversation with the stakeholder; it receives one prompt and returns one result. Subagents also cannot spawn other subagents. Therefore all dialogue and all dispatching happen in the main session, and all execution happens in subagents.

| Role | Subagent (`agents/`) | Skill (procedure) | Allowed tools | Notes |
|---|---|---|---|---|
| PM | *(main session)* | `run`, `ba` (intake, relay, gates), `report` (presentation) | all | Only role that talks to the stakeholder. Dispatches strictly per the Team Lead's plan; makes no technical decisions |
| BA | `ba-analyst.md` | `ba` (analysis, questions, stories) | Read, Grep, Glob, WebFetch, Bash (`ingest.sh`), Write inside `docs/requirements/` | Never talks to the stakeholder, never creates issues, never splits technical tasks |
| Team Lead | `team-lead.md` | `plan` | Read, Grep, Glob, Bash (`board.sh`, `issue.sh`, `git`) | Reads code, never edits it. Splits stories into tasks, sets dependencies, builds the dispatch plan |
| Dev | `developer.md` | `dev` | Read, Write, Edit, Bash | **One task per invocation**, fresh context each time, its own worktree |
| Reviewer | `reviewer.md` | `review` | Read, Grep, Glob, Bash (`gh`, `pr-size.sh`) | No Write/Edit |
| QA | `qa-tester.md` | `qa` | Read, Grep, Glob, Bash (test runners, e2e, `gh`, `issue.sh`) | No Write/Edit on source code |
| DevOps | `devops.md` | `deploy` | Read, Bash (`gh workflow`, `gh run`, `gh release`, smoke-test `curl`) | Never edits code, never reads secrets |
| Reporter | `reporter.md` | `report` (data + draft) | Read, Bash (`metrics.sh`, `gh`), Write inside `docs/reports/` | PM presents the result |

**Skills vs. subagents**
- `SKILL.md` holds the detailed procedure (steps, gates, prohibitions). An `agents/*.md` file is a short worker definition: role, tool allowlist, optional `model`, and the instruction "read and follow `skills/<x>/SKILL.md`". Never duplicate skill content in agent files.
- When a user invokes a skill directly (e.g. `/devteam:dev 42`), the skill immediately dispatches to its subagent; it does not do the work in the main session.

**Communication between agents**
- Agents never call each other. Only the PM (main session) invokes subagents.
- Input to a subagent: a short prompt with the issue/PR number(s), the mode (e.g. `implement`, `rework`, `rebase`) and the config path. The subagent reads everything else from the board, issues and repo. The board is the handoff surface.
- Output: every subagent ends with a structured result block, defined in `references/agent-output.md`, e.g.
  ```json
  {"role":"dev","issue":42,"status":"pr_opened","pr":57,"next":"review","notes":"..."}
  ```
  Allowed `status` values are fixed per role, e.g. `pr_opened | needs_split | blocked` (dev), `approved_merged | changes_requested | needs_split | needs_rebase` (review), `passed | bug_created` (qa).
- A `model` may be set per subagent in its frontmatter (e.g. a stronger model for reviewer and QA, a lighter one for reporter).

### 2.2 Question relay rules (PM ⇄ BA ⇄ Stakeholder)

Relaying through the PM risks a "telephone game". To prevent it:
- The PM asks the stakeholder the questions from `questions.md` **verbatim**. It may translate them into the stakeholder's language but must not rephrase, merge, drop or answer them.
- The stakeholder's answer is written into `questions.md` **verbatim**, plus an English translation. The BA reads answers directly from the file, never from a PM summary.
- **Only the BA may mark a question `confirmed` or declare the requirements "clear".** The PM never concludes that requirements are complete on its own.
- If the stakeholder volunteers new information outside the questions, the PM records it verbatim in `docs/requirements/<slug>/sources/stakeholder-notes.md` for the BA to analyze.

## 3. Shared conventions

### 3.1 Status column

| Status | Meaning | Moved there by |
|---|---|---|
| `Backlog` | Approved story, not yet split into tasks | PM (after GATE 2) |
| `Todo` | Task ready to be picked up | Team Lead; QA (bugs); Reviewer (rework) |
| `In Progress` | A developer is working on it | Dev |
| `In Review` | PR open, awaiting review | Dev |
| `QA` | Merged, awaiting testing | Reviewer |
| `Done` | QA passed, ready to deploy | QA |
| `Released` | Live in production | DevOps |

### 3.2 Project custom fields

- `Priority`: P0, P1, P2, P3 (single select)
- `Size`: XS, S, M (single select, defined in 3.6). There is no L; anything bigger than M must be split.
- `Wave`: number. Set by the Team Lead; tasks in the same wave may run in parallel.
- `Agent`: text. Which developer slot is working on the task (e.g. `dev-1`), for visibility.
- `Attempts`: number. How many times the task has been sent back.
- Releases are grouped by repository **milestones**.

### 3.3 Labels

`type:epic`, `type:story`, `type:task`, `type:bug`, `type:report`, `qa:failed`, `review:changes`, `needs-split`, `needs-rebase`, `needs-human`, `blocked`

### 3.4 Issue relationships

- Epic → Story → Task, linked with GitHub **sub-issues** (GraphQL `addSubIssue`).
- A QA bug is a sub-issue of the original task (or story) and states `Found in #<PR>`.
- Task dependencies are written in the body: `Depends on #12, #15`. A task is ready only when all dependencies are `Done` or `Released`.
- Every task body has a `Files (expected)` section listing the files/modules it will touch. The Team Lead uses it for conflict detection.

### 3.5 Git

- Branches: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`
- Worktrees: `.worktrees/<issue>` (git-ignored)
- Conventional Commits
- PR title: `<type>: <summary> (#<issue>)`; body contains `Closes #<issue>` and the acceptance-criteria checklist
- **Squash** merge. `main` is protected and CI must be green.

### 3.6 Sizing rules

**Stories (BA)**
- Each story is a vertical slice: the user can see or use something, however small.
- At most **5 acceptance criteria**. More means split the story.
- A story that the Team Lead would need more than **5 tasks** for is too big and goes back to the BA.
- Preferred splitting patterns:
  - By workflow: happy path first; errors and edge cases as separate stories
  - By CRUD operation: create, read, update and delete are separate stories
  - By business rule: each complex rule is its own story
  - By user role: regular user and admin separately
  - By data type or channel: one input type or platform first, extend later
  - Simple version first, full version later (e.g. exact search before fuzzy search)

**Tasks (Team Lead)**

| Size | Description | PR limit (excluding tests, lockfiles and generated files) |
|---|---|---|
| `XS` | A tiny change: config, one function, one field | ≤ 50 changed lines, ≤ 3 files |
| `S` | One logical unit: an endpoint, a component, a migration | ≤ 150 lines, ≤ 6 files |
| `M` | Maximum allowed | ≤ 300 lines, ≤ 10 files |

- **Target XS and S.** M is allowed only when no sensible split exists, and the task must include a `Why not smaller` section.
- Each task does **one thing** in **one layer** (schema/migration, service, API, UI, job), unless splitting would leave dead or untestable code.
- Each task must be **independently mergeable**: CI green, no broken features. Unfinished work sits behind a feature flag or stays unwired.
- Each task has its own **Definition of Done**, verifiable by tests.
- Suggested ordering: data/schema → logic/service → API → UI → wiring/feature flag → e2e.

All limits are read from `limits` in the config so each project can tune them.

### 3.7 Parallel development rules (Team Lead)

- Tasks may share a wave **only if** they do not depend on each other **and** their `Files (expected)` lists do not overlap.
- Always **serialized** (never in the same wave as anything touching the same area): database migrations/schema changes, dependency changes (`package.json`, lockfiles), shared routing/config files, CI/build config.
- At most `max_parallel_dev` developers run at once (start with **2**; raise only when the conflict rate stays low).
- Each developer works in its own worktree with its own port and test database, derived from the slot number (`port_base + slot`, `<test_db_prefix>_<slot>`).
- A developer rebases on the latest `main` before opening a PR. When a merge makes another open PR conflict, the reviewer labels that PR `needs-rebase` and the PM dispatches a developer in `rebase` mode.
- Do not let development outpace review: if more than `max_open_prs` PRs are waiting in `In Review`, the PM dispatches no new developers until the queue drains.

## 4. Folder structure (packaged as a plugin)

```
devteam/
├── .claude-plugin/
│   └── plugin.json
├── README.md                     # Install and usage guide (English)
├── skills/
│   ├── setup/SKILL.md            # Initialize board, fields, labels, config
│   ├── ba/SKILL.md               # Requirement intake → clarification → stories
│   ├── plan/SKILL.md             # Team Lead: tasks, dependencies, dispatch plan
│   ├── dev/SKILL.md              # Implement one task, open a PR
│   ├── review/SKILL.md           # Code review, merge
│   ├── qa/SKILL.md               # Test, file bugs, loop
│   ├── deploy/SKILL.md           # DevOps
│   ├── report/SKILL.md           # Stakeholder report
│   └── run/SKILL.md              # PM orchestrator
├── agents/
│   ├── ba-analyst.md
│   ├── team-lead.md
│   ├── developer.md
│   ├── reviewer.md
│   ├── qa-tester.md
│   ├── devops.md
│   └── reporter.md
├── references/
│   ├── board-conventions.md      # Section 3, for all skills to reference
│   ├── agent-output.md           # Result block format and allowed statuses per role
│   ├── requirement-analysis-template.md
│   ├── questions-template.md
│   ├── prd-template.md
│   ├── story-template.md         # User story + Given/When/Then + traceability
│   ├── task-template.md          # Includes Files (expected), DoD, Why not smaller
│   ├── dispatch-plan-template.md
│   ├── bug-template.md
│   ├── review-checklist.md
│   └── report-template.md
├── scripts/
│   ├── ingest.sh                 # Convert requirement sources to markdown
│   ├── board.sh                  # Board operations (section 6)
│   ├── issue.sh                  # Issues, sub-issues, links
│   ├── worktree.sh               # Create/clean worktrees with slot port/DB
│   ├── pr-size.sh                # Measure PR size against limits
│   └── metrics.sh                # Report metrics
└── templates/
    ├── devteam.config.yml
    └── deploy.yml                # Sample GitHub Actions workflow
```

Each repository using the skill set has `.devteam/config.yml`:

```yaml
owner: <github-user-or-org>
repo: <repo>
project_number: <n>
ids:                     # filled in by setup; do not edit by hand
  project_id: ...
  status_field_id: ...
  status_options: { Backlog: ..., Todo: ..., ... }
  priority_field_id: ...
  size_field_id: ...
  wave_field_id: ...
  agent_field_id: ...
  attempts_field_id: ...
language:
  artifacts: en          # fixed: every document, issue and PR is in English
  chat: auto             # reply to the stakeholder in their language (vi/en)
commands:
  install: npm ci
  test: npm test
  lint: npm run lint
  e2e: npx playwright test        # leave empty if none
parallel:
  max_parallel_dev: 2
  max_open_prs: 4
  port_base: 4100
  test_db_prefix: app_test
deploy:
  staging_workflow: deploy.yml
  staging_url: https://staging.example.com
  production_environment: production    # GitHub Environment with required reviewers
limits:
  max_attempts: 3
  story_max_ac: 5
  story_max_tasks: 5
  pr_max_lines: { XS: 50, S: 150, M: 300 }
  pr_max_files: { XS: 3, S: 6, M: 10 }
  pr_size_exclude: ["**/*.test.*", "**/__tests__/**", "**/*.lock", "package-lock.json", "**/generated/**"]
```

## 5. Skill specifications

Every `SKILL.md` contains: frontmatter (`name`, a `description` that states clearly when to use it), which agent executes it, inputs, steps, outputs, completion criteria, and prohibitions.

### 5.1 `setup` (main session)
- **When:** first use of devteam in a repository.
- **Steps:**
  1. Check `gh auth status` for the `project` scope; if missing, instruct `gh auth refresh -s project`.
  2. Create a new Project or reuse an existing one. Create the Status, Priority, Size, Wave, Agent and Attempts fields with the options in section 3.
  3. Create the labels. Enable branch protection on `main` if permitted; otherwise print instructions.
  4. Collect all IDs (project, fields, options) into `.devteam/config.yml`.
  5. Add `.worktrees/` to `.gitignore`.
  6. Copy `templates/deploy.yml` into `.github/workflows/` if no deploy workflow exists, then ask the stakeholder about the deploy target.
  7. Add a short section to the repo's `CLAUDE.md` pointing to the config.
- **Done when:** `scripts/board.sh list Todo` runs without errors.

### 5.2 `ba` (PM in main session + `ba-analyst` subagent)

Three phases, **strictly in order**: Analyze → Clarify until sign-off → Write stories. No skipping.

**Accepted requirement sources** (can be combined):
- Files already in the current folder (e.g. `requirements/`, `docs/`). If the stakeholder does not specify which, the PM lists candidates and asks.
- Files the stakeholder provides: `.md`, `.txt`, `.pdf`, `.docx`, `.doc`, `.pptx`, `.xlsx`, images (wireframes, screenshots).
- Links: web pages, public Google Docs/Notion pages, GitHub issues or discussions.
- A description typed in the chat (the PM saves it verbatim as `sources/stakeholder-brief.md`).

**Phase A: Analyze** (`ba-analyst`, no questions asked, no stories written)
1. Convert every source to markdown with `scripts/ingest.sh`:
   - PDF → `pdftotext -layout`. If it is a scanned PDF without text, report it and read the pages as images.
   - docx/pptx/xlsx → `pandoc`, or `markitdown` if available.
   - URL → WebFetch. If the link needs a login or cannot be read, **stop and ask (via the PM) for an exported file**; never guess content.
   - Images → read directly and describe in text.
   - Save converted sources in `docs/requirements/<slug>/sources/` with origin and retrieval date for traceability.
2. Write `docs/requirements/<slug>/analysis.md` from `requirement-analysis-template.md`:
   - Business goal and problem statement
   - Actors/personas
   - Functional requirements numbered `FR-01`, `FR-02`… with source citations (file, page, section)
   - Non-functional requirements (performance, security, platform, i18n…)
   - Scope in / out
   - Business rules and data entities
   - **Gaps** (missing information), **Ambiguities** (multiple interpretations), **Conflicts** (sources contradict each other), **Assumptions** (provisional)
   - Risks and external dependencies (third-party APIs, data, legal)
3. Write `docs/requirements/<slug>/questions.md` from `questions-template.md`. Each question has: `ID` (Q-01…), the question, why it matters (impact if wrong), related FRs, suggested options A/B/C where possible, `Answer (original)`, `Answer (English)`, and `Status`: `open | answered | confirmed | deferred`. Order questions by impact: scope and architecture first.
4. Return the result block with the number of open questions and the next batch to ask (5–7 questions).

**Phase B: Clarify until sign-off** (PM ⇄ stakeholder, `ba-analyst` re-invoked per round)
5. The PM asks the batch following the relay rules in 2.2.
6. The PM records answers verbatim + English translation and sets them to `answered`.
7. The PM re-invokes `ba-analyst`, which reads the answers, marks each `confirmed` or raises follow-up questions, updates `analysis.md`, and writes a short "here is how I understand it" summary for the stakeholder to confirm (prevents silent misunderstandings).
8. Repeat until the BA reports **no `open` or `answered` questions remain** (everything `confirmed`, or `deferred` with stakeholder agreement and a reason).
9. **GATE 1: Requirement sign-off.** The PM presents the BA's final summary (scope, key FRs, remaining assumptions, deferred items) and asks explicitly: "Do you confirm these requirements are complete and correct?" (in the stakeholder's language). Only an explicit yes (e.g. "ok, go ahead") counts. Silence or vague answers do not. The PM writes `Signed-off: <date> by <stakeholder>` at the top of `analysis.md`.

**Phase C: Write stories** (`ba-analyst` drafts, PM gates and publishes)
10. `ba-analyst` writes `docs/requirements/<slug>/prd.md` from `prd-template.md`, referencing the confirmed FRs and Qs.
11. `ba-analyst` writes user stories **in English**: "As a <role>, I want <capability>, so that <benefit>". Each story has:
    - Acceptance criteria in **Given / When / Then**
    - Traceability: `Covers: FR-03, FR-04` · `Decisions: Q-02, Q-07`
    - INVEST, with emphasis on **Small**; follows the story rules in 3.6
    - A **FR → Story traceability table** proving every FR is covered by at least one story
    - A size self-check table (number of ACs per story); any story over the limit is split before presenting
12. **GATE 2: Story approval.** The PM presents the stories and applies feedback (re-invoking `ba-analyst` for changes).
13. After approval, the PM creates the Epic and Story issues (sub-issues, English content) with `scripts/issue.sh` and puts them in `Backlog`.

- **Prohibitions:** writing stories or creating issues before sign-off; answering on the stakeholder's behalf or turning assumptions into decisions without asking; choosing technology or designing technical solutions; splitting technical tasks; writing artifacts in Vietnamese.
- **Requirement changes mid-stream:** go back to Phase B for the changed part, update `analysis.md` with a changelog, and label affected stories/tasks `blocked` until signed off again.

### 5.3 `plan` (Team Lead, `team-lead` subagent)
- **Input:** stories in `Backlog`, tasks labeled `needs-split`, and open bugs from QA.
- **Steps:**
  1. Read the codebase to understand the current architecture.
  2. Split each story into technical tasks **in English**, following the task rules in 3.6. Each task states:
     - One-sentence goal and explicit out-of-scope
     - `Files (expected)` and estimated changed lines
     - Size, plus `Why not smaller` if M
     - Definition of Done and the tests to write
     - `Depends on`
  3. Size self-check: split any task over the limit or doing more than one thing. If a story needs more than `story_max_tasks` tasks, return it to the BA (via the PM) with a suggested split.
  4. Re-split `needs-split` tasks; include QA bugs in planning with their inherited priority.
  5. Set Priority and Size, attach the milestone, create the task issues as sub-issues, move them to `Todo`, and move the parent story out of `Backlog`.
  6. **Build the dispatch plan** following 3.7: group ready tasks into waves, write the `Wave` field on the board, and write `docs/plans/<date>-dispatch.md` from `dispatch-plan-template.md` (waves, slots, reasons for serialization, conflict risks).
  7. Return the result block containing the plan, e.g. `{"role":"team-lead","waves":[[41,42],[43],[44,45]],"serial":[43],"risks":["43 changes the users schema"]}`.
- **Prohibitions:** editing code; creating stories; changing acceptance criteria (request changes through the PM instead).

### 5.4 `dev` (`developer` subagent)
- **Input from the PM:** one issue number, a slot number and a mode: `implement`, `rework` (after review/QA feedback) or `rebase`.
- **Steps (`implement` / `rework`):**
  1. Move the task to `In Progress`, set `Agent` to the slot, comment "Started by dev-<slot>".
  2. Create or reuse the worktree with `scripts/worktree.sh <issue> <slot>` (own port and test DB).
  3. Read the task, parent story, acceptance criteria and all comments. In `rework` mode, read the review feedback or bug report carefully first.
  4. **TDD:** write a failing test for each acceptance criterion / DoD item, then implement until it passes.
  5. Run `lint` and `test` from the config; everything must be green.
  6. Check size with `scripts/pr-size.sh`. If over the limit: do not open a large PR. If a completed part is independently mergeable, open it as a first small PR; comment on the task proposing the split, label it `needs-split` and return `needs_split`.
  7. Rebase on the latest `main`, push, and open the PR following 3.5. The PR body includes the ticked acceptance-criteria checklist and manual test steps.
  8. Move the task to `In Review`.
- **Mode `rebase`:** rebase onto `main`, resolve conflicts without changing behavior, re-run tests, force-push with lease, remove `needs-rebase`.
- **Prohibitions:** merging its own PR; working outside the task scope (including "while I'm here" refactors; those need their own task); disabling or deleting tests to make them pass; combining multiple tasks in one PR; touching other worktrees.

### 5.5 `review` (`reviewer` subagent)
- **Input:** a PR in `In Review` (the PM sends one PR per invocation).
- **Steps:**
  1. Read the diff (`gh pr diff`), the issue and its acceptance criteria.
  2. Run `scripts/pr-size.sh`. Oversized or multi-purpose PRs → request changes with "PR too large, please split", label `needs-split`, skip the detailed review.
  3. Review against `review-checklist.md`: acceptance criteria met, logic and edge cases, security (input validation, secrets, injection), meaningful and sufficient tests, conventions, no scope creep.
  4. Report only evidence-based issues (file:line), classified as `blocker`, `should-fix` or `nit`.
  5. Any blocker or should-fix: `gh pr review --request-changes` with inline comments, label `review:changes`, increment `Attempts`, move the task to `Todo`.
  6. Clean and CI green: `gh pr review --approve`, squash merge, delete the branch, move the task to `QA`. Then check the other open PRs; label any that now conflict `needs-rebase`.
  7. If `Attempts > max_attempts`: label `needs-human` and stop.

### 5.6 `qa` (`qa-tester` subagent)
- **Input:** items in `QA`.
- **Steps:**
  1. Check out the latest `main`, install dependencies, run the full `test` and `e2e` suites.
  2. Verify every acceptance criterion of the task and its parent story. Prefer e2e or running the real app; if there is no e2e, state exactly how each criterion was checked.
  3. Run a quick regression on related features.
  4. **Pass:** comment a test report (what was tested, results) and move to `Done`.
  5. **Fail:** create a `type:bug` issue from `bug-template.md` (steps to reproduce, expected vs. actual, logs/screenshots) as a sub-issue of the original task, inheriting its priority, in `Todo`. Label the original task `qa:failed` and increment `Attempts`. The original task can only reach `Done` once all its bugs are `Done`.
  6. When every item in the milestone is `Done` with no open bugs, comment "Ready to deploy" on the milestone.
- **Prohibitions:** editing code; lowering acceptance criteria to make something pass.

### 5.7 `deploy` (`devops` subagent)
- **Entry gate (automatic):** every item in the milestone is `Done`, CI on `main` is green, no open P0/P1 bugs.
- **Steps:**
  1. Generate release notes from the milestone's PRs, grouped into features, fixes and chores.
  2. Trigger staging with `gh workflow run <staging_workflow>` and follow it with `gh run watch`.
  3. Smoke-test `staging_url`: health check plus the main flows from the acceptance criteria.
  4. **GATE 3: production.** Use a GitHub Environment with required reviewers. The subagent only triggers the production job; the stakeholder approves it on GitHub. Never bypass this gate.
  5. After production: create the tag and GitHub Release, move items to `Released`, close the milestone.
  6. If the smoke test fails: stop, create a P0 bug, and document the rollback path (redeploy the previous tag).
- **Prohibitions:** deploying from a local machine; reading or printing secrets.

### 5.8 `report` (`reporter` subagent + PM)
- **Input:** a period (default: last 7 days) or a milestone.
- **Steps:**
  1. `scripts/metrics.sh` collects: items per status, stories completed, PRs merged, average PR size, bugs opened/closed, first-time QA pass rate, average cycle time (In Progress → Done), parallelism achieved and rebase/conflict count, deployments, `needs-human` / `needs-split` / `blocked` items.
  2. `reporter` writes `docs/reports/YYYY-MM-DD.md` (English) from `report-template.md`:
     - **5-line executive summary** for a non-technical reader: progress vs. plan, what was delivered, risks, decisions needed from the stakeholder.
     - Details: metrics table, released features, notable bugs, plan for next period.
  3. The PM posts it as a `type:report` issue (readable on mobile) and gives the stakeholder a short summary in their language.
- **Every number comes from the script**; nothing is estimated.

### 5.9 `run` (PM orchestrator, main session)
- **When:** `/devteam:run`, on a schedule, or when the stakeholder says "continue".
- The PM only dispatches and decides based on result blocks; it never does a subagent's work itself and never overrides the Team Lead's plan.
- **Loop**, picking the highest-priority available action each step:
  1. Items labeled `needs-human` → notify the stakeholder, skip them.
  2. Requirements with `open` questions → ask the stakeholder (Phase B). Never break down on its own.
  3. Items in `QA` → `qa-tester`.
  4. PRs in `In Review` → `reviewer` (one PR per invocation).
  5. PRs labeled `needs-rebase` → `developer` in `rebase` mode.
  6. Stories in `Backlog`, tasks labeled `needs-split`, or new bugs without a wave → `team-lead`.
  7. Tasks in `Todo` with a `Wave` → dispatch `developer` subagents **in parallel** for the lowest unfinished wave, up to `max_parallel_dev`, respecting `max_open_prs`. Tasks returned to `Todo` for rework are dispatched in `rework` mode.
  8. Milestone meets the deploy gate → `devops`.
  9. Nothing left → `report`, then stop.
- `--max-steps N` (default 10) prevents endless runs. End with a short summary of what happened.

## 6. Scripts (bash + `gh` + `jq`)

`scripts/board.sh` (all functions read `.devteam/config.yml`):
- `list <status>`: JSON list of items with issue number, title, priority, size, wave, agent, attempts, labels
- `move <issue> <status>`: find the item id and call `gh project item-edit` with the matching option id
- `set-field <issue> <field> <value>`
- `ready-tasks`: tasks in `Todo` whose dependencies are all `Done`/`Released`
- `bump-attempts <issue>`

`scripts/issue.sh`:
- `create <type> <title> <body-file> [--parent N] [--priority P] [--size S]`: create the issue, label it, add it to the project, link the sub-issue
- `children <issue>`: list sub-issues and their status

`scripts/worktree.sh <issue> <slot>` / `worktree.sh clean <issue>`: create or remove `.worktrees/<issue>` on the right branch and write a `.env.local` with the slot's port and test database.

`scripts/pr-size.sh <branch|pr> [--size XS|S|M]`: count changed lines and files against `main`, excluding `pr_size_exclude`; exit non-zero if over the limit for the size.

`scripts/metrics.sh <since|milestone>`: JSON metrics for `report`.

`scripts/ingest.sh <file|url> <slug>`: detect the source type, convert it to markdown and save it to `docs/requirements/<slug>/sources/`. Check for and explain how to install missing tools (`poppler-utils`, `pandoc`). On failure, exit with a clear error code and never create an empty file.

Requirements for all scripts: `set -euo pipefail`, clear error messages, `--help`, idempotent re-runs.

## 7. Testing approach

All acceptance tests run on a dedicated **sandbox repository** with its own Project board. Never test against a real project. Each Phase ends with a short written test log in `docs/devteam-tests/phase-<n>.md` (inside the plugin repo) describing what was run and the outcome.

## 8. Phases

Each Phase must meet its acceptance criteria before moving on. Commit after each Phase.

**Phase 0: Preparation**
- Ask the stakeholder: the final name of the skill set, the sandbox repository, and the deploy target (Vercel, VPS, Docker, Cloudflare…).
- Create the folder skeleton, `plugin.json`, `references/board-conventions.md` and `references/agent-output.md`.
- Create all 7 files in `agents/` per 2.1: frontmatter `name`, `description`, `tools` (and optional `model`), with a short body pointing to the matching skill.

**Phase 1: Board foundation**
- Write `board.sh`, `issue.sh` and the `setup` skill.
- ✅ Acceptance: `setup` on the sandbox creates every column and field; a test issue created with the script moves through every status.

**Phase 2: PM + BA**
- Write `ingest.sh`, the `ba` skill, `ba-analyst` and the templates (analysis, questions, PRD, story).
- ✅ Acceptance:
  - `ingest.sh` reads one `.md`, one `.pdf`, one `.docx` and one public URL, and fails clearly on a login-protected link.
  - Given a requirement that is **deliberately incomplete and contradictory** (e.g. "a todo app with login", one place says "email only", another says "Google login"), the BA detects the conflict and raises questions; **no story is created** while any question is `open`.
  - The PM relays questions verbatim; the stakeholder answers in Vietnamese; `questions.md` holds both the original and the English translation; only the BA marks questions `confirmed`.
  - After sign-off: a PRD, 1 epic, ≥ 3 stories with Given/When/Then, and an FR → Story traceability table covering every FR, all in English, in `Backlog`.
  - Given a deliberately large request ("user management with CRUD, roles and CSV import"), the BA splits it into multiple stories, none exceeding 5 ACs.

**Phase 3: Team Lead**
- Write `worktree.sh`, the `plan` skill, `team-lead` and the task and dispatch-plan templates.
- ✅ Acceptance: stories become tasks with `Files (expected)`, dependencies and DoD; ≥ 80% are XS or S and every M has `Why not smaller`; the dispatch plan puts independent, non-overlapping tasks in the same wave and serializes a migration task; `Wave` is written on the board.

**Phase 4: Dev + Review (including parallel)**
- Write `pr-size.sh`, the `dev` and `review` skills, `developer`, `reviewer` and `review-checklist.md`.
- ✅ Acceptance:
  - Every task is handled by a fresh `developer` invocation; `reviewer` has no edit permission.
  - **Two developers run in parallel** on a 2-task wave in separate worktrees with separate ports/DBs; both open PRs; after the first merges, a deliberately conflicting second PR is labeled `needs-rebase`, rebased by a `developer` in `rebase` mode, and merged.
  - An oversized PR is caught by the developer before opening and by the reviewer if forced through (`needs-split`).
  - The reviewer catches a planted bug (e.g. missing input validation) and sends it back; after rework it is merged and moved to `QA`.

**Phase 5: QA loop**
- Write the `qa` skill, `qa-tester` and `bug-template.md`.
- ✅ Acceptance: a PR missing one acceptance criterion produces a child bug and the task does not reach `Done`; after the fix QA passes it; a task that fails 4 times stops with `needs-human`.

**Phase 6: Deploy**
- Write the `deploy` skill, `devops` and `templates/deploy.yml` (automatic staging, production behind environment approval).
- ✅ Acceptance: staging deploys on the sandbox; production waits for approval; a failing smoke test stops the release and creates a P0 bug.

**Phase 7: Report + Orchestrator**
- Write `metrics.sh`, the `report` skill, `reporter`, and the `run` skill.
- ✅ Acceptance: the transcript shows the main session only talking to the stakeholder and dispatching, with all execution inside subagents; `/devteam:run` takes an approved story all the way to staging using parallel developers and stops at the production gate; the report's numbers match the board.

**Phase 8: Polish**
- `README.md` (English): installation (`/plugin marketplace add` or copying the folder), day-to-day workflow, troubleshooting.
- Final review: every `SKILL.md` ≤ 150 lines, every `description` is specific enough for Claude to trigger the right skill, no hard-coded repository names, all agent tool lists match 2.1.

## 9. Out of scope (v1)

- Trello and Jira (keep scripts structured so an adapter can be added later)
- Automatic production rollback
- More than one reviewer or QA running in parallel
