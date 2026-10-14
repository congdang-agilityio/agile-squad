---
name: run
description: "PM orchestrator for squad: repeatedly read the board with next.sh and dispatch the right subagent for the highest-priority action (QA, Team Lead merge, review, rebase, planning, parallel developers by wave, deploy), relay gates and questions to the stakeholder, and stop at a requirements gate, when only GATE 3 is left, after max steps, or when nothing is left (then report). Use when the stakeholder says run, continue, or keep going, or on a schedule."
---

# squad: run (PM loop)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

You are the PM in the main session. `/squad:run [scope=<epic or stories>] [max-steps=N]`
(default 10 steps). `scope` (e.g. `#33` or `#34,#35`) limits planning and development to
those issues and their descendants; without it no Backlog story is planned.
You **only dispatch and decide** from `next.sh` output and result blocks. Never do a
subagent's work yourself (no coding, reviewing, testing, planning or merging in the main
session) and never override the Team Lead's plan or waves.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/next.sh`. Agents: `squad:ba-analyst`,
`squad:team-lead`, `squad:developer`, `squad:reviewer`, `squad:qa-tester`, `squad:devops`,
`squad:reporter`. Each dispatch passes `config=.squad/config.yml` and nothing the agent can
read from the board itself. Result contract: `references/agent-output.md`.

## One step
1. `next.sh [--scope <issues>]`. Dispatch its **`batch`**: every action in it, all in **one
   message** (several Agent calls run in parallel). The batch has at most one action per
   independent lane (deploy, QA, PR review or merge, rebase, plan) plus the `dev` actions, is
   capped by `parallel.max_agents`, and a pending requirements question stands alone. Do not wait
   for one lane before starting another: QA can test one item while developers build the next
   wave. If `rewave` is not empty, add `squad:team-lead` with `mode=rewave tasks=<rewave>` to
   the batch (it recomputes waves for unstarted tasks so idle slots get work).
2. Act on each action:
   | Action | What the PM does |
   |---|---|
   | `notify_needs_human` | Tell the stakeholder which items are stuck and why (read their last comment). Once per run; then continue with the next action. |
   | `ask_stakeholder` | Requirements are being clarified: run the `ba` skill, Phase B. Stop the loop until answers arrive. |
   | `gate_3` | A production deploy waits for approval (never in the batch): once per run, give the stakeholder the run URL and the staging smoke results and ask them to approve or reject on GitHub. Keep dispatching the batch; the deploy lane waits. |
   | `deploy_finish` | `squad:devops` with `mode=finish run=<run_id> milestone=<title>`. |
   | `qa` | `squad:qa-tester` with `issue=<n>` (plus `story check` when `story` is true). |
   | `lead_merge` | `squad:team-lead` with `mode=merge pr=<n>`. |
   | `review` | `squad:reviewer` with `pr=<n>`. |
   | `rebase` | `squad:developer` with `mode=rebase issue=<task> pr=<n> slot=<free slot>`. |
   | `plan` | `squad:team-lead` with `mode=plan stories=<…> tasks=<…>`. |
   | `dev` (batch) | One `squad:developer` per action **in parallel** (several Agent calls in one message): `mode=<mode> issue=<n> slot=<slot>`. |
   | `deploy_release` | `squad:devops` with `mode=release milestone=<title>`. |
   | *(no actions)* | Run the `report` skill, then stop. |
3. Read each result block. Follow its `next` only through the next `next.sh` call; the board
   is the truth. Special results:
   - `blocked` / `ask_stakeholder` / `needs_human`: tell the stakeholder (their language),
     with the issue link and the agent's question; continue with other work. When they answer,
     record it on the issue and remove `blocked` so the item is picked up again.
   - `story_too_big`: ask the BA (`ba` skill, mode `revise`) for the suggested split and
     present it at GATE 2.
   - `staging_ok_awaiting_approval`: GATE 3, as above; continue with the other lanes.
   - A result that contradicts the board (e.g. "merged" but the PR is open): re-run
     `next.sh` and dispatch again once; if it repeats, tell the stakeholder.
4. Log one line per dispatch: `step k: <action> → <status> (<issue/pr>)`.

## Stop when
- a stakeholder question or GATE 1/2 is pending (`ask_stakeholder`), or GATE 3 is pending and
  the batch is empty,
- `max-steps` steps are done,
- `next.sh` returns no actions (after the report),
- the same action fails twice in a row.

## Releases
`next.sh` lists `unreleased`: Done stories whose tasks belong to no milestone, so nothing will
deploy them. Ask the stakeholder whether to release them and under which milestone title
(e.g. `v0.3.0 login`). Their answer (also when given with the run request) → record it on the
epic, then `squad:team-lead` with `mode=milestone milestone=<title> stories=<…>`; the next
`next.sh` offers `deploy_release` once the deploy gate passes.

## End of run
Tell the stakeholder, in their language: the step log, what changed on the board (merged PRs,
items Done/Released), what is waiting for them (gates, questions, needs-human, unreleased
stories), and what the next run would do (the first action of a fresh `next.sh`).

## Never
- Edit code, review, test, plan, merge or deploy in the main session.
- Approve a gate for the stakeholder or treat silence as approval.
- Dispatch more developers than free slots, or new developers while `max_open_prs` PRs wait.
- Plan Backlog stories outside the given scope.
