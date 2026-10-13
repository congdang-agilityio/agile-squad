<!-- Dispatch plan. The Team Lead posts it as a comment on the epic (gh issue comment <epic>
     --body-file - <<'EOF' … EOF). The board's Wave field is the source of truth; this comment
     explains it. Waves and serial reasons come from `waves.sh plan` output, not from guessing. -->
## Dispatch plan · <YYYY-MM-DD> · stories #<n>, #<n>

- **Developers in parallel:** <parallel.max_parallel_dev> (slots dev-1 … dev-<n>)
- **Tasks:** <count> (XS <n> · S <n> · M <n>) · **Waves:** <first>–<last>

| Wave | Tasks (slot) | Why grouped / serialized |
|---|---|---|
| <w> | #<n> <short title> (dev-1), #<n> <short title> (dev-2) | independent, no shared files |
| <w> | #<n> <short title> (dev-1) | serial: <reason from waves.sh serial_reasons> |

### Dependencies
- #<task> → #<task>: <why>

### Conflict risks
- <Files or areas two waves both touch, and how the order avoids conflicts.>
- <Tasks whose PR may need a rebase after an earlier merge.>

### Not planned
- <Stories returned to the BA (story_too_big), tasks waiting on unplanned dependencies, open questions.>
