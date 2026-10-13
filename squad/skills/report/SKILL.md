---
name: report
description: "Progress report for the stakeholder: collect delivery metrics from the board and GitHub with metrics.sh (period or milestone), have the reporter draft a report with a 5-line plain-language summary and a metrics table where every number comes from the script, then publish it as a type:report issue and summarize it in the stakeholder's language. Use when the stakeholder asks how things are going, at the end of a run, or on a schedule."
---

# squad: report (numbers from the script, story for the stakeholder)

Paths written as `references/…`, `templates/…` or `scripts/…` are inside `${CLAUDE_PLUGIN_ROOT}` (the squad plugin folder), not the target repository.

Two roles:
- **Reporter** = the `reporter` subagent, dispatched by the PM with
  `period=<since>..<until> | milestone=<title> config=.squad/config.yml`.
- **PM** = the main session: publishes the report and tells the stakeholder.
When invoked directly (`/squad:report [since|milestone]`), the PM dispatches the reporter.

Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/metrics.sh`, `issue.sh`. Template:
`references/report-template.md`. Default period: the last 7 days.

## Reporter
1. Run `metrics.sh --since <date> [--until <date>]` or `metrics.sh --milestone "<title>"`
   once and keep its JSON. **Every number in the report is copied from it.** Never count,
   estimate or recompute by hand; a value the JSON lacks is "n/a".
2. Read context for the words (not the numbers): delivered stories and tasks
   (`gh issue view`), released tags (`gh release view`), open bugs, flagged items, the next
   waves (`board.sh list Todo`).
3. Write `.squad/reports/<YYYY-MM-DD>.md` from the template (create the folder if needed; it
   is a local draft, the issue is the record). The 5-line summary is for a non-technical
   reader: what users can do now, quality, the biggest risk, and decisions needed.
4. Check before returning: every number in the file appears in the metrics JSON; no issue
   numbers or jargon in the summary; English only.
5. Return `report_ready` with `file` and `period` (or `failed` if the script failed).

## PM
1. Read the draft. Publish it:
   `issue.sh create report "Status <YYYY-MM-DD>: <period or milestone>" .squad/reports/<YYYY-MM-DD>.md`
   (reports are not added to the board).
2. Tell the stakeholder, in their language, the 5 summary lines (translated) and the issue
   link. Ask the decision questions from line 5 explicitly.
3. Answers are new information: record them (`ba` notes or a comment on the issue) before
   acting on them.

## Never
- Put a number in the report that is not in the metrics output, or round it differently.
- Edit the board, code or issues other than creating the report issue.
- Name a file `report*`, `summary*`, `findings*` or `analysis*` (Claude Code refuses subagent
  writes to such names); use the date.
