# Phase 8: Polish — test log

Date: 2026-10-14

## Done
- `squad/README.md` (English): what the team does, requirements, installation (marketplace or
  `--plugin-dir`), first run (`/squad:setup`), day-to-day workflow and gates, configuration,
  troubleshooting (drawn from the problems met in phases 3–7), layout, v1 limits.
- `.claude-plugin/marketplace.json` at the repository root (marketplace `cff-skills`, plugin
  `squad` from `./squad`), so `/plugin marketplace add <owner>/<repo>` +
  `/plugin install squad@cff-skills` works once the repository is on GitHub.
- BA skill: every story that adds a screen states how the user reaches it (lesson from the
  sandbox: the sign-up screen had no way in from the home page).
- Plan skill and Team Lead agent descriptions name the `rewave` and `milestone` modes; the
  reporter description points to `.squad/reports/`.
- `docs/decisions.md`: D-7 (report drafts local, issue is the record), D-8 (GATE 3 holds only
  the deploy lane), D-9 (releases named by the stakeholder), D-10 (parallel lanes, rewave).

## Final review
| Check | Result |
|---|---|
| Every `SKILL.md` ≤ 150 lines | PASS: ba 140, setup 124, plan 108, dev 88, run 80, qa 73, deploy 72, review 59, report 46 |
| Descriptions specific enough to trigger the right skill | PASS: each says what it does, its modes and when to use it ("Use when …") |
| No hard-coded repository names | PASS: `grep -ri 'congdang\|squad-sandbox\|todonow\|code-for-food\|/home/\|/tmp/claude'` in `squad/` finds nothing (only a generic `*.up.railway.app` example in `templates/deploy.yml`) |
| Agent tool lists match plan 2.1 | PASS: ba-analyst Read/Grep/Glob/WebFetch/Bash/Write; team-lead Read/Grep/Glob/Bash; developer Read/Write/Edit/Bash; reviewer Read/Grep/Glob/Bash (no Write/Edit); qa-tester Read/Grep/Glob/Bash (no Write/Edit); devops Read/Bash; reporter Read/Bash/Write. Bash scopes are stated in each agent's `Limits:` line. Deviations are decisions: Team Lead merges (D-1), reporter writes `.squad/reports/` (D-7) |
| Manifests | PASS: `claude plugin validate squad` and `claude plugin validate .` (marketplace) |
| Scripts | PASS: `bash -n` on every script, `--help` works for all ten, `ingest_fallback.py` compiles |

## Not exercised
- Installing through the marketplace (`/plugin marketplace add`): the repository has no GitHub
  remote yet, and installing would change the user's global plugin set. The manifests
  validate; every test in phases 0–7 loaded the plugin with `--plugin-dir`.
