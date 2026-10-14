# Conventions: sizing (BA, Team Lead, developer, reviewer)

Numeric limits are defaults; read the real values from `limits` in `.squad/config.yml`.

### Stories (BA)
- A story is a vertical slice: the user can see or use something, however small.
- At most `limits.story_max_ac` (default 5) acceptance criteria. More means split.
- A story needing more than `limits.story_max_tasks` (default 5) tasks goes back to the BA.
- Preferred splitting patterns: by workflow (happy path first, errors/edge cases later), by
  CRUD operation, by business rule, by user role, by data type or channel, simple version first.

### Tasks (Team Lead)

| Size | Description | PR limit (excluding tests, lockfiles, generated files) |
|---|---|---|
| `XS` | Config, one function, one field | ≤ 50 changed lines, ≤ 3 files |
| `S` | One logical unit: endpoint, component, migration | ≤ 150 lines, ≤ 6 files |
| `M` | Maximum allowed | ≤ 300 lines, ≤ 10 files |

- Target XS and S. M only when no sensible split exists, with a `Why not smaller` section.
- One task does **one thing** in **one layer** (schema, service, API, UI, job), unless splitting
  would leave dead or untestable code.
- Every task is **independently mergeable**: CI green, nothing broken. Unfinished work sits
  behind a feature flag or stays unwired.
- Every task has its own Definition of Done, verifiable by tests.
- Suggested order: data/schema → logic/service → API → UI → wiring/feature flag → e2e.
