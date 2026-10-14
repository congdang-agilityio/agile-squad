# Result statuses: `review`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `review_passed` | Verdict PASS posted as a review comment, labeled `review:passed` | `lead_merge` | `pr`, `issue`, `head_sha`, `findings` (`{nit}` count) |
| `changes_requested` | Blockers or should-fix found, task back to `Todo` | `rework` | `pr`, `issue`, `attempts`, `findings` (`{blocker, should_fix, nit}` counts) |
| `needs_split` | PR too large or multi-purpose | `plan` | `pr`, `issue` |
| `needs_rebase` | PR conflicts with `main` | `rebase` | `pr`, `issue` |
| `needs_human` | Attempts exceeded `max_attempts` | `escalate` | `pr`, `issue`, `attempts` |
