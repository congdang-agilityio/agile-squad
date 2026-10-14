---
name: doctor
description: "Diagnose why squad cannot run in this repository: tools, gh login and token scopes, .squad/config.yml and its board ids, board fields and Status columns, labels, conflicting project workflows, merge settings, branch protection, deploy workflow, GitHub Environments and secrets, the gh pr merge permission rule and leftover worktrees. Read-only; proposes each fix and applies it only after the stakeholder agrees. Use when a squad script fails, after a machine restart or a fresh clone, before the first run, or when the stakeholder asks whether squad is set up correctly."
---

# squad: doctor

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

Runs in the **main session** (PM). No subagent: it only reads, then asks.

## Steps
1. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"` from the repository root (`--offline`
   when there is no network). It prints JSON `{ok, fails, warns, checks}`; each check has
   `status` (`ok`, `warn`, `fail`), `detail` and `fix`.
2. Tell the stakeholder, in their language: one line per `fail` and `warn` with what it
   breaks and the fix; then "everything else is OK" with the number of passing checks.
   - `fail`: squad cannot work correctly until it is fixed (`/squad:run` would stop).
   - `warn`: squad runs, with a gap (e.g. no branch protection, no production secret yet).
3. Fixes, one confirmation for the whole list ("fix all?") unless a fix is destructive:

   | Check | Fix | Who |
   |---|---|---|
   | `config` missing | the `setup` skill | PM |
   | `ids`, `board` | `board.sh bootstrap --project <n>` (reuses the board, rewrites ids) | PM |
   | `labels` | `issue.sh labels` | PM |
   | `project_workflows` | `board.sh workflows --fix` **deletes** them: explicit yes for this one | PM |
   | `gh_auth` | `! gh auth refresh -h github.com -s project,workflow` | stakeholder |
   | `merge_permission` | add `"Bash(gh pr merge:*)"` to `.claude/settings.json` | PM, after yes |
   | `gitignore` | append the missing lines | PM |
   | `merge_settings`, `branch_protection`, `environment:*`, `deploy_workflow` | `setup` skill steps 5 and 8 | PM |
   | secret `RAILWAY_TOKEN` | `gh secret set RAILWAY_TOKEN --env <env>` | stakeholder (never the PM) |
   | `worktrees` | `worktree.sh clean <issue> --delete-branch --pr-merged` | PM |
   | `commands` | propose values from the stack (setup step 7), write after yes | PM |

   Changes to tracked files (`.gitignore`, `.claude/settings.json`, workflows) go on a branch
   `chore/squad-doctor` with a PR, never straight to `main`.
4. Run `doctor.sh` again and report the result.

## Never
- Fix anything without the stakeholder's yes, or delete project workflows without an
  explicit yes for that item.
- Read, print or set secrets or tokens.
- Edit `ids:` in the config by hand.
