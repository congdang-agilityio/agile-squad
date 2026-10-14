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

One file per role in `references/results/`: `ba.md`, `team-lead.md`, `dev.md`,
`review.md`, `qa.md`, `devops.md`, `reporter.md`. A subagent reads only its own.
