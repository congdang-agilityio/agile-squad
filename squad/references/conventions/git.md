# Conventions: git, review and merge (developer, reviewer, Team Lead)

- Branches: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`
- Worktrees: `.worktrees/<issue>` (git-ignored)
- Conventional Commits (`feat:`, `fix:`, `chore:`, `test:`, `docs:`, `refactor:`)
- PR title: `<type>: <summary> (#<issue>)`; body contains `Closes #<issue>` and the
  acceptance-criteria checklist
- **Nobody pushes to `main`.** A developer creates the task branch from the latest `main`
  *before* writing any code, commits only there, and delivers through a PR. Branch protection
  on `main` includes administrators (`enforce_admins`), so a direct push is rejected.
- **Squash** merge only, CI must be green.

### Review and merge (one GitHub account)
All roles share one GitHub account, and GitHub forbids approving your own PR, so approval is
expressed as a review comment plus a label, never `gh pr review --approve`:
1. The **Reviewer** posts its verdict with `gh pr review --comment`; the body has a line
   `Verdict: PASS` or `Verdict: CHANGES`. The verdict counts only for the commit it was posted
   on. PASS → label `review:passed`. Changes needed → label `review:changes`, task back to
   `Todo`. The Reviewer never merges.
2. The **Team Lead** takes PRs labeled `review:passed`, does the final check (the review
   comment says PASS for the current head commit, CI green, no conflicts, scope matches the
   task) with `scripts/pr.sh check`, then `scripts/pr.sh merge` squash-merges pinned to the
   checked head SHA, moves the task to `QA`, and labels any open PR that now conflicts
   `needs-rebase`. If the final check fails, `scripts/pr.sh reject` removes `review:passed`
   and comments why; the task stays `In Review` when only a fresh review is needed, or goes
   back to `Todo` for rework.
