# agile-squad

A Claude Code plugin that works as a software team. You talk to one PM; the PM runs a BA, a
Team Lead, developers, a reviewer, QA, DevOps and a reporter as subagents, and every
requirement, task, PR, bug and release lives on a GitHub Projects board.

```
/plugin marketplace add congdang-agilityio/agile-squad
/plugin install squad@agile-squad
```

Then, in a clone of your repository: `/squad:setup`, describe a feature and run `/squad:ba`,
or fix something small with `/squad:fix "<what to change>"`.

- Plugin documentation: [`squad/README.md`](squad/README.md)
- Design decisions: [`docs/decisions.md`](docs/decisions.md)
- Test logs of each build phase, run against a real sandbox project:
  [`docs/squad-tests/`](docs/squad-tests/)
- The original build plan: [`plan.md`](plan.md)

## Status

Version 0.2.0. Tested end to end on one Node/Next.js project with GitHub Actions and Railway
(three releases, two developers in parallel, quick-lane fixes). GitHub Projects only; see
"Limits" in the plugin README.

## License

MIT, see [LICENSE](LICENSE).
