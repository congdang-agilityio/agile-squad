---
name: setup
description: "Initialize squad in the current repository: create or reuse the GitHub Projects board with the squad Status columns and Priority/Size/Wave/Agent/Attempts fields, create the labels, write .squad/config.yml, and configure merges, branch protection and .gitignore. Use the first time squad is used in a repository, when .squad/config.yml is missing, or when a board script reports missing ids."
---

# squad: setup

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

Runs in the **main session** (PM). No subagent: it needs a few stakeholder decisions.

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (call them by this full path)
- Conventions: `${CLAUDE_PLUGIN_ROOT}/references/board-conventions.md`
- Talk to the stakeholder in their language; everything written to files and GitHub is English.

## Inputs

- The current directory is a clone of the target repository with a GitHub remote.
- Optional: an existing project number to reuse (`--project N`) or a project title.

## Steps

1. **Preflight.** Run `gh auth status --active` and confirm the active account is the one the
   stakeholder wants to use. If its token scopes lack `project` (or `workflow`, needed for the
   deploy workflow), stop and ask the stakeholder to run:
   `! gh auth refresh -h github.com -s project,workflow`. Check that `jq` and `git` exist.

2. **Board.** Ask whether to reuse an existing project (number) or create a new one, unless the
   stakeholder already said. Then run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh" bootstrap [--project N] [--title "<title>"]
   ```
   It creates `.squad/config.yml` from the template if missing, creates or reuses the project,
   links it to the repo, aligns the Status options (keeping existing option ids), creates the
   Priority, Size, Wave, Agent and Attempts fields, and writes every id into the config.
   It is idempotent: re-running it changes nothing when the board is already correct.

3. **Built-in project workflows.** Run `board.sh workflows`. Any entry with `"conflicts": true`
   sets Status behind squad's back (for example "Item closed" moves a task to Done when its
   PR merges, skipping QA). GitHub's API can only delete these workflows, not disable them, so:
   - New project created in step 2: run `board.sh workflows --fix`.
   - Existing project: show the list to the stakeholder, explain the effect, and run `--fix`
     only after an explicit yes. Otherwise tell them to disable those workflows in the
     project's Workflows settings page.
   Keep "Auto-add sub-issues to project" and "Auto-close issue".

4. **Labels.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/issue.sh" labels` (creates or updates all 12).

5. **Repository settings.** Squash merge only, and delete branches after merge:
   ```bash
   gh repo edit <owner>/<repo> --enable-squash-merge --enable-merge-commit=false \
     --enable-rebase-merge=false --delete-branch-on-merge
   ```
   Then protect `main`: PRs required, administrators included (so nobody, not even this
   account, can push to `main` directly), no force pushes, linear history:
   ```bash
   echo '{"required_status_checks":null,"enforce_admins":true,
     "required_pull_request_reviews":{"required_approving_review_count":0},
     "restrictions":null,"required_linear_history":true,
     "allow_force_pushes":false,"allow_deletions":false}' \
   | gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input -
   ```
   Approvals stay at 0 because every squad role uses the same GitHub account, and GitHub does
   not let an account approve its own PR: the Reviewer's verdict is a review comment plus the
   `review:passed` label, and the Team Lead merges (see board-conventions, "Review and merge"). If the call fails (HTTP 403 on private repos
   without GitHub Pro/Team, or missing admin rights), do not stop: tell the stakeholder that
   squad will still follow the PR-only flow, and how to enable protection later (make the
   repo public or upgrade, then re-run setup). Once CI exists, add its check name to
   `required_status_checks` with `"strict": true`.

6. **Git hygiene.** Ensure `.gitignore` contains `.worktrees/` and `.squad/reports/` (append if missing).

7. **Commands.** Detect the stack (e.g. `package.json` scripts, `pyproject.toml`, `Makefile`) and
   propose values for `commands.install`, `test`, `lint` and `e2e` in `.squad/config.yml`. Show
   them to the stakeholder and write them after confirmation. Leave `e2e` empty if there is none.

8. **Deploy workflow.** If `.github/workflows/` has no deploy workflow, copy
   `${CLAUDE_PLUGIN_ROOT}/templates/deploy.yml` to `.github/workflows/deploy.yml` (Railway by
   default) and record `deploy:` in the config. Create GitHub Environments `staging` and
   `production`; `production` gets the stakeholder as required reviewer (GATE 3):
   `gh api -X PUT repos/<owner>/<repo>/environments/production --input -` with
   `{"reviewers":[{"type":"User","id":<id>}]}`. Set the variable `APP_URL` per environment
   (`gh variable set APP_URL --env staging --body <url>`). Ask the stakeholder to create one
   Railway project token per Railway environment and store it themselves:
   `gh secret set RAILWAY_TOKEN --env staging` (and `--env production`). Never handle the token.

9. **CLAUDE.md.** Add (or update) this section in the repo's `CLAUDE.md`:
   ```markdown
   ## squad
   This repository is run by the squad plugin. Board, ids, commands and limits live in
   `.squad/config.yml`; the GitHub Projects board is the single source of truth for work state.
   Use `/squad:run` to continue work. Do not edit `ids:` in the config by hand.
   ```

   **Permissions.** Claude Code's auto mode refuses `gh pr merge` as "merge without review"
   (it cannot see squad's review). Ask the stakeholder whether to add
   `"Bash(gh pr merge:*)"` to `permissions.allow` in `.claude/settings.json`, so the Team Lead
   can merge after the Reviewer's PASS. Branch protection still guards `main`.

10. **Verify and commit.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/board.sh" list Todo`; it must
    print a JSON array without errors. Then commit `.squad/config.yml`, `.gitignore`,
    `CLAUDE.md`, `.claude/settings.json` and any workflow file on a branch `chore/squad-setup`,
    open a PR and squash-merge it after the stakeholder agrees. Never commit to `main`.

## Output

Tell the stakeholder, in their language: the board URL
(`https://github.com/users/<owner>/projects/<n>` or `/orgs/<owner>/projects/<n>`), what was
created versus reused, what could not be configured (protection, environment) and what they
must do by hand.

## Done when

- `board.sh list Todo` runs without errors.
- `.squad/config.yml` has every id under `ids:` (status, priority and size options included).
- All 12 labels exist; no conflicting built-in workflow remains enabled (or the stakeholder
  explicitly chose to keep it).

## Never

- Delete project workflows on an existing board without the stakeholder's explicit yes.
- Edit ids in the config by hand; re-run `bootstrap` instead.
- Store tokens or deploy secrets in the repository.
- Use a GitHub account other than the one the stakeholder confirmed.
