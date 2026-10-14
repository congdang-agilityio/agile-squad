# Result statuses: `devops`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `gate_not_met` | Deploy entry gate failed | `none` | `milestone`, `reasons` |
| `staging_ok_awaiting_approval` | Staging deployed and smoke-tested, release-gate run waiting for GATE 3 | `gate_3` | `milestone`, `run_id`, `run_url`, `release_notes` (draft release URL) |
| `released` | Production deployed and smoke-tested, release published, items `Released` | `report` | `milestone`, `tag`, `release_url` |
| `smoke_failed` | Deploy or smoke test failed, P0 bug created with the logs, release stopped | `plan` | `milestone`, `environment`, `bug` |
| `rollback_proposed` | Production failed; the last good deployment is named; rollback needs the stakeholder's yes | `ask_stakeholder` | `milestone`, `bug`, `deployment` |
| `rolled_back` | Production rolled back after approval and verified | `plan` | `bug`, `deployment` |
| `infra_done` | Infra task applied (staging, and production when approved), verified, task in `QA` | `qa` | `issue`, `environments` |
| `needs_approval` | Infra task needs a production change; the exact plan is on the task | `ask_stakeholder` | `issue`, `plan` |
| `health_ok` | Mode `health`: no error lines, no 5xx, latest deployment healthy | `none` | `environment`, `since`, `app_errors`, `http_5xx` |
| `bugs_filed` | Mode `health`: problems found in the logs, bugs filed or updated | `plan` | `environment`, `bugs`, `app_errors`, `http_5xx` |
| `blocked` | Not logged in to Railway, or a secret only the stakeholder may set | `ask_stakeholder` | `issue`, `notes` with the command for the stakeholder |
| `failed` | Platform or workflow error not caused by the app, or production rejected/cancelled | `ask_stakeholder` | `run_url`, `milestone` |
