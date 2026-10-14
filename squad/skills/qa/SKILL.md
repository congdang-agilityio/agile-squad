---
name: qa
description: "QA procedure: verify a merged task, bug or story in the QA column against every acceptance criterion and DoD item by running the full test suites, e2e and the real app on the latest main; pass it to Done with a test report, or file a bug sub-issue from the bug template and keep the task out of Done. Also re-verifies a task whose bugs are fixed and closes stories whose tasks are all Done. Use when items are waiting in QA."
---

# squad: qa (verify on main, pass or file bugs)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

The PM dispatches a fresh `qa-tester` subagent: `issue=<n> config=.squad/config.yml`
(one task or bug per invocation). When invoked directly (`/squad:qa <issue>`), dispatch the
`qa-tester` subagent instead. QA never edits code and never weakens a criterion.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`worktree.sh`, `board.sh`, `issue.sh`), literal
arguments. Template: `references/bug-template.md`. Rules: `references/board-conventions.md`.

## 1. Prepare
1. `board.sh get <n>`: the item must be in `QA`. Read it (`gh issue view <n> --json title,body,labels,closedByPullRequestsReferences,comments`),
   its parent story (`issue.sh parent <n>`) and the story's ACs, the merged PR (`Found in`), and
   its sub-issues (`issue.sh children <n>`): bugs filed earlier and their status.
2. **Open bugs first.** If any child bug is not `Done`/`Released`, the task cannot pass: return
   `bug_created` with the open `bugs` and do nothing else.
3. `worktree.sh qa` gives `.worktrees/qa` at the latest `origin/main` with the QA port and
   database (`.env.local`; tools must read it, no inline `VAR=…` prefixes). Run
   `commands.install`, `commands.services` if tests need them, then build.

## 2. Verify
1. Full suites on main: `commands.lint`, `commands.test`, and `commands.e2e` if set. A failure
   that this item caused is a bug for it; an unrelated failure is a separate bug on the story.
2. **Every** criterion of the item (task DoD and the story ACs it claims; for a bug, its
   "Failed criterion" and DoD) is checked against the **running app** where possible: start
   it on the QA port (`npm run build` + `npm start`, run in the background) and use `curl` or
   e2e. Unit tests passing is not enough on its own. For each criterion record: how it was
   checked, the exact command or test, the observed result.
3. Quick regression: the neighbouring features (same page, endpoint group or module).
   **Quick-lane task** (`quick` from the PM, label `quick`): check its DoD and `Request` on
   main with the full suites; start the app only when a DoD item is visible in the UI or API;
   regression only for the files it changed. It has no story: skip the **Story** step under "Decide".
4. Stop the app you started: `lsof -ti tcp:<QA port>` gives its PID, then `kill <pid>`
   (only that PID; never `pkill`, which could hit other projects' servers). Check the port is free.

## 3. Decide
- **All criteria met, no regression:**
  1. Comment a test report on the item: commit tested, table `criterion | how checked | result`,
     regression checked, suites run.
  2. `board.sh move <n> Done`; remove `qa:failed` if present.
  3. If it is a bug, also re-check its parent task now (the task may pass once all its bugs are
     `Done`): report it in `notes` so the PM dispatches QA for the parent.
  4. **Story:** if every task of the parent story is `Done`/`Released` and it has no open bugs,
     verify the story's ACs end to end the same way, then comment and move the story to `Done`.
     (`issue=<story>` with `story: true` from the PM: do only this check.) An AC that only the
     stakeholder can confirm and has no recorded answer is not a bug: comment what is needed,
     `gh issue edit <story> --add-label blocked`, return `blocked` with the question.
  5. **Milestone:** if the item has a milestone and every issue in it is `Done`/`Released` with
     no open bug, append "Ready to deploy (<date>)" to the milestone description
     (`gh api -X PATCH repos/<owner>/<repo>/milestones/<m> -f description=…`) and return
     `ready_to_deploy: true`.
  6. Return `passed`.
- **Any criterion not met, or a regression:**
  1. One bug per distinct problem: `issue.sh create bug "<symptom>" - --parent <n> --priority <item priority>`
     with the body from `bug-template.md` (steps, expected vs actual verbatim, evidence,
     `Found in #<PR>`). Bugs start in `Todo`.
  2. On the item: `gh issue edit <n> --add-label qa:failed`, `board.sh bump-attempts <n>`,
     comment the report with links to the bugs. The item **stays in `QA`**; it reaches `Done`
     only after all its bugs are `Done` and a re-check passes.
  3. If the new Attempts exceeds `limits.max_attempts`: `gh issue edit <n> --add-label needs-human`,
     comment the history (attempts, bugs, what keeps failing) and return `needs_human`.
     Otherwise return `bug_created` with `bugs` and `attempts`.

## Never
- Edit, commit or push code; fix a bug yourself; change or reinterpret an acceptance criterion.
- Move an item to `Done` with an open bug, a failing suite or an unchecked criterion.
- Pass on "tests are green" alone when a criterion can be observed in the running app.
- Leave the app or services you started running, or test anywhere but `.worktrees/qa`.

End with the `qa` result block from `references/agent-output.md`.
