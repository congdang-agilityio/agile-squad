# squad

A software team for Claude Code. You talk to one PM, and the PM runs a team of subagents: BA,
Team Lead, Developers, Reviewer, QA, DevOps and Reporter. The team coordinates through a
GitHub Projects board. Every requirement, task, PR, bug and release lives on GitHub, so you
can follow the work there or just ask the PM.

```
You (stakeholder) ⇄ PM (main Claude Code session)
                      │ dispatches, never codes
     ┌──────────┬─────┴──────┬───────────┬──────────┬──────────┬──────────┐
     BA      Team Lead   Developers   Reviewer      QA       DevOps    Reporter
 requirements  tasks,     one task,   verdict by   verify    staging,   metrics
 → stories     waves,     own work-   comment      on main,  GATE 3,    report
               merges     tree, PR                 file bugs production
```

## What you get

- **Requirements to stories.** The BA asks questions until the requirement is clear. You sign
  it off (GATE 1), then approve small Given/When/Then stories (GATE 2).
- **Small tasks in parallel.** The Team Lead splits stories into XS/S/M tasks with expected
  files, dependencies and a Definition of Done. `waves.sh` computes waves, so independent
  tasks run in parallel. Each developer works in its own git worktree, port and test database.
- **Real review and QA.** Every PR is reviewed against the acceptance criteria, security and
  size limits. QA verifies every item on the latest `main` with the full suites and the
  running app, and files bugs as sub-issues.
- **Gated releases.** DevOps deploys a milestone to staging through GitHub Actions and smoke
  tests it. The production job then waits for your approval in the GitHub Environment
  (GATE 3).
- **Honest reports.** Every number in a report comes from `metrics.sh`, never from the model.
- **A quick lane for small changes.** `/squad:fix "<what>"` turns one small request into one
  task and runs it through dev, review, merge and QA, without the BA and story gates.
- **Cost control.** Small tasks run on cheaper models (config `models`), and each run stops
  at a token budget.

## Requirements

- Claude Code with plugin support.
- `gh` (GitHub CLI) logged in, with the `project` and `workflow` scopes:
  `gh auth refresh -h github.com -s project,workflow`.
- `git`, `jq`, `python3`, `bash`, `awk`.
- Optional, for requirement files: `pdftotext` (poppler) and `pandoc` or `markitdown`
  (`ingest.sh` has a built-in fallback for .docx/.pptx/.xlsx).
- The target project's own toolchain (for example Node and Docker for a local test database).
- For deploys: a hosting platform reachable from GitHub Actions. The template uses Railway with
  one project token per environment, stored as a GitHub Environment secret by you.

## Installation

**From a marketplace** (this repository ships `.claude-plugin/marketplace.json` at its root):

```
/plugin marketplace add <owner>/<this-repo>
/plugin install squad@cff-skills
```

**From a folder** (for trying it out or developing it):

```bash
claude --plugin-dir /path/to/cff-skills/squad
```

You can also copy the `squad/` folder into a plugin directory you already load. Skills appear
as `/squad:<name>` and agents as `squad:<name>`.

## First run in a repository

Open Claude Code in a clone of the target repository (it needs a GitHub remote) and run:

```
/squad:setup
```

Setup does the following:
- creates or reuses the GitHub Projects board, with the Status columns
  `Backlog → Todo → In Progress → In Review → QA → Done → Released` and the Priority, Size,
  Wave, Agent and Attempts fields;
- creates the labels and writes `.squad/config.yml`;
- turns on squash merges and branch protection on `main` (nobody pushes to `main`, admins
  included);
- adds the deploy workflow and creates the `staging` and `production` GitHub Environments,
  with you as the required reviewer of production.

Fill in the `commands` section (install, test, lint, e2e, services) in the config. In an empty
repository, also set `stack`, or let the Team Lead propose one for you to decide.

Claude Code's auto mode blocks `gh pr merge`. Setup offers the allow rule
`Bash(gh pr merge:*)`, so the Team Lead can merge PRs that passed review.

Setup ends with `/squad:doctor`. Run it again any time something looks wrong (after a fresh
clone, a lost config, a changed token): it checks everything below and proposes the fixes.

## Day-to-day workflow

| You want to | Say or run |
|---|---|
| Start a feature or product | Describe it, or attach files and links, then `/squad:ba` |
| Fix or tweak something small | `/squad:fix "<what to change>"` (one XS/S task, no story) |
| Answer the BA's questions | Answer in chat; the PM relays them and records the answers |
| Approve requirements / stories | Reply to GATE 1 / GATE 2 in chat |
| Let the team work | `/squad:run scope=#<epic or stories> [max-steps=N] [max-tokens=N]` |
| Release finished stories | Give the PM a milestone title when it asks (`v0.3.0 login`) |
| Approve production | Approve the waiting `production` job on GitHub (GATE 3) |
| Know where things are | `/squad:report` or ask "how is it going?" |
| Check the setup | `/squad:doctor` |

`/squad:run` is the PM loop. Each step it reads the board with `next.sh` and dispatches one
action per lane in one message: deploy, QA, PR review or merge, rebase, planning, plus
developers up to the free slots. It reads each result and repeats. It stops when:
- it needs you (a requirements question, GATE 1 or GATE 2);
- only GATE 3 is left (while GATE 3 is pending, the other lanes keep working);
- it reaches `max-steps` or the token budget;
- nothing is left to do (it then runs the report).

Run it again to continue; the board is the state, nothing lives in the session.

Individual skills can also be called directly, for example `/squad:dev 42`,
`/squad:review 57`, `/squad:qa 42` or `/squad:deploy "v0.3.0 login"`. Each one dispatches its
subagent instead of doing the work in the main session.

### Gates

| Gate | When | How you answer |
|---|---|---|
| GATE 1 | Requirements are clear | Sign-off in chat (recorded in `docs/requirements/<slug>/`) |
| GATE 2 | Stories are drafted | Approve or comment in chat; then the epic and stories are created |
| GATE 3 | Staging passed smoke tests | Approve or reject the `production` job on GitHub |

The team never approves a gate for you, and it never treats silence as approval.

## Configuration (`.squad/config.yml`)

| Key | Meaning |
|---|---|
| `commands.*` | install, test, lint, e2e and an idempotent `services` command (e.g. start a test Postgres) |
| `parallel.max_parallel_dev` | developer slots (worktrees), default 2 |
| `parallel.max_open_prs` | no new developers while this many PRs wait for review |
| `parallel.max_agents` | subagents dispatched at once by the run loop (memory), default 3 |
| `parallel.port_base`, `test_db_prefix`, `database_url_template` | per-slot port and test database |
| `merge.require_ci` | merge only with green CI |
| `models.<role>` | model per dispatch (`sonnet`, `opus`, `haiku`) for dev, review, qa (by task size `XS`/`S`/`M`, QA also `story`), rebase, merge, deploy |
| `budget.max_tokens_per_run` | `/squad:run` stops dispatching once its subagents reported this many tokens (approximate; default 2,000,000) |
| `deploy.*` | workflow names, staging and production URLs, production environment |
| `limits.*` | attempts before `needs-human`, story size, PR line/file limits per task size, files excluded from the size check |

The `ids` block is written by setup; do not edit it by hand. If it is incomplete, run
`board.sh bootstrap --project <n>` again.

## Troubleshooting

Start with `/squad:doctor`: it detects most of these and prints the fix.

| Symptom | Cause and fix |
|---|---|
| `config value .ids.… is missing` | The config lost its board ids. Run `"$PLUGIN/scripts/board.sh" bootstrap --project <n>`; it reuses the board |
| `gh: … requires the project scope` | `gh auth refresh -h github.com -s project,workflow` |
| Tasks jump to Done right after merge, skipping QA | A built-in project workflow ("Item closed") sets Status. Run `board.sh workflows --fix` (deletes it) |
| `gh pr merge` is blocked in auto mode | Add the allow rule `Bash(gh pr merge:*)` (setup offers it) |
| A PR is labeled `needs-split` | It is bigger than its task size. The Team Lead re-sizes or splits it. Add generated files (lock files, migration locks) to `limits.pr_size_exclude` |
| An item is labeled `needs-human` | It failed `limits.max_attempts` times. Read its last comment, decide, then remove the label |
| An item is labeled `blocked` | It waits for your answer. The PM removes the label after recording your answer |
| Done stories never deploy | They are in no milestone. Give the PM a milestone title (`next.sh` lists them as `unreleased`) |
| Staging smoke test fails | DevOps files a P0 bug with logs and the rollback path; production is not touched |
| A subagent cannot write `report.md` | Claude Code refuses subagent writes to files named `report*`, `summary*`, `findings*` or `analysis*`; squad names reports by date |
| Two developers never run at once | Their tasks depend on each other or are serial (migrations, shared routing, config). That is intended. `rewave` reuses idle slots when waves are stale |

Scripts can be run by hand from the repository root for diagnosis. Each one prints its usage
with `--help`: `next.sh` (what the PM would do now), `board.sh list <status>`,
`waves.sh`, `pr-size.sh <pr>`, `release.sh gate "<milestone>"`, `metrics.sh --since <date>`
and `doctor.sh`.

## Layout

```
squad/
├── .claude-plugin/plugin.json
├── skills/      setup, doctor, ba, fix, plan, dev, review, qa, deploy, report, run (procedures)
├── agents/      ba-analyst, team-lead, developer, reviewer, qa-tester, devops, reporter
├── references/  board conventions, result-block contract, templates, review checklist
├── scripts/     board, issue, worktree, waves, pr, pr-size, release, metrics, next, ingest, doctor
└── templates/   squad.config.yml, deploy.yml (GitHub Actions → Railway)
```

Design decisions that differ from the original plan are in `docs/decisions.md` of the source
repository.

## Limits (v1)

- GitHub Projects only. Trello and Jira are not supported yet; the scripts are the adapter
  layer.
- One reviewer and one QA at a time.
- No automatic production rollback. The P0 bug names the previous tag to redeploy.
- The token budget counts what subagents report; it is a guard, not a bill. For a hard dollar
  cap on unattended runs use `claude -p --max-budget-usd <n> "/squad:run …"`.
- DevOps has no access to the hosting platform: databases, platform settings and logs are
  set up or fetched by you.
- One GitHub account for all roles. Reviews are verdict comments (GitHub does not let an
  account approve its own PR), and the Team Lead merges.
