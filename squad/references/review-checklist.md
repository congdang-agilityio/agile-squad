# Review checklist

The Reviewer goes through every section for every PR. Report only findings backed by evidence:
`path:line`, what is wrong, why it matters, and a concrete fix. No style opinions that the
linter does not enforce, no "consider" without a reason.

## Severity
| Severity | Meaning | Blocks PASS? |
|---|---|---|
| `blocker` | Wrong behavior, an AC/DoD item not met, security hole, data loss, broken build or tests, missing tests for new logic | yes |
| `should-fix` | Real defect risk or maintainability problem that will cost more later (unhandled edge case, misleading name in a public API, duplicated logic) | yes |
| `nit` | Minor, optional | no |

## 1. Scope and size
- The PR does exactly what the task says: one thing, one layer. Nothing from other tasks, no
  "while I'm here" refactors, no new features. Changed files match `Files (expected)` (small
  necessary extras are fine and should be explained in the PR body).
- `pr-size.sh` is within the task's size. Over the limit or doing two things → `needs-split`.
- Title `<type>: <summary> (#<issue>)`, body has `Closes #<issue>` and the ticked checklist.

## 2. Acceptance criteria and Definition of Done
- Every DoD item and every AC the task claims to cover is implemented **and** has a test that
  would fail without the change. Map each one to a test name in your notes.
- Behavior matches the story's wording, including error messages and edge cases it lists.

## 3. Correctness
- Logic, branches, off-by-one, null/undefined/empty inputs, time zones and dates, async errors
  and promise handling, concurrency (double submit, race on unique keys).
- Error paths return the documented status/message; nothing is silently swallowed.

## 4. Security
- **Every external input is validated** (request body, query, params, headers, cookies, form
  fields, file contents): type, presence, length/range, format. Invalid input is rejected
  with a clear 4xx, never passed on. Missing validation is a `blocker`.
- No injection: parameterized queries/ORM only, no string-built SQL/shell/HTML; output encoded.
- AuthN/AuthZ: protected routes check the session; users reach only their own data.
- Secrets: none in code, tests, logs or fixtures; passwords hashed with the agreed algorithm,
  never logged or returned.
- Cookies/sessions: `HttpOnly`, `Secure` in production, `SameSite`; no sensitive data in URLs.

## 5. Tests
- Tests are meaningful (assert behavior, not implementation details), deterministic, isolated
  (own test database per slot, no shared state, no real network), and fast.
- No tests deleted, skipped (`.skip`, `xit`) or weakened to make the build pass.
- CI is green on the head commit.

## 6. Conventions and quality
- Follows the repo's existing structure, naming and patterns; Conventional Commits.
- No dead code, debug output, commented-out blocks or TODOs without an issue number.
- User-facing text goes through the translation files (vi and en) when the app is bilingual.
- Database: migrations are additive and reversible where possible; indexes for new lookups.

## 7. Verdict
- Any `blocker` or `should-fix` → `Verdict: CHANGES`.
- Only `nit`s or nothing → `Verdict: PASS` (list the nits; the developer may ignore them).
