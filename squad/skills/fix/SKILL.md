---
name: fix
description: "Quick lane for one small change: a bug against existing behavior, a text or style tweak, a small refactor or a dependency bump. Skips the BA, GATE 1/2 and story planning: the Team Lead turns the request into one XS/S task, then a developer, the reviewer, the Team Lead merge and a light QA check run as usual. Use when the stakeholder says fix, change, tweak, rename or bump something small; use the ba skill for new features or anything that needs product decisions."
---

# squad: fix (quick lane)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

You are the PM in the main session. `/squad:fix <what to change> [priority=P0..P3]`
(default P2). The request goes through the same safety steps as any task (own worktree,
TDD, size limit, review verdict, Team Lead merge, QA on `main`), without the requirement
and story work. You never write the code yourself.

## When it fits
One task of size XS or S whose expected result is clear from the request or the existing
code. Examples: "the sign-up button says Sumbit", "the task list crashes on an empty title",
"bump zod to 3.23". Not a fit: a new screen or flow, a change of business rules, anything
that needs several tasks or a product decision. Then say so and offer `/squad:ba`. When you
are unsure, let the Team Lead decide (step 2).

## Steps
1. **Request.** Take the stakeholder's words verbatim (their language is fine). If the
   request names no observable result ("make it better"), ask one question first.
2. **Task.** Dispatch `squad:team-lead` with
   `mode=quick request=<verbatim words> priority=<P> config=.squad/config.yml`, and as the
   Agent call's `model` the config's `models.quick` when it is set.
   - `quick_planned` → tell the stakeholder in one short message: the task link, size and
     its Definition of Done. No gate: the request is theirs. If they object, close the task
     (`gh issue close <n> --reason "not planned"`) and start again from their words.
   - `too_big_for_fix` → relay the reason and questions in their language. Answers that make
     it one small task → dispatch `mode=quick` again with the request plus the answers
     (verbatim). Otherwise offer the `ba` skill.
3. **Run.** Follow the `run` skill with `scope=#<task>` (default `max-steps=6`): developer →
   review → merge → QA. The `quick` flag and the cheaper models come from `next.sh`.
4. **Release** (skip when `deploy.platform` is `none`). When the task is `Done`, it is already on staging if the deploy workflow
   deploys `main`. Ask whether to ship it to production now and under which milestone (an
   open one, or a patch such as `v0.3.1`); on an answer dispatch `squad:team-lead` with
   `mode=milestone milestone=<title> stories=#<task>`, then continue with the `run` skill
   until GATE 3. Without an answer, it stays unreleased and `next.sh` keeps listing it.

## Report
At the end tell the stakeholder: PR link, review rounds, QA result, tokens used, and
what is waiting for them (GATE 3, a milestone name).

## Never
- Edit code, review, test or merge in the main session.
- Use the quick lane to slip in new behavior that has no requirement (use the `ba` skill).
- Bundle several requests into one task: one `/squad:fix` per change. Several small fixes
  can run in parallel: create each task, then one `run` with all of them in `scope`.
