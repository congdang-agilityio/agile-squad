<!-- Stakeholder report. The reporter writes it to .squad/reports/<YYYY-MM-DD>.md from
     scripts/metrics.sh output; the PM publishes it as a type:report issue (readable on a
     phone). Every number comes from the metrics JSON: copy it, never estimate or round
     differently. A number the JSON does not have is written "n/a". English only. -->
# Status <YYYY-MM-DD> · <period or milestone>

## Summary
<Exactly 5 short lines for a non-technical reader. No jargon, no issue numbers.>
1. **Progress:** <what moved forward vs. the plan, e.g. "2 of 5 planned features are live">
2. **Delivered:** <what users can now do; "nothing released" if so>
3. **Quality:** <bugs found/fixed, anything that failed>
4. **Risks:** <the biggest risk to the plan, or "none">
5. **Decisions needed from you:** <a question for the stakeholder, or "none">

## Metrics
| Metric | Value |
|---|---|
| Stories delivered | <delivered.stories> |
| Tasks and bugs delivered | <delivered.tasks_and_bugs> |
| PRs merged (task PRs / other) | <prs.merged> (<prs.task_prs> / <len(prs.other_prs)>) |
| Average / largest task PR (changed lines, excl. tests and lockfiles) | <prs.avg_changed_lines> / <prs.max_changed_lines> |
| PRs sent back by review | <len(prs.sent_back_by_review)> |
| PRs that needed a rebase | <len(prs.needed_rebase)> |
| Bugs opened / closed | <bugs.opened> / <bugs.closed> |
| Open bugs (P0 / P1 / P2 / P3) | <bugs.open_now.*> |
| First-time QA pass rate | <qa.passed_first_time> of <qa.tasks_delivered> (<qa.first_time_pass_rate as %>) |
| Average / median cycle time (start → Done) | <cycle_time_hours.avg> h / <cycle_time_hours.median> h (n = <n>, excluded: <excluded>) |
| Most developers working at the same time | <parallelism.max_concurrent_devs> |
| Deploy runs (success / failure) | <deployments.runs> (<by_conclusion.success> / <by_conclusion.failure>) |
| Releases | <deployments.releases> |

## Released
- <tag>: <one line per feature, plain language, with the story issue number>

## Notable bugs
- #<n> <title>: <status, impact in one line>

## Needs attention
- needs-human: <issues or "none"> · needs-split: <…> · blocked: <…>

## Board now
| Type | Backlog | Todo | In Progress | In Review | QA | Done | Released |
|---|---|---|---|---|---|---|---|
| Stories | … |
| Tasks | … |
| Bugs | … |

## Next period
- <What the team will work on next, from the board: the next waves, stories waiting for planning,
  open questions. No promises the board does not support.>
