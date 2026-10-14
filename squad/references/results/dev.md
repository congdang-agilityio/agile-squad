# Result statuses: `dev`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `pr_opened` | PR open, task in `In Review` | `review` | `issue`, `pr`, `slot`, `size` (`{lines, files}`) |
| `rebased` | Rebase done, `needs-rebase` removed | `review` | `issue`, `pr` |
| `needs_split` | Task too big; split proposed, labeled `needs-split` | `plan` | `issue`, `pr` (partial PR or `null`) |
| `blocked` | Cannot proceed (dependency, unclear AC, environment) | `ask_stakeholder` or `plan` | `issue` |
