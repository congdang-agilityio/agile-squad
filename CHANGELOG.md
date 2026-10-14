# Changelog

All notable changes to agile-squad. Versions follow [Semantic Versioning](https://semver.org);
the plugin version lives in `squad/.claude-plugin/plugin.json` and the marketplace entry.

## [0.3.0] - 2026-10-15

### Added
- **Guard hook** (`hooks/hooks.json`, `scripts/guard.sh`): blocks pushes to `main`,
  `gh pr merge --admin` and `gh pr review --approve`; developers may write only inside their
  worktree, the BA only under `docs/requirements/`, the reporter only under `.squad/reports/`,
  and the reviewer, QA, Team Lead and DevOps never edit files. Active only in repositories
  with `.squad/config.yml`.
- **Test suite** (`tests/`, 63 tests) with a fake `gh`: config parsing, the guard hook,
  `next.sh` decisions on a fake board, waves, PR sizing, doctor. CI runs shellcheck, the
  tests on Linux and macOS, and plugin validation.
- **Behavior evals** (`squad/evals/`, `claude plugin eval`): quick-lane routing, refusing a
  feature in the quick lane, GATE 1 needs an explicit yes, the doctor fix for lost ids, review
  is delegated to the reviewer subagent.
- `/squad:setup quick`: board, labels and commands in about two minutes, deploys off
  (`deploy.platform: none`).
- `models.quick` in the config: the model for the Team Lead's quick-lane decision.

### Changed
- Conventions and result statuses are split by role (`references/conventions/`,
  `references/results/`): each subagent reads 20–59% less shared text per dispatch.
- Agents must end with a fenced JSON result block in English (a Sonnet eval showed 1 in 10
  blocks in the right format before this rule).

## [0.2.0] - 2026-10-14

### Added
- `/squad:fix` quick lane: one XS/S task without the BA, story gates or story planning.
- `models` in the config: a model per role and task size; `next.sh` puts it on each action.
- Token budget for `/squad:run` (`max-tokens`, `budget.max_tokens_per_run`).
- `/squad:doctor` and `scripts/doctor.sh`: read-only setup checks with a fix per problem.
- `release.sh draft | deploy | wait | publish` for DevOps.
- `commands.build` and `commands.start` for QA.

### Fixed
- 14 high-severity findings of two independent reviews, among them: a blocked developer kept
  its slot forever; a failed smoke test made the milestone unreleasable; GATE 1/2 were not
  reported by `next.sh`; `merge.require_ci: false` was ignored; macOS incompatibilities
  (BSD `sed`/`date`, bash 3.2).

## [0.1.0] - 2026-10-14

### Added
- First release: PM orchestrator with BA, Team Lead, developer, reviewer, QA, DevOps and
  reporter subagents on a GitHub Projects board; three human gates; parallel developers in
  worktrees; GitHub Actions deploys to Railway with production approval.

[0.3.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/congdang-agilityio/agile-squad/releases/tag/v0.1.0
