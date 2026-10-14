# Phase 12: DevOps on Railway through the CLI — test log

Date: 2026-10-15 · Plugin version 0.4.0

| Check | Result |
|---|---|
| `tests/railway.test.sh` (fake Railway CLI and gh) | 29 tests: check/status output; `vars` prints names only, the secret value never appears; plain variable set on the right project, environment and service; secret-looking names and credential URLs refused (exit 3); reference variables allowed; production change refused without approval, allowed with `--approved` + `--issue` and recorded on the issue; `config` refuses `variables.*`; `add-db` links a throwaway directory, not the repo; `deploy staging` runs from a clean worktree at the commit and waits for SUCCESS; production deploy refused without GATE 3 and with a gate run for another commit, accepted with the approved run; rollback needs approval; not logged in → exit 5 |
| `tests/guard.test.sh` | +6: subagents cannot call the `railway` CLI (also via npx); QA may read through `railway.sh`, not change; DevOps may change through it; the main session is unrestricted |
| Whole suite | 101 tests pass; shellcheck `-S warning` clean |
| Live Railway (temporary project `squad-railway-livetest`, deleted afterwards) | see below |

## Live test on Railway (2026-10-15, Railway CLI 5.63.1, stakeholder's OAuth login)

| Step | Result |
|---|---|
| `check`, `status staging` | user, project, staging + production with `web` |
| `add-db staging postgres` | Postgres service created in staging |
| `set-var staging DATABASE_URL=${{Postgres.DATABASE_URL}}`, `APP_VERSION_LABEL=v1` | set; app later reported `db: true` |
| `set-var staging SMTP_PASSWORD=…` | refused (exit 3) with the command for the stakeholder |
| `config staging preDeployCommand "node migrate.js"`, `startCommand` | **bug found**: the CLI's `environment edit --service-config` answered "No changes to apply"; switched to the `serviceInstanceUpdate` API; deploy logs then showed "migrations applied" |
| `vars staging` | names only |
| `deploy staging <sha>` | **bug found**: `railway up --ci` never returned (it follows the app's logs; killed after 9 min while the deployment had succeeded); switched to `--detach` + polling by deployment id: SUCCESS in 3 min 37 s |
| `domain staging` | generated `web-staging-….up.railway.app`; second call returns it without creating |
| Smoke + `errors staging --since 10m` after two calls to `/boom` | `app_errors: 2` grouped as one message, `http_5xx: 2` grouped as `GET /boom 500`; field names match real Railway JSON logs |
| Production without approval (`deploy`, `set-var`, `rollback`) | refused (exit 3) |
| `deploy production` v1 and v2 with approval | SUCCESS each; app answered `v2` |
| `deployments production` | **fixed**: commit shown from the upload message (`cliMessage`) |
| `rollback production <v1 deployment>` with approval | app answered `v1` again |
| Audit | 4 production changes commented on the issue (gh stubbed in this test) |
| `redeploy staging`, `logs staging`, `logs --build` | ok |

