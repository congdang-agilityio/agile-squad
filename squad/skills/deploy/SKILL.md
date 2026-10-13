---
name: deploy
description: "DevOps procedure for releasing a milestone: check the deploy gate (all items Done, CI on main green, no open P0/P1 bugs), draft release notes, deploy and smoke-test staging through the GitHub Actions deploy workflow, start the approval-gated production job (GATE 3, approved by the stakeholder on GitHub), then tag, publish the release and mark items Released; on a failed smoke test stop and file a P0 bug. Use when a milestone is ready to deploy or after the stakeholder approved production."
---

# squad: deploy (milestone → staging → GATE 3 → production)

The PM dispatches a fresh `devops` subagent:
- `mode=release milestone=<title> config=.squad/config.yml`: gate, notes, staging, then stop
  at GATE 3;
- `mode=finish run=<run id> milestone=<title> config=.squad/config.yml`: after the stakeholder
  approved (or rejected) production on GitHub.
When invoked directly (`/squad:deploy <milestone>`), dispatch the `devops` subagent instead.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`release.sh`, `board.sh`, `issue.sh`), literal
arguments. Workflow: `deploy.staging_workflow` (default `deploy.yml`, from
`templates/deploy.yml`). Everything runs on GitHub Actions: **never deploy from this machine**
(no `railway up` here), never read, print or set secrets.

## Mode release
1. **Gate.** `release.sh gate "<milestone>"`. Not `ok` → return `gate_not_met` with the
   `reasons`. Nothing else.
2. **Notes.** `release.sh notes "<milestone>"`; save them as a **draft** GitHub Release on the
   tested commit: `gh release create <tag> --draft --target <main sha> --title "<tag>" --notes-file -`
   (main sha = `ci_main.headSha` from the gate). Re-running reuses the draft
   (`gh release edit`).
3. **Staging + production request.** `gh workflow run <workflow> -f ref=<main sha> -f production=true`,
   then find the run: `gh run list --workflow <workflow> --event workflow_dispatch --limit 1 --json databaseId,headSha,url`.
4. **Follow staging.** Poll `gh run view <id> --json status,conclusion,jobs` every 30 s until the
   `staging` job has finished (never `gh run watch` here: it would block on the approval).
   - `staging` failed → **Smoke failed** (below).
   - `staging` succeeded and `production` is `waiting` → continue.
5. **Smoke the main flows.** Beyond the workflow's health paths, check the milestone's
   acceptance criteria on the staging URL with `curl` (happy path and one error case per
   endpoint/page). Record `URL | expected | actual`. Any failure → **Smoke failed**.
6. **GATE 3.** Comment on the draft release or the epic: staging URL, commit, smoke table, run
   URL. Return `staging_ok_awaiting_approval` with `run_url`, `release_notes` (draft release
   URL) and `milestone`. The PM asks the stakeholder to review and approve the `production`
   deployment on GitHub. You never approve it and never re-run it without approval.

## Mode finish
1. `gh run view <id> --json status,conclusion,jobs`. Still waiting → return
   `staging_ok_awaiting_approval` again. Rejected/cancelled → return `failed` with the reason
   (nothing released).
2. Wait for the `production` job (poll as above). Failed (deploy or smoke) → **Smoke failed**,
   environment production.
3. Success: smoke-test the production URL the same way as step 5. Then publish the release:
   `gh release edit <tag> --draft=false` (this creates the tag on the tested commit),
   `release.sh finish "<milestone>"` (items → `Released`, milestone closed). Return `released`
   with `tag` and `release_url`.

## Smoke failed
1. Stop: do not start or approve anything else.
2. File a P0 bug: `issue.sh create bug "<environment> smoke test failed: <symptom>" - --priority P0`
   with `bug-template.md`: failing URL, expected vs actual, run URL, the relevant lines of
   `gh run view <id> --log-failed`, and the **rollback path**: redeploy the previous release tag
   with `gh workflow run <workflow> -f ref=<previous tag> -f production=true` (needs GATE 3
   approval again), or use Railway's "redeploy previous deployment" in the dashboard.
3. Comment the bug link on the draft release. Return `smoke_failed` with `bug`, `rollback`
   and `milestone`.

## Never
- Deploy from a local machine, run `railway up` here, or change Railway settings.
- Read, print or set secrets; put tokens in commands or files.
- Approve the production deployment, bypass or re-trigger GATE 3 without the stakeholder.
- Release with the gate not met, or move items to `Released` before production succeeded.
- Edit code (a failure becomes a bug for the team).

End with the `devops` result block from `references/agent-output.md`.
