# Phase 2: PM + BA — test log

Date: 2026-10-13 · Sandbox: congdang-agilityio/squad-sandbox · Board: https://github.com/users/congdang-agilityio/projects/1
Stakeholder: Cong (answered in Vietnamese in chat; the main session acted as PM).

## Built
- `scripts/ingest.sh` (+ `scripts/ingest_fallback.py`, standard library only): converts a file
  or URL into `docs/requirements/<slug>/sources/<name>.md` with a source header, keeps the
  original in `sources/raw/`. md/txt, pdf (`pdftotext`), docx/pptx/xlsx/html (pandoc →
  markitdown → fallback), images (stub for the BA to describe), public URLs, GitHub issues/PRs.
  Exit codes: 0 ok, 2 usage, 3 missing tool, 4 login wall, 5 scanned PDF (pages exported as
  images), 6 unreadable.
- `scripts/issue.sh publish <slug>`: refuses without a `Signed-off:` line; creates the epic from
  `epic.md` and one story per `stories/S-*.md` as sub-issues in `Backlog` with priority;
  idempotent (dedupes on open issue title + type); JSON on stdout, progress on stderr.
- `skills/ba/SKILL.md` (136 lines): PM steps + BA modes `analyze | clarify | stories | revise`,
  GATE 1 (requirement sign-off), GATE 2 (story approval), mid-stream changes.
- `references/`: `requirement-analysis-template.md`, `questions-template.md`,
  `prd-template.md`, `story-template.md`; `agent-output.md` gained the BA statuses.
- Fixtures: `docs/squad-tests/fixtures/make_fixtures.py` generates the deliberately
  contradictory "TodoNow" requirement (brief.md says email-only login, meeting-notes.docx says
  Google sign-in) plus nfr.pdf, pitch.pptx, fields.xlsx and an image-only scanned.pdf.

## Acceptance
| Check | Result |
|---|---|
| `ingest.sh` reads `.md`, `.pdf`, `.docx` (also `.pptx`, `.xlsx`, public URL, GitHub issue) | PASS |
| Login-protected URL fails clearly (exit 4, "login required"); 404 → exit 6; scanned PDF → exit 5 with page images | PASS |
| BA detects the email-only vs Google conflict (C-01, both sides quoted) and raises questions | PASS |
| No story is created while any question is `open`: stories were only written after sign-off in both runs; `issue.sh publish` on an unsigned slug exits 1 ("no 'Signed-off:' line: GATE 1 not passed") | PASS |
| PM relays questions verbatim; Vietnamese answers stored in `Answer (original)` + English translation; only the BA sets `confirmed` | PASS (TodoNow 7 rounds + change round, 34 questions; user-admin 5 rounds, 35 questions) |
| Unclear answer is not guessed: "D: wpa cho phase này" → BA re-opened as Q-27; "3.C" (A or B?) → follow-up Q-21; "10.D" → follow-up Q-28 | PASS |
| After sign-off: PRD, 1 epic, ≥ 3 Given/When/Then stories, FR → Story table covering every FR, all English, in `Backlog` | PASS — TodoNow: epic #33, 32 stories #34–#65, 27/27 FRs; user-admin: epic #67, 26 stories #68–#93, 20/20 FRs |
| Requirement change at GATE 2 ("thêm đăng xuất và mật khẩu ít nhất 8 kí tự …"): `revise` returns `blocked`, clarify round (Q-33/Q-34), GATE 1 re-signed, stories revised (S-02/03/04 changed, S-29..S-32 added), GATE 2 re-approved | PASS |
| Large request "user management with CRUD, roles and CSV import" → split into 26 stories, each ≤ 5 ACs (create/read/update/block/delete, roles, CSV happy path / bad rows / size limit are separate stories) | PASS |
| Requirement docs merged through a PR, never pushed to `main` | PASS — PR #66 (todonow), PR #94 (user-admin), squash-merged |
| Re-running `publish` creates no duplicates | PASS (both slugs) |

Not tested: a real private Google Doc link (the login-wall detection was tested on a
login-redirecting URL).

## Findings fixed during testing
1. **Claude Code blocks subagent writes to `.md` files named `report*`, `summary*`,
   `findings*`, `analysis*`.** The BA files are `requirements.md` and `understanding.md`; the
   skill warns about the names. Phase 7 (reporter) must avoid these prefixes too.
2. **`${CLAUDE_PLUGIN_ROOT}` is substituted in skill/agent text but is not an environment
   variable in Bash, and Bash permission rules reject commands with shell variables.** The BA
   calls `ingest.sh` once per source with literal paths (no loops, pipes or variables).
3. **Re-signing GATE 1 after a change was underspecified:** the BA's Status line stayed
   "needs sign-off" and `revise` would block again. The skill now says: add
   `Re-signed (<change>): <date> by <name>` below `Signed-off:`, update the Status line, and
   `revise` only blocks on changes not covered by a `Re-signed` line.
4. **Sign-off with a missing input:** the stakeholder confirmed user-admin without giving the
   contact address for admin-action emails. Recorded as an open input in `requirements.md` and
   `stakeholder-notes.md`; the BA marked only S-23 as depending on it.

## Environment limits found (affect later phases)
- **Auto mode blocks `gh pr merge` as "Merge Without Review"**, even after the stakeholder
  approved at GATE 2. The stakeholder granted the permission for this session. The Team Lead
  merge step (D-1, Phases 3–4) needs an allow rule such as `Bash(gh pr merge:*)` in the target
  repo's `.claude/settings.json`; `setup` should offer to add it. Branch protection on `main`
  still applies.
- The BA's prose summary can be slightly off (it reported 8 P0 stories for user-admin; the
  files and board have 7). Gates should present numbers read from the files, not from the
  summary.

## Commands used
Headless BA runs from the sandbox clone (`P=<repo>/squad`):
`claude -p --plugin-dir $P --allowedTools Agent Read Grep Glob Write Edit "Bash($P/scripts/ingest.sh:*)" < prompt.txt`
with a prompt that dispatches `squad:ba-analyst` with `mode=<mode> slug=<slug> config=.squad/config.yml`.
