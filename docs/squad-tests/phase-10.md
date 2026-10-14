# Phase 10: final review and publishing — test log

Date: 2026-10-14 · Plugin version 0.2.0 · Published as `congdang-agilityio/agile-squad`

## Review
Two fresh read-only reviewers ran in parallel:
- **Consistency** (skills ↔ agents ↔ references ↔ scripts ↔ README): 27 findings, 8 high.
- **Script bugs** (bash/jq/python, macOS portability): 25 findings, 6 high.

Fixed: all 14 high findings and most medium and low ones (decision D-14). Highlights:
| Finding | Fix |
|---|---|
| Blocked developer kept its slot forever | `dev` gives the slot back (label `blocked`, Agent cleared, `Todo`) |
| Failed smoke test made the milestone unreleasable | draft deleted; P0 bug gets the milestone; P0/P1 bugs always in scope |
| GATE 1/2 never reported by `next.sh` | `gate_1`, `gate_2` actions; the run stops at them |
| Rebase without a slot, rework without a PR number | `next.sh` assigns a free slot / adds `pr` |
| Team Lead "rework" rejection lost its reasons and was unbounded | `pr.sh reject … rework` labels `review:changes`, bumps Attempts |
| QA and Team Lead lacked tools their procedures need | agent Limits updated |
| `merge.require_ci: false` ignored | `cfg` keeps `false`; CI lookup errors now block |
| `release.sh finish` could close a milestone without releasing | lookups on their own line (errexit) |
| `issue.sh publish` died silently without a Priority line | `|| true` |
| macOS: `sed {…p}`, `date -d`, `\t` in brackets, bash 3.2 | BSD forms, python dates, `[[:blank:]]`, bash 4 guard |
| `pr-size.sh` failed right after a PR opened | body/branch fallback; numstat parsed by jq |
| DevOps could not write multi-line notes or poll (observed in the v0.4.0 release) | `release.sh draft/deploy/wait/publish` |
| Metrics fetched label events of every merged PR | only the PRs the report counts |

Not fixed (documented): listing caps (projects 100, open PRs 200, issues 500), a rewave that
file overlaps cannot improve (rewave at most once per run), ingest.sh edge exit codes.

## Checks after the fixes
| Check | Result |
|---|---|
| `bash -n` and `--help` on all 11 scripts | pass |
| `next.sh` on the sandbox | same actions as before; `dev #118` now carries `pr: 121`; no false `gate_1`/`gate_2` |
| `release.sh wait <run> production` on the v0.4.0 run | `{run_status: completed, conclusion: success}` |
| `release.sh gate "v0.4.0 …"` | ok, no blocking bugs |
| `pr-size.sh 185`, `pr.sh check 185` | sizes as before; check reports "PR is not open" (merged) |
| `doctor.sh` | 0 fail; warns: `commands` (new build/start not set in the sandbox), `.gitignore`, merge allow rule |
| `metrics.sh --milestone "v0.4.0 …"` | 13 PRs, 1 min 53 s |
| `cfg` with `require_ci: false`, `issue_args "#36,#63" 70` | `false`; `36 63 70` |
| `claude plugin validate` (marketplace and plugin) | pass |

`release.sh draft`, `deploy` and `publish` were not run live: the sandbox's Railway project
was deleted at the stakeholder's request before this phase.

## Publishing
- Marketplace renamed `agile-squad`; install with
  `/plugin marketplace add congdang-agilityio/agile-squad` and `/plugin install squad@agile-squad`.
- Root README and MIT LICENSE added; plugin manifest has `homepage`/`repository`.
- Railway project `squad-sandbox-todonow` deleted (stakeholder decision); the GitHub sandbox
  repository is kept as a record.
