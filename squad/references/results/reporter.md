# Result statuses: `reporter`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `report_ready` | Report written from `metrics.sh` output | `publish_report` | `file`, `period` |
| `failed` | Metrics could not be collected | `ask_stakeholder` | — |
