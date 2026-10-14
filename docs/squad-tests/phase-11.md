# Phase 11: guard hook, tests, evals, per-role conventions, quick setup — test log

Date: 2026-10-15 · Plugin version 0.3.0

| Item | Evidence |
|---|---|
| Guard hook | 22 unit tests (`tests/guard.test.sh`); live in Claude Code 2.1.299: `git push origin main` blocked ("squad guard: pushing to main is not allowed…"); `--agent squad:developer` writing `package.json` in the main checkout blocked, file not created |
| Script tests + CI | `tests/run.sh`: 65 tests (lib, guard, next on a fake board, waves, pr-size, doctor), all pass; shellcheck `-S warning` clean; `.github/workflows/ci.yml` (shellcheck, SKILL.md ≤150 lines, plugin validate, tests on Ubuntu and macOS) |
| Per-role conventions | shared reading per dispatch: BA −46%, Team Lead −20%, developer −35%, reviewer −34%, QA −57%, DevOps −56%, reporter −59% |
| Quick-mode model | `tests/model-eval/quick-mode/RESULTS.md`: Sonnet 10/10 decisions, 10/10 JSON blocks, 10/10 English titles, $0.33 vs Opus $1.51 → `models.quick: sonnet` |
| Quick setup | `deploy.platform: none`: `next.sh` lists nothing unreleased and offers no deploys; doctor skips deploy checks (tests) |
| Behavior evals | `claude plugin eval` 5 cases: 5/5 after the GATE 1 rubric fix (the PM correctly went back to clarifying when the BA raised new questions); about $2.24 per pass |
| Docs | README.md (English) and README.vi.md (Vietnamese) with a Mermaid role diagram, rendered with mermaid-cli 11.4.2 to check the syntax; CHANGELOG.md |
