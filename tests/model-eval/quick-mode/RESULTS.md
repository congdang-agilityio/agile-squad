# Quick-mode model comparison (2026-10-15)

Target: the squad sandbox (Next.js + Prisma to-do app), 10 requests in Vietnamese
(`cases.tsv`: 5 that fit the quick lane, 5 features or vague requests), dry run, read-only.

| Run | Model | Right decision | Fenced JSON result block | English title | Cost (10 runs) |
|---|---|---|---|---|---|
| 1 (agent rule: "end with the result block") | Sonnet | 10/10 | 1/10 | 9/10 | $0.41 |
| 1 | Opus | 10/10 | 10/10 | 10/10 | $1.51 |
| 2 (agent rule spells out the fenced JSON and English) | Sonnet | 10/10 | 10/10 | 10/10 | $0.33 |

Sonnet found the same files and tests to change as Opus (e.g. the four test references of
the sign-up label). Decision: `models.quick: sonnet`, and every agent definition now states
the JSON-and-English rule explicitly.
