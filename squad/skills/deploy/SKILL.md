---
name: deploy
description: "DevOps procedure for releasing a milestone: check the deploy gate (all items Done, CI on main green, no open P0/P1 bugs), draft release notes, deploy and smoke-test staging through the GitHub Actions deploy workflow, start the approval-gated production job (GATE 3, approved by the stakeholder on GitHub), then tag, publish the release and mark items Released; on a failed smoke test stop and file a P0 bug. Use when a milestone is ready to deploy or after the stakeholder approved production."
---

# squad: deploy (milestone → staging → GATE 3 → production)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

The PM dispatches a fresh `devops` subagent:
- `mode=release milestone=<title> config=.squad/config.yml`: gate, notes, staging, then stop
  at GATE 3;
- `mode=finish run=<run id> milestone=<title> config=.squad/config.yml`: after the stakeholder
  approved (or rejected) production on GitHub.
When invoked directly (`/squad:deploy <milestone>`), dispatch the `devops` subagent instead.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`release.sh`, `board.sh`, `issue.sh`), literal
arguments, one command per call (no pipes, loops or multi-line quoted text). Workflow: `deploy.staging_workflow` (default `deploy.yml`, from
`templates/deploy.yml`). Everything runs on GitHub Actions: **never deploy from this machine**
(no `railway up` here), never read, print or set secrets.

## Mode release
1. **Gate.** `release.sh gate "<milestone>"`. Not `ok` → return `gate_not_met` with the
   `reasons`. Nothing else.
2. **Draft notes.** `release.sh draft "<milestone>" <main sha>` (main sha = `ci_main.headSha`
   from the gate): a draft GitHub Release with generated notes on the tested commit
   (re-running updates it).
3. **Staging + production request.** `release.sh deploy <main sha>` starts the workflow with
   `production=true` and prints the new run `{id, url}`.
4. **Follow staging.** `release.sh wait <run> staging` (polls; never `sleep` loops or
   `gh run watch`, which would block on the approval).
   - `staging` failed → **Smoke failed** (below).
   - `staging` succeeded and the run is `waiting` → continue.
5. **Smoke the main flows.** Beyond the workflow's health paths, check the milestone's
   acceptance criteria on the staging URL with `curl` (happy path and one error case per
   endpoint/page; take real paths from the code or the stories, never guess). Record
   `URL | expected | actual`. Any failure → **Smoke failed**.
6. **GATE 3.** Comment on the epic (or, for quick tasks, on each task): staging URL, commit,
   smoke table, run URL, and anything the stakeholder should check first (for example a
   missing platform setting). Return `staging_ok_awaiting_approval` with `run_url`,
   `release_notes` (draft release URL) and `milestone`. The PM asks the stakeholder to approve
   or reject the `production` deployment on GitHub. You never approve it and never re-run it
   without approval.

## Mode finish
1. `release.sh wait <run> production`. `run_status` still `waiting` → return
   `staging_ok_awaiting_approval` again. Rejected/cancelled → comment it on the epic, delete
   the draft (`gh release delete <tag> --yes`; a draft has no tag) so the next release starts
   again from the gate, and return `failed` with the reason.
2. `production` failed (deploy or smoke) → **Smoke failed**, environment production.
3. Success: smoke-test the production URL the same way as release step 5. Then
   `release.sh publish "<milestone>" [--note "<known limitation, one line>"]...` (creates the
   tag on the tested commit; one `--note` per limitation the stakeholder accepted) and
   `release.sh finish "<milestone>"` (items → `Released`, milestone closed). Return
   `released` with `tag` and `release_url`.

## Smoke failed
1. Stop: do not start or approve anything else.
2. File a P0 bug: `issue.sh create bug "<environment> smoke test failed: <symptom>" - --priority P0 --milestone "<milestone>"`
   with `references/bug-template.md`: failing URL, expected vs actual, run URL, the relevant lines of
   `gh run view <id> --log-failed`, and the **rollback path**: redeploy the previous release tag
   with `gh workflow run <workflow> -f ref=<previous tag> -f production=true` (needs GATE 3
   approval again), or use the platform's "redeploy previous deployment".
3. Delete the draft release (`gh release delete <tag> --yes`) so the fixed milestone starts
   again from the gate, comment the bug link on the epic, and return `smoke_failed` with
   `bug`, `rollback` and `milestone`.

## Never
- Deploy from a local machine, run `railway up` here, or change Railway settings.
- Read, print or set secrets; put tokens in commands or files.
- Approve the production deployment, bypass or re-trigger GATE 3 without the stakeholder.
- Release with the gate not met, or move items to `Released` before production succeeded.
- Edit code (a failure becomes a bug for the team).

End with the result block from `references/agent-output.md` and `references/results/devops.md`.
