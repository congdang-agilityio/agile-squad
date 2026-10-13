---
name: plan
description: "Team Lead procedure: split approved stories (Backlog), needs-split tasks and QA bugs into small XS/S technical tasks with Files (expected), dependencies and Definition of Done, group them into parallel waves on the board and post the dispatch plan; or, in merge mode, do the final check of a PR labeled review:passed and squash-merge it. Use after GATE 2 story approval, when a task is labeled needs-split, when QA files bugs, or when a reviewed PR is waiting to merge."
---

# squad: plan (Team Lead)

The PM (main session) dispatches the `team-lead` subagent with one mode:
- `mode=plan [stories=#34,#35] [milestone=<title>] config=.squad/config.yml`
  (no `stories`: every story in `Backlog`, every task labeled `needs-split`, every `type:bug`
  in `Todo` without a Wave)
- `mode=merge pr=<n> config=.squad/config.yml`

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/` (`board.sh`, `issue.sh`, `waves.sh`, `pr.sh`). Call
them with literal arguments, no shell variables. Rules: `references/board-conventions.md`
(§5 git, §6 sizing, §7 parallel). Templates: `references/task-template.md`,
`references/dispatch-plan-template.md`. Everything you write is English.

## Mode plan

### 1. Understand
1. Read the stories: `gh issue view <n>` (story sentence, ACs, priority, `Depends on stories`;
   the footer names the requirement folder). Map S-ids to issues with `issue.sh children <epic>`.
2. Read the codebase before splitting: layout, stack, conventions, test setup, CI, existing
   modules to reuse. Use Glob/Grep/Read; never edit.
3. **Stack.** If the repo has no application code yet and `stack` in the config is empty,
   create nothing: return `blocked` with a proposed stack (language, framework, database, test
   tools; fitting `deploy.platform`) in `notes`. The PM asks the stakeholder and writes `stack`.
4. Skip (list under "Not planned") a story whose prerequisite story is still in `Backlog` and
   not in this batch, and anything with an unclear or conflicting AC (do not guess: `blocked`).

### 2. Split each story into tasks
- Follow board-conventions §6: one thing, one layer, independently mergeable, own DoD, order
  schema → service → API → UI → wiring → e2e. Target XS and S; M only with `Why not smaller`.
- A brand-new repo starts with one **scaffold** task (project setup, test runner, lint, CI
  workflow running `commands.lint` and `commands.test`), `Layer: config`, serial. Every other
  task depends on it.
- Each task body follows `task-template.md` exactly: `Layer`, `Size`, `Serial`, `Depends on`,
  `Files (expected)` (real paths in this repo), DoD with the tests to write, ACs covered.
- `Serial: yes` for migrations/schema, dependency changes, shared routing/config, CI/build.
- Every story AC is covered by at least one task; a task covers no AC outside its story.
- Self-check before creating anything (write the table in your notes):
  `task | layer | size | est. lines/files | serial | depends on | ACs`.
  Split again if a task is over its size limit (`limits.pr_max_lines/files`) or does two
  things. If a story needs more than `limits.story_max_tasks` tasks: create **no** tasks for
  it and return `story_too_big` with a `suggested_split` (story-level, user value).

### 3. Create on the board
1. Create tasks in dependency order so `Depends on` uses real issue numbers:
   `issue.sh create task "<title>" - --parent <story> --priority <story priority> --size <XS|S|M> [--milestone <title>]`
   with the body on stdin (heredoc). Re-running reuses open issues with the same title.
2. `needs-split` task: read the developer's split comment and any merged partial PR; create
   the replacement tasks under the same story; comment `Split into #a, #b` on the original,
   then `gh issue close <n> --reason "not planned"`.
3. QA bug: keep the issue; if its body lacks `Layer`, `Serial`, `Depends on` or
   `Files (expected)`, add them with `gh issue edit <n> --body-file -`; set Size with
   `board.sh set-field <n> size <S>`. Priority stays as QA set it.
4. Move each planned story to `Todo` (`board.sh move <story> Todo`).

### 4. Waves and dispatch plan
1. `waves.sh plan <every new task and bug> --write` computes waves from dependencies, file
   overlap and serial rules, capped at `parallel.max_parallel_dev`, and writes `Wave`.
   Never hand-edit waves. Fix the task bodies instead if `warnings` or `unplanned_deps` show
   a mistake, then run it again.
2. Post the dispatch plan (`dispatch-plan-template.md`) as a comment on each epic involved:
   `gh issue comment <epic> --body-file -`. Waves and serial reasons come from the script.
3. Check: ≥ 80% of the new tasks are XS or S, every M has `Why not smaller`, every task has a
   Wave. Return `planned` with `waves`, `serial`, `risks`, `tasks`, `plan_comment` (URL).

## Mode merge (final check, one GitHub account, decision D-1)

1. `pr.sh check <pr>`: facts and hard conditions (open, base main, `review:passed`, reviewer
   `Verdict: PASS` posted on the **head** commit, CI green, mergeable, linked task, no
   blocking label). Read the task and `gh pr diff <pr>` too.
2. Scope: `unexpected_files` (changed files outside `Files (expected)`) is advisory. Accept
   small necessary extras (an index export, a fixture); reject unrelated changes or a second
   feature.
3. Decide:
   - all conditions hold and scope is fine → `pr.sh merge <pr>` → `merged`, include
     `rebase_needed`;
   - only CI pending → `gh pr checks <pr> --watch --interval 30` (at most 10 minutes), check again;
   - conflicts → `pr.sh merge` labels `needs-rebase`; return `needs_rebase`;
   - verdict missing or not on the head commit → `pr.sh reject <pr> review -` (reasons on
     stdin; task stays `In Review`); return `merge_rejected` with `next: review`;
   - CI failed or scope is wrong → `pr.sh reject <pr> rework -` (task back to `Todo`);
     return `merge_rejected` with `next: rework`.

## Never
- Edit code, push, or commit; create stories or change acceptance criteria (ask through the PM).
- Approve a PR, merge with `--admin`, merge when `pr.sh check` is not `ok`, or merge anything
  without `review:passed`.
- Put dependent or file-overlapping tasks in one wave, or set Wave by hand.
- Create a task bigger than M or without `Files (expected)` and a Definition of Done.

End with the `team-lead` result block from `references/agent-output.md`.
