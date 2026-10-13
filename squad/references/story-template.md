<!-- File: docs/requirements/<slug>/stories/S-<nn>-<short-slug>.md
     The first heading becomes the GitHub issue title (without the "S-nn: " prefix);
     the rest of the file becomes the issue body. -->
# S-<nn>: <Short title in plain words>

- **Priority:** P0 | P1 | P2 | P3
- **Covers:** FR-03, FR-04 · **Decisions:** Q-02, Q-07
- **Depends on stories:** none | S-<nn>

## User story
As a <role>, I want <capability>, so that <benefit>.

## Acceptance criteria
(At most `limits.story_max_ac`, default 5. Each one observable by a user or a test.)

1. **<name>**
   - Given <context>
   - When <action>
   - Then <observable outcome>
2. …

## Out of scope
- <What this story deliberately does not do, and which story does it, if any.>

## Notes
- <Business rules, examples, edge cases the BA wants the Team Lead to see. No technical design.>

---
<!-- Stories index: docs/requirements/<slug>/stories.md must contain:

## Stories
| ID | Title | Priority | ACs | Covers |
|---|---|---|---|---|

## FR → Story traceability
| FR | Stories |
|---|---|
| FR-01 | S-01, S-03 |     ← every FR in scope appears; no empty cells

## Size self-check
| Story | ACs | ≤ limit? | Split pattern used |
|---|---|---|---|
| S-01 | 3 | yes | happy path first |
-->
