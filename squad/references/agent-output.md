# Agent output contract

Every squad subagent ends its final message with **exactly one** fenced `json` result block.
The PM (main session) decides the next step from this block alone, so it must be accurate,
machine-readable, and the last thing in the message.

````
```json
{"role":"dev","issue":42,"status":"pr_opened","pr":57,"next":"review","notes":"..."}
```
````

## Common fields

| Field | Required | Meaning |
|---|---|---|
| `role` | yes | `ba`, `team-lead`, `dev`, `review`, `qa`, `devops`, `reporter` |
| `status` | yes | One value from the role's list below. Nothing else is allowed |
| `next` | yes | Suggested next action for the PM (see per-role table), or `none` |
| `notes` | yes | One or two English sentences: what happened and anything the PM must know |
| `issue` / `pr` | when relevant | Issue / PR number the result is about |

Rules:
- Do not invent statuses. If nothing fits, use the role's failure status (`blocked`, `failed`)
  and explain in `notes`.
- Numbers are integers, not strings. Unknown values are `null`, never guessed.
- Everything the PM needs to verify must also be visible on the board, issue or PR. The
  result block is a summary, not the record.

## Per-role statuses

### `ba` (ba-analyst)

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `questions_ready` | Analysis written, questions waiting for the stakeholder | `ask_stakeholder` | `slug`, `open` (count), `batch` (list of Q-IDs to ask now) |
| `needs_source` | A source cannot be read (login, scan, broken link) | `ask_stakeholder` | `slug`, `missing` (list of what is needed) |
| `clear` | No `open` or `answered` questions remain | `gate_1` | `slug`, `understanding_file` |
| `stories_ready` | PRD and stories drafted | `gate_2` | `slug`, `stories` (count), `prd_file`, `stories_file` |
| `blocked` | Cannot continue | `ask_stakeholder` | — |

### `team-lead`

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `planned` | Tasks created, waves written to the board, dispatch plan posted on the epic | `dispatch` | `waves` (list of lists of issue numbers), `serial`, `risks`, `tasks` (list of `{issue, story, size}`), `plan_comment` (URL) |
| `merged` | Mode `merge`: final check passed, squash-merged, task moved to `QA` | `qa` | `pr`, `issue`, `rebase_needed` (list of PRs labeled) |
| `merge_rejected` | Mode `merge`: final check failed, `review:passed` removed | `review` or `rework` | `pr`, `issue`, `reasons` |
| `needs_rebase` | Mode `merge`: PR conflicts with `main`, labeled `needs-rebase` | `rebase` | `pr`, `issue` |
| `story_too_big` | A story needs more than `story_max_tasks` tasks | `ba_split` | `story`, `suggested_split` |
| `blocked` | Cannot plan (no `stack` for a new repo, unclear or conflicting AC) | `ask_stakeholder` | `proposal` (e.g. proposed stack) when relevant |

### `dev` (developer)

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `pr_opened` | PR open, task in `In Review` | `review` | `issue`, `pr`, `slot`, `size` (`{lines, files}`) |
| `rebased` | Rebase done, `needs-rebase` removed | `review` | `issue`, `pr` |
| `needs_split` | Task too big; split proposed, labeled `needs-split` | `plan` | `issue`, `pr` (partial PR or `null`) |
| `blocked` | Cannot proceed (dependency, unclear AC, environment) | `ask_stakeholder` or `plan` | `issue` |

### `review` (reviewer)

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `review_passed` | Verdict PASS posted as a review comment, labeled `review:passed` | `lead_merge` | `pr`, `issue`, `head_sha`, `findings` (`{nit}` count) |
| `changes_requested` | Blockers or should-fix found, task back to `Todo` | `rework` | `pr`, `issue`, `attempts`, `findings` (`{blocker, should_fix, nit}` counts) |
| `needs_split` | PR too large or multi-purpose | `plan` | `pr`, `issue` |
| `needs_rebase` | PR conflicts with `main` | `rebase` | `pr`, `issue` |
| `needs_human` | Attempts exceeded `max_attempts` | `escalate` | `pr`, `issue`, `attempts` |

### `qa` (qa-tester)

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `passed` | Every AC verified, item moved to `Done` | `none` or `deploy` | `issue`, `ready_to_deploy` (bool), `milestone` |
| `bug_created` | Bug filed as sub-issue, task labeled `qa:failed` | `plan` | `issue`, `bugs` (list), `attempts` |
| `needs_human` | Attempts exceeded `max_attempts` | `escalate` | `issue`, `attempts` |

### `devops`

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `gate_not_met` | Deploy entry gate failed | `none` | `milestone`, `reasons` |
| `staging_ok_awaiting_approval` | Staging green, production job waiting for GATE 3 | `gate_3` | `milestone`, `run_url`, `release_notes_file` |
| `released` | Production done, tag + release created, items `Released` | `report` | `milestone`, `tag`, `release_url` |
| `smoke_failed` | Smoke test failed, P0 bug created, release stopped | `plan` | `milestone`, `bug`, `rollback` |
| `failed` | Workflow error not caused by the app | `ask_stakeholder` | `run_url` |

### `reporter`

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `report_ready` | Report written from `metrics.sh` output | `publish_report` | `file`, `period` |
| `failed` | Metrics could not be collected | `ask_stakeholder` | — |
