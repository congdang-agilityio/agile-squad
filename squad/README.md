# squad

The `squad` plugin of [agile-squad](https://github.com/congdang-agilityio/agile-squad): a
software team for Claude Code (PM, BA, Team Lead, developers, reviewer, QA, DevOps, reporter)
that works through a GitHub Projects board.

Full documentation, with a diagram of who does what:
[English](https://github.com/congdang-agilityio/agile-squad/blob/main/README.md) ·
[Tiếng Việt](https://github.com/congdang-agilityio/agile-squad/blob/main/README.vi.md)

Quick start, in a clone of your repository:

| Command | What it does |
|---|---|
| `/squad:setup` (or `/squad:setup quick`) | board, labels, config, branch protection, deploy workflow (quick: no deploys) |
| `/squad:ba` | requirements → clarifying questions → GATE 1 → stories → GATE 2 |
| `/squad:run scope=#<epic>` | the team works: plan, develop in parallel, review, merge, QA, deploy to GATE 3 |
| `/squad:fix "<small change>"` | one small task without the requirement flow |
| `/squad:report` · `/squad:doctor` | progress report · setup check |
