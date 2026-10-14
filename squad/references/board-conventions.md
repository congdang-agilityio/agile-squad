# Board conventions (index)

The rules every squad role follows are split by role, so each subagent reads only what it
needs:

| File | Content | Read by |
|---|---|---|
| `conventions/core.md` | board as source of truth, Status column and owners, fields, labels, issue relationships, bounded loops, language, human gates | everyone |
| `conventions/git.md` | branches, worktrees, commits, PRs, review verdicts and merge (one GitHub account) | developer, reviewer, Team Lead, PM |
| `conventions/sizing.md` | story and task size limits and splitting patterns | BA, Team Lead, developer, reviewer |
| `conventions/parallel.md` | waves, serial tasks, slots, rebase, open-PR limit | Team Lead, PM |

Result blocks: `agent-output.md` (common fields) and `results/<role>.md` (statuses per role).
