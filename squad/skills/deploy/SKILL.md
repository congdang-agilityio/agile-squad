---
name: deploy
description: "DevOps procedure, with the Railway CLI under the stakeholder's own login (no tokens): release a milestone (deploy gate, release notes, deploy and smoke-test staging, request GATE 3 on GitHub; after approval deploy production, publish, mark items Released); change the platform for an infra task (databases, variables, service settings) with approval for production; read logs and deployments; roll back production after approval. On a failed deploy or smoke test, file a P0 bug with the logs. Use when a milestone is ready to deploy, after GATE 3, for infra tasks, or when production must be rolled back."
---

# squad: deploy (Railway via railway.sh)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

The PM dispatches a fresh `devops` subagent with one mode:
- `mode=release milestone=<title>`: gate, notes, staging, smoke, request GATE 3;
- `mode=finish run=<run id> milestone=<title>`: after the stakeholder decided GATE 3;
- `mode=infra issue=<n> [approved="<stakeholder words>"]`: a task labeled `infra`;
- `mode=rollback deployment=<id> approved="<stakeholder words>" issue=<n>`;
- `mode=health env=production [since=24h]`: scan the logs for errors and file bugs.
All with `config=.squad/config.yml`. When invoked directly (`/squad:deploy <milestone>`, or
`/squad:deploy health [staging|production]`), dispatch the `devops` subagent instead.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`railway.sh`, `release.sh`, `board.sh`,
`issue.sh`), literal arguments, one command per call (no pipes, loops or multi-line quoted
text). **Railway only through `railway.sh`**, which uses the stakeholder's `railway login`:
never the `railway` CLI directly, never print, read or set secrets. If it exits 5 (not logged
in), return `blocked` with "the stakeholder runs `! railway login`". **Production changes**
(deploy, variables, settings, databases, redeploy, rollback) need the stakeholder's approval:
GATE 3 (`--gate-run`) for a release, the quoted words (`--approved … --issue …`) otherwise;
`railway.sh` refuses without them and records every change on the issue.

## Mode release
1. **Gate.** `release.sh gate "<milestone>"`. Not `ok` → return `gate_not_met` with `reasons`.
2. **Draft notes.** `release.sh draft "<milestone>" <sha>` (sha = `ci_main.headSha`).
3. **Staging.** `railway.sh deploy staging <sha>`. Exit 4 → **Deploy failed** (below).
4. **Smoke staging.** Health paths and the milestone's acceptance criteria on the staging URL
   with `curl` (happy path and one error case per endpoint or page; real paths from the code
   or the stories). Record `URL | expected | actual`. Then `railway.sh errors staging
   --since 15m`: any `app_errors` or `http_5xx` during the smoke test is a failure too. On a
   failure read `railway.sh logs staging --lines 200` first. Any failure → **Deploy failed**.
5. **GATE 3.** `release.sh approval <sha> <tag>` starts the release-gate workflow; its
   `production` job waits for the stakeholder on GitHub. Comment on the epic (quick tasks: on
   each task): staging URL, commit, smoke table, run URL, anything to check first. Return
   `staging_ok_awaiting_approval` with `run_id`, `run_url`, `release_notes`, `milestone`.
   You never approve it.

## Mode finish
1. `release.sh wait <run> production`. `run_status` `waiting` → return
   `staging_ok_awaiting_approval` again. Rejected or cancelled → comment it on the epic,
   delete the draft (`gh release delete <tag> --yes`), return `failed` with the reason.
2. Approved: `railway.sh deploy production <sha> --gate-run <run> --issue <epic>` (it checks
   on GitHub that this run approved this commit). Exit 4 → **Deploy failed**, production.
3. Smoke production as in release step 4, including `railway.sh errors production --since 15m`.
   Failure → **Deploy failed**, production.
4. `release.sh publish "<milestone>" [--note "<accepted limitation>"]...`, then
   `release.sh finish "<milestone>"`. Return `released` with `tag` and `release_url`.

## Mode infra
For a task labeled `infra` (databases, variables, service settings, domains).
1. `board.sh move <n> "In Progress"`, `board.sh set-field <n> agent devops`. Read the task
   (Goal, DoD) and the current state: `railway.sh status <env>`, `railway.sh vars <env>`.
2. **Staging first:** `railway.sh add-db | set-var | config | domain | redeploy staging … --issue <n>`
   (`config` takes a setting name: `preDeployCommand`, `startCommand`, `healthcheckPath`, …).
   Variables that hold secrets (passwords, tokens, API keys, credential URLs) are refused:
   for those, comment on the task the exact command for the stakeholder
   (`! railway variable set KEY --stdin …`), label it `blocked` and return `blocked`.
   A database URL is wired as a reference, e.g. `DATABASE_URL=${{Postgres.DATABASE_URL}}`.
3. Verify on staging (status, logs, the app's health path).
4. **Production** (when the task needs it): without `approved=`, comment the exact plan
   (commands, environment) on the task and return `needs_approval` with `plan`. With it, run
   the same commands with `--approved "<words>" --issue <n>` and verify.
5. Comment what changed and how it was verified, `board.sh move <n> QA`, return `infra_done`.

## Mode rollback
`railway.sh deployments production` (find the last good deployment, `can_rollback`), then
`railway.sh rollback production <deployment> --approved "<words>" --issue <bug>`, verify
with status and the health path, comment on the bug, return `rolled_back`.

## Mode health
1. `railway.sh errors <env> --since <since, default 24h>`, and `railway.sh status <env>`
   (a crashed or failed latest deployment counts as an error).
2. Nothing found → return `health_ok` with the numbers.
3. For each distinct problem (one entry of `top_errors` or `top_paths`, or a crash): read
   the surrounding lines (`railway.sh logs <env> --since <since> --filter "<a few words of it>"`),
   then look for an open bug about it (`gh issue list --label type:bug --state open --search "<words>"`):
   - found → comment the new count and period on it;
   - not found → `issue.sh create bug "<env>: <short symptom>" - --priority <P>` with
     `references/bug-template.md` (log lines without secrets, count, first and last time,
     affected request). Priority: P0 when a main flow is down or most requests fail, P1 for
     repeated 5xx or unhandled exceptions, P2 for occasional errors.
4. Return `bugs_filed` with `bugs` (new and updated) and the numbers. The PM tells the
   stakeholder; the Team Lead plans the bugs like any other.

## Deploy failed
1. Stop: start nothing else on that environment.
2. Logs: `railway.sh logs <env> --build --lines 200` (build) or `railway.sh logs <env> --lines 200`
   (runtime, migrations), and `railway.sh status <env>`.
3. File a P0 bug: `issue.sh create bug "<environment> deploy failed: <symptom>" - --priority P0 --milestone "<milestone>"`
   with `references/bug-template.md`: what failed, expected vs actual, the relevant log lines
   (no secrets), and the cause if the logs show it (missing variable, migration error).
   If the cause is the platform (a missing database or setting), say which infra change fixes it.
4. Production only: name the last good deployment (`railway.sh deployments production`) and
   return `rollback_proposed` with `deployment` and `bug`; the PM asks the stakeholder.
5. Delete the draft release (`gh release delete <tag> --yes`), comment the bug on the epic,
   return `smoke_failed` with `bug`, `environment`, `milestone` (or `rollback_proposed`).

## Never
- Use the `railway` CLI directly, `railway up` outside `railway.sh deploy`, or delete
  projects, environments or services.
- Change production without GATE 3 or the stakeholder's quoted approval.
- Read, print or set secrets; put tokens in commands, files or comments.
- Approve the production gate, release with the gate not met, or move items to `Released`
  before production succeeded.
- Edit code (a code problem becomes a bug for the team).

End with the result block from `references/agent-output.md` and `references/results/devops.md`.
