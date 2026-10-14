# Phase 9 (after the final review): quick lane, cost control, doctor — test log

Date: 2026-10-14 · Sandbox: congdang-agilityio/squad-sandbox · Plugin version 0.2.0

## Why
The final review found three problems with everyday use: a small change had to go through
the full BA → story → plan flow (no quick path); a story cost about $14 because every subagent
ran on Opus; and 13 README troubleshooting rows were symptoms of setup drift with no check
for them. Decisions D-11, D-12 and D-13.

## Built
| Item | Files |
|---|---|
| Quick lane `/squad:fix` | `skills/fix`, Team Lead `mode=quick` (`skills/plan`), QA quick check (`skills/qa`), label `quick` (`issue.sh`), `quick_planned` / `too_big_for_fix` (`agent-output.md`), Done quick tasks listed as `unreleased` (`next.sh`) |
| Model per dispatch | config `models` (role × size), `next.sh` adds `model` to each action (Size read from the board; unknown size gets the M model), run skill passes it to the Agent call |
| Token budget | config `budget.max_tokens_per_run`, `/squad:run max-tokens=N`, PM sums each subagent's reported `subagent_tokens`; the end-of-run summary shows tokens per role |
| Doctor | `scripts/doctor.sh` (16 checks, read-only, `--offline`), `skills/doctor` (proposes fixes, applies after a yes), setup ends with it, the run loop calls it when `next.sh` fails |

## Tests
| Test | Result |
|---|---|
| `doctor.sh` without a config | `config` fail with fix "run /squad:setup", exit 1 |
| `doctor.sh` on the sandbox (8.6 s) | 12 ok, 1 fail (label `quick` missing: new in this phase), 2 warn: `.squad/reports/` not ignored and no `gh pr merge` allow rule (both real gaps in the sandbox) |
| `doctor.sh --offline` | local checks only, exit 0 |
| `next.sh` with `models` | `dev #118` got `model: sonnet` (XS) |
| **A** `/squad:fix` small change (Vietnamese request: login tab title) | PASS. Team Lead created #184 (XS, `quick`, request quoted verbatim, DoD starts with a failing test) → developer PR #185 → review PASS in 1 round → Team Lead merge → QA quick check on main (unit, e2e, running app) → Done. All four dispatches on Sonnet. 22 min, **$1.51**, ~165k subagent tokens. Main session: 5 Agent, 5 `next.sh`, 1 Skill: no code work. #184 listed as `unreleased`; the PM asked for a milestone instead of creating one |
| **B** `/squad:fix` too big ("dark mode with a settings screen") | PASS. Team Lead returned `too_big_for_fix`: no task created, five product questions, suggested `/squad:ba`. 40 s, **$0.37** |

Compare: the full flow cost $10.57–$37.72 per run of one to three stories (phase 7).

## Not exercised end to end
- The token budget stop (`max-tokens`) was not hit in a live run: run A used ~165k of the
  2,000,000 default. The PM did sum and report tokens per role, which the stop rule uses.
- QA could not run the WebKit e2e project locally (browser not installed on this machine);
  CI ran it green.

## Open items
- Team Lead `mode=quick` itself has no `models` entry and runs on the agent default (Opus):
  ~55k of run A's 165k tokens. Kept: judging whether a request fits the quick lane is the
  decision that protects scope.
