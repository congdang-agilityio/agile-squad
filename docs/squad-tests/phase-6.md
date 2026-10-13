# Phase 6: Deploy — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Railway project `squad-sandbox-todonow`
(service `web`; staging https://web-staging-4af2.up.railway.app, production https://web-production-8664f.up.railway.app)

## Built
- `templates/deploy.yml`: GitHub Actions workflow. Push to `main` → `staging` job (GitHub
  Environment `staging`): `railway up --ci` with the environment's `RAILWAY_TOKEN`
  (`@railway/cli@5.63.1`), then a smoke test of `SMOKE_PATHS` (default `/api/health`) with
  retries. `workflow_dispatch` with `ref` and `production=true` adds the `production` job in
  GitHub Environment `production` (required reviewers = GATE 3), deploying the exact commit
  that passed staging, with the same smoke test.
- `scripts/release.sh gate|notes|finish <milestone>`: entry gate (every milestone item `Done`,
  no open P0/P1 bug, latest CI on `main` green), release notes grouped by PR type, and after
  production: items → `Released`, milestone closed. Tag = first word of the milestone title.
- `skills/deploy/SKILL.md` (69 lines): mode `release` (gate → draft GitHub Release with notes
  → trigger → follow staging by polling, not `gh run watch` → smoke the milestone's ACs on
  staging → GATE 3 report → stop) and mode `finish` (follow production → smoke production →
  publish the release (tag) → `release.sh finish`); smoke failure → stop, P0 bug with logs and
  rollback path.
- `setup` step 8: copies the workflow, creates both GitHub Environments (production with the
  stakeholder as required reviewer), sets `APP_URL` per environment, asks the stakeholder to
  store the Railway tokens themselves. Config: `deploy.ci_workflow`, `deploy.production_url`.
- DevOps agent: no `railway` CLI, no secrets, never approves GATE 3.

## Setup done for the sandbox
- Railway (via the Railway MCP/CLI, account `code-for-food`): project, empty service `web`
  with healthcheck `/api/health`, environments `production` and `staging`, generated domains.
- GitHub: Environments `staging` and `production` (reviewer congdang-agilityio,
  `prevent_self_review: false` because one account does everything), variables `APP_URL` per
  environment, `RAILWAY_SERVICE`, `SMOKE_PATHS`.
- The stakeholder created the two Railway project tokens and stored them as environment
  secrets in their own terminal; no agent saw them.
- `.github/workflows/deploy.yml` reached the repo through the squad flow: task #128 →
  developer (PR #129) → reviewer PASS → Team Lead merge → QA.

## Acceptance
| Check | Result |
|---|---|
| Staging deploys on the sandbox automatically on push to `main` | PASS — run 38401466169 after merging #129; staging served health, ready, version |
| Release gate, notes and staging for milestone `v0.1.0 operator endpoints` (6 items) | PASS — gate ok, draft release with Features/Fixes/Chores, staging job + 11 AC smoke checks on staging |
| **Production waits for approval** | PASS — run 38402615675: `production` job waited in the `production` environment until the stakeholder approved on GitHub ("đã duyệt"; approval by congdang-agilityio) |
| After approval: production deploy + 8 smoke checks, tag `v0.1.0` on the tested commit, items → `Released`, milestone closed | PASS — https://github.com/congdang-agilityio/squad-sandbox/releases/tag/v0.1.0 |
| **Failing smoke test stops the release and creates a P0 bug** | PASS — milestone `v0.1.1 smoke drill`: a staging-only `SMOKE_PATHS` with a missing path made the staging smoke fail (404), production never started, P0 bug #131 with failed log lines and rollback path (`gh workflow run deploy.yml -f ref=v0.1.0 -f production=true` or Railway "redeploy previous deployment") |

Drill cleanup: staging `SMOKE_PATHS` removed, #130/#131 closed and archived, milestone
`v0.1.1 smoke drill` closed, draft release deleted.

## Findings fixed during testing
1. **The template `deploy.yml` was invalid YAML** (an unquoted `: ` in an input description).
   The developer refused to change the file against its DoD and asked; the template was fixed
   upstream and now passes YAML parsing and action-validator. Lesson: validate templates.
2. **`deploy.staging_url` in the sandbox config was still a placeholder.** DevOps refused to
   hand over to GATE 3 without its own AC smoke test and returned `failed`; after the PM set
   the URLs, a resumed run completed the smoke and the GATE 3 report.
3. Moving an item to `Done` closes the issue (GitHub's kept "Auto-close issue" workflow); this
   is intended.

## Notes
- Railway cost: one small Next.js service per environment, no database yet.
- Headless subagents cannot copy or diff files outside the repo (permission sandbox); the
  developer copied the template with Read/Write and the PM verified it with `cmp`.
