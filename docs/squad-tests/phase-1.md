# Phase 1: Board foundation — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Board: https://github.com/users/congdang-agilityio/projects/1

## Built
- `scripts/lib.sh`: config lookup (main worktree aware), a YAML-subset → JSON reader in awk
  (no `yq` needed), GraphQL helper, `inherit_errexit`
- `scripts/board.sh`: `bootstrap`, `list`, `get`, `move`, `set-field`, `ready-tasks`,
  `bump-attempts`, `workflows [--fix]`
- `scripts/issue.sh`: `create`, `link`, `children`, `parent`, `labels`
- `skills/setup/SKILL.md` (112 lines)
- `templates/squad.config.yml` (plan name `devteam.config.yml`, renamed for squad)

## Acceptance
| Check | Result |
|---|---|
| `bootstrap` creates the project, links the repo, 7 Status options, Priority/Size/Wave/Agent/Attempts | PASS |
| Re-running `bootstrap` changes nothing (config byte-identical; default option ids kept) | PASS |
| `issue.sh labels` creates all 11 labels | PASS |
| `phase-1.sh`: epic → story → task sub-issues, duplicate-safe create, fields, attempts, a task through all 7 statuses, dependency-aware `ready-tasks`, error cases, self-cleanup | PASS (20/20) |
| `board.sh list Todo` runs without errors (setup "done when") | PASS |

Run it again with: `cd <sandbox clone> && bash docs/squad-tests/phase-1.sh <path>/squad/scripts`.

## Findings fixed during testing
1. **Built-in project workflows fight squad.** New boards ship with "Item closed → Done" and
   "Pull request merged → Done" (a merged PR with `Closes #N` would skip QA), plus "Item added"
   and "PR linked" which overwrite Status. The API can only delete them, so
   `board.sh workflows --fix` deletes those four (setup asks first on existing boards).
   "Auto-close issue" and "Auto-add sub-issues" are kept. Done on the sandbox.
2. **Sub-issue auto-add race:** GitHub may add the issue itself while the script adds it
   ("Content already exists"); `item_id` now re-reads and retries.
3. **`set -e` was not active inside `$(...)`:** added `shopt -s inherit_errexit`.
4. **Number fields come back as floats** (`1.0`): normalized to integers.
5. **Archived items are returned by the items query:** filtered out.
6. **The board listing is eventually consistent** (new items appear after ~10–30 s);
   `get` now reads the issue directly, `ready-tasks` resolves unlisted dependencies directly.

## Environment limits found (affect later phases)
- The sandbox is **private on a free plan**: branch protection returns HTTP 403. Squash-only
  merges and delete-branch-on-merge are set.
- Every role uses one GitHub account, and GitHub does not allow approving your own PR, so
  `gh pr review --approve` will fail in Phase 4. Required approvals are set to 0 in setup.
- GitHub Environment required reviewers (GATE 3) on private repos also depend on the plan.
