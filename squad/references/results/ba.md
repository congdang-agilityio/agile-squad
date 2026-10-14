# Result statuses: `ba`

Common fields and rules: `references/agent-output.md`.

| Status | Meaning | `next` | Extra fields |
|---|---|---|---|
| `questions_ready` | Analysis written, questions waiting for the stakeholder | `ask_stakeholder` | `slug`, `open` (count), `batch` (list of Q-IDs to ask now) |
| `needs_source` | A source cannot be read (login, scan, broken link) | `ask_stakeholder` | `slug`, `missing` (list of what is needed) |
| `clear` | No `open` or `answered` questions remain | `gate_1` | `slug`, `understanding_file` |
| `stories_ready` | PRD and stories drafted | `gate_2` | `slug`, `stories` (count), `prd_file`, `stories_file` |
| `blocked` | Cannot continue | `ask_stakeholder` | — |
