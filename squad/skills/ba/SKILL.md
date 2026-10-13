---
name: ba
description: "Turn a product idea or requirement sources (files, links, a chat description) into signed-off requirements and small user stories in the Backlog: analyze, ask clarifying questions until the BA declares them clear, get requirement sign-off (GATE 1), draft PRD and stories, get story approval (GATE 2), publish epic and stories. Use when the stakeholder brings a new feature or product idea, shares requirement documents, answers clarifying questions, or changes requirements mid-stream."
---

# squad: ba (requirements → stories)

Two roles share this procedure:
- **PM** = the main session. The only one who talks to the stakeholder, owns GATE 1 and 2.
- **BA** = the `ba-analyst` subagent, dispatched by the PM with a mode:
  `analyze | clarify | stories | revise`. It never talks to the stakeholder.

Phases run **strictly in order**: A Analyze → B Clarify until sign-off → C Stories. No skipping.
Paths: scripts in `${CLAUDE_PLUGIN_ROOT}/scripts/`, templates in
`${CLAUDE_PLUGIN_ROOT}/references/`. Rules: `references/board-conventions.md` (language!).

## Files (in the target repo)
```
docs/requirements/<slug>/
  sources/             converted sources (+ raw/ originals, *-pages/ scanned PDF images)
  requirements.md      the analysis, from requirement-analysis-template.md
  questions.md         questions-template.md
  understanding.md     the BA's latest "here is how I understand it" (plain language)
  prd.md, epic.md      prd-template.md; epic.md = "# <epic title>" + PRD summary + story list
  stories.md           index, FR → Story traceability, size self-check
  stories/S-01-<x>.md  one file per story, story-template.md
```
Keep these names: Claude Code refuses subagent writes to `.md` files whose name starts with
`analysis`, `summary`, `report` or `findings`.
`<slug>`: short kebab-case name agreed with the stakeholder (e.g. `todo-login`).

## Phase A: Analyze

**PM**
1. Collect sources. If the stakeholder did not name them, list candidates in the repo
   (`requirements/`, `docs/`, `*.pdf|docx|pptx|xlsx|md`) and ask which ones count.
2. Save a typed description verbatim as `sources/stakeholder-brief.md` (original language).
3. Dispatch `ba-analyst`: `mode=analyze slug=<slug> sources=<paths/URLs> config=.squad/config.yml`.

**BA (mode analyze)**: ask nothing, write no stories.
1. Convert each source: `"${CLAUDE_PLUGIN_ROOT}/scripts/ingest.sh" <file|url> <slug>`, one call
   per source with literal paths (no shell variables, loops or pipes: they are not permitted).
   Exit 4 (login) or 6 (unreadable): try WebFetch for URLs; if still unreadable, **do not
   guess**: return `needs_source` listing what is missing. Exit 5 (scanned PDF): read the page
   images and write their content into the stub's "Content" section. Images: read them and
   write the description into their stub.
2. Write `requirements.md`: goal, actors, `FR-nn` and `NFR-nn` **each with a source citation**
   (file + section/page), scope in/out, business rules, entities, and the four lists:
   **Gaps, Ambiguities, Conflicts** (quote both sides), **Assumptions**. Risks/dependencies.
3. Write `questions.md`: one question per gap/ambiguity/conflict/assumption that matters.
   Each: why it matters, related IDs, options A/B/C. Order by impact: scope and
   architecture-shaping questions first. Pick the next batch of 5–7.
4. Write `understanding.md` and return `questions_ready` with `open` count and `batch` IDs.

## Phase B: Clarify until sign-off (loop)

**PM**, each round:
1. Ask the batch **verbatim** from `questions.md`, in the stakeholder's language. Translating
   is allowed; rephrasing, merging, dropping, adding hints or answering is not. Show the
   options. Unanswered questions stay `open`.
2. Record each answer **verbatim** in `Answer (original)`, a faithful English translation in
   `Answer (English)`, and set `Status: answered`. Never summarize.
3. Anything the stakeholder volunteers outside the questions: append verbatim (with date) to
   `sources/stakeholder-notes.md`.
4. Re-dispatch `ba-analyst` with `mode=clarify`.

**BA (mode clarify)**
1. For each `answered` question: if the answer fully resolves it, apply it to `requirements.md`
   (FR/NFR/scope, changelog row) and set `confirmed` with a BA note. If it is unclear, set it
   back to `open` and say in the BA note what is unclear. If it resolves the question but
   raises something new, confirm it and add a follow-up `Q-nn`.
2. Read `stakeholder-notes.md`; turn new information into FRs or new questions.
3. Rewrite `understanding.md`: short plain-language "here is how I understand it" (scope, key rules,
   what is still assumed) so the stakeholder can catch misunderstandings.
4. Return `questions_ready` (next batch) or, when **no question is `open` or `answered`**
   (all `confirmed`, or `deferred` with stakeholder agreement and a reason), return `clear`.

Only the BA marks `confirmed`/`deferred` or declares requirements clear. The PM never does.

**GATE 1: requirement sign-off (PM)**
- Present `understanding.md` (scope, key FRs, remaining assumptions, deferred items), then ask
  explicitly, in the stakeholder's language: "Do you confirm these requirements are complete
  and correct?"
- Only an explicit yes counts ("ok", "đồng ý, làm đi"). Silence, "probably", or new
  information means: record it and go back to Phase B.
- On yes: insert `Signed-off: <YYYY-MM-DD> by <stakeholder name>` as the line after the title
  in `requirements.md` (for a change: `Re-signed (<change>): <date> by <name>` below it), and
  set its `- Status:` line to signed off.

## Phase C: Stories

**BA (mode stories)**: only when `requirements.md` has a `Signed-off:` line.
1. `prd.md` from the template, referencing confirmed FRs and Q decisions (no new scope).
2. Stories in English, one file each: "As a <role>, I want <capability>, so that
   <benefit>", Given/When/Then ACs, `Covers:` and `Decisions:`, priority, out of scope.
3. Keep stories small (board-conventions §6): vertical slices, at most
   `limits.story_max_ac` ACs. Split by workflow (happy path first), CRUD operation, business
   rule, role, data type/channel, or simple-version-first. Split anything over the limit
   **before** returning.
4. `stories.md`: index, **FR → Story traceability (every in-scope FR covered)**, size
   self-check. `epic.md`. Return `stories_ready`.

**BA (mode revise)**: apply the stakeholder's feedback (given verbatim) to the stories,
`prd.md`, `stories.md` and `epic.md`, re-run the size self-check and traceability, and return
`stories_ready`. If the feedback adds or changes requirements not yet covered by a
`Re-signed` line, change nothing and return `blocked` with the affected FRs: the PM follows
"Requirement changes mid-stream".

**GATE 2: story approval (PM)**
- Present each story (title, story sentence, AC names, priority) and the traceability table,
  in the stakeholder's language; the files stay English.
- Feedback → re-dispatch `ba-analyst` with `mode=revise` and the stakeholder's words verbatim.
  Repeat until an explicit approval.
- On approval:
  1. `"${CLAUDE_PLUGIN_ROOT}/scripts/issue.sh" publish <slug>` creates the epic and story
     sub-issues in `Backlog` (idempotent).
  2. Commit `docs/requirements/<slug>/` on branch `docs/<slug>-requirements`, open a PR
     ("docs: requirements for <slug>") and squash-merge it. GATE 2 is its review. Never
     commit to `main` directly.
  3. Tell the stakeholder the epic and story issue numbers.

## Requirement changes mid-stream
Record the change verbatim in `stakeholder-notes.md`, label affected stories/tasks `blocked`,
and run Phase B for the changed part only (`mode=clarify`). The BA adds a changelog row to
`requirements.md`. Re-sign GATE 1 for the change, revise stories (GATE 2), then remove `blocked`.

## Done when
Every in-scope FR maps to at least one story, every story has ≤ `story_max_ac` Given/When/Then
ACs, the epic and stories are in `Backlog`, and the requirement docs are merged.

## Never
- Write stories or create issues before GATE 1, or publish before GATE 2.
- Answer for the stakeholder, or turn an assumption into a decision without asking.
- Choose technology, design technical solutions, or split technical tasks (Team Lead's job).
- Write any artifact in Vietnamese. Vietnamese lives only in `Answer (original)`, in
  `stakeholder-notes.md`/`stakeholder-brief.md`, and in parentheses after business terms.
