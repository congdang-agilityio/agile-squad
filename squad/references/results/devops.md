# Result statuses: `devops`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `gate_not_met` | Deploy entry gate failed | `none` | `milestone`, `reasons` |
| `staging_ok_awaiting_approval` | Staging deployed and smoke-tested, production job waiting for GATE 3 | `gate_3` | `milestone`, `run_id`, `run_url`, `release_notes` (draft release URL) |
| `released` | Production done, tag + release created, items `Released` | `report` | `milestone`, `tag`, `release_url` |
| `smoke_failed` | Smoke test failed, P0 bug created, release stopped | `plan` | `milestone`, `environment`, `bug`, `rollback` |
| `failed` | Workflow error not caused by the app, or production rejected/cancelled | `ask_stakeholder` | `run_url`, `milestone` |
