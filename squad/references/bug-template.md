<!-- Bug issue body. Created by QA with:
       issue.sh create bug "<symptom in a few words>" - --parent <task> --priority <task priority> <<'EOF' … EOF
     It is a sub-issue of the task (or story) that failed, starts in Todo, and is planned and
     fixed like a task (branch fix/<bug>-<slug>). The first five lines use the task-template
     format so waves.sh can schedule it; the Team Lead corrects them when planning.
     Title: the observable symptom, e.g. "Readiness endpoint lacks X-App-Version header".
     Everything in English; quote error output verbatim. -->
- **Story:** #<story>
- **Layer:** <best guess: api | ui | service | …>
- **Size:** XS (estimate; the Team Lead confirms)
- **Serial:** no
- **Depends on:** none

## Found in
#<merged PR> (task #<task>) · main @ `<short sha>` · QA attempt <n>

## Failed criterion
<The exact acceptance criterion or DoD item, quoted from the task or story.>

## Steps to reproduce
1. <From a clean checkout of main: commands, URL, inputs>
2. …

## Expected
<What the criterion requires.>

## Actual
<What happened. Paste the response, test output or log lines verbatim (trim to what matters).>

## Evidence
- <Command run and its exit code, test name, screenshot path or log excerpt>

## Files (expected)
- `<path>` (suspected location of the fix; the Team Lead confirms)

## Definition of Done
- [ ] A test that reproduces this bug fails before the fix and passes after it
- [ ] The failed criterion above is met; lint and tests green
