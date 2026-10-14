<!-- Task issue body. Created by the Team Lead with:
       issue.sh create task "<title>" - --parent <story> --priority <P> --size <XS|S|M> <<'EOF' … EOF
     Title: imperative, one thing, e.g. "Add users table migration".
     scripts/waves.sh and scripts/pr.sh parse the "Layer", "Serial", "Depends on" lines and the
     "Files (expected)" list: keep their exact form. The "Depends on" line holds only the
     dependency issue numbers: any other #number on it is read as a dependency. Everything in English. -->
- **Story:** #<story>
- **Layer:** schema | service | api | ui | job | config | infra | test
- **Size:** XS | S | M (~<lines> changed lines, <files> files, excluding tests)
- **Complexity:** low | medium | high (<one-line reason>; picks the model, see plan skill)
- **Serial:** no | yes (<reason: database migration, dependency change, shared routing/config, CI/build>)
- **Depends on:** none | #<task>, #<task>

## Goal
<One sentence: the single thing this task delivers.>

## Out of scope
- <What this task deliberately does not do, and which task does it.>

## Files (expected)
- `<path/to/file.ext>` (new | edit, ~<lines> lines)
- `<path/to/dir/>` (new files under this directory)

## Definition of Done
- [ ] <Observable result, verifiable by a test>
- [ ] Tests: <which tests are added: unit/integration/e2e, and what they assert>
- [ ] Lint and tests green; independently mergeable (unfinished parts unwired or behind a flag)

## Acceptance criteria covered
- <Story AC name(s) this task delivers, or "none (enabler for #<task>)">

## Why not smaller
<Only for size M: why no sensible split exists. Delete this section for XS and S.>

## Notes
- <Technical hints for the developer: existing code to reuse, conventions, risks. No new scope.>
