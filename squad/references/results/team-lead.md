# Result statuses: `team-lead`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `planned` | Tasks created, waves written to the board, dispatch plan posted on the epic | `dispatch` | `waves` (list of lists of issue numbers), `serial`, `risks`, `tasks` (list of `{issue, story, size}`), `plan_comment` (URL) |
| `merged` | Mode `merge`: final check passed, squash-merged, task moved to `QA` | `qa` | `pr`, `issue`, `rebase_needed` (list of PRs labeled) |
| `merge_rejected` | Mode `merge`: final check failed, `review:passed` removed | `review` or `rework` | `pr`, `issue`, `reasons` |
| `needs_rebase` | Mode `merge`: PR conflicts with `main`, labeled `needs-rebase` | `rebase` | `pr`, `issue` |
| `milestone_set` | Mode `milestone`: stories and their tasks/bugs put in the named milestone | `deploy` | `milestone`, `issues` |
| `quick_planned` | Mode `quick`: one task created in `Todo` with label `quick`, no parent | `dispatch` | `issue`, `size`, `title` |
| `too_big_for_fix` | Mode `quick`: the request is not one small task; nothing created | `ask_stakeholder` or `ba` | `reason`, `questions` |
| `story_too_big` | A story needs more than `story_max_tasks` tasks | `ba_split` | `story`, `suggested_split` |
| `blocked` | Cannot plan (no `stack` for a new repo, unclear or conflicting AC) | `ask_stakeholder` | `proposal` (e.g. proposed stack) when relevant |
