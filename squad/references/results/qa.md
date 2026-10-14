# Result statuses: `qa`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `passed` | Every criterion verified on main, item moved to `Done` | `none`, `qa` (re-check the parent task) or `deploy` | `issue`, `story_done` (bool), `recheck` (parent task or `null`), `ready_to_deploy` (bool), `milestone` |
| `bug_created` | Bug(s) filed as sub-issues in `Todo`, item labeled `qa:failed`, stays in `QA` | `plan` | `issue`, `bugs` (list), `attempts` |
| `needs_human` | Attempts exceeded `max_attempts`; labeled `needs-human` | `escalate` | `issue`, `attempts`, `bugs` |
| `blocked` | Cannot test (environment, missing information) | `ask_stakeholder` | `issue` |
| `claimed_elsewhere` | Another worker (possibly on another machine) claimed this item first; nothing changed | `none` | `issue`, `by` |
