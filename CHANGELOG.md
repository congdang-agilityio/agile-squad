# Changelog

All notable changes to agile-squad. Versions follow [Semantic Versioning](https://semver.org);
the plugin version lives in `squad/.claude-plugin/plugin.json` and the marketplace entry.

## [0.6.2] - 2026-10-16

### Fixed
- **Guard: false positives on `git push`** (#2). A push from a task worktree reached with
  `cd <worktree> && … && git push -u origin HEAD` was blocked as a push from `main`, because
  the guard checked the session's directory and ignored the `cd`. It now follows `cd` and
  `pushd` through the command. Text in heredocs and quoted arguments (an issue body that
  mentions `git push`) is no longer treated as a command. Pushes to `main` stay blocked.
- **Items left out of GitHub's project listing** (#3). GitHub's item listing sometimes omits
  items that are on the board, so `next.sh` treated the tasks under them as out of scope
  without a word. `next.sh` now reads each item's ancestors from the issue itself (a task
  stays in scope even when its story is missing from the listing) and notes the missing item.

### Added
- `board.sh missing`: issues with an item on the board that the listing leaves out.
  Doctor check `board_items` reports them.
- `board.sh relink <issue>...`: deletes and re-adds those items, restoring Status, Priority,
  Size, Wave, Agent and Attempts, and checks that they are listed again (a second round when
  needed). Doctor asks for an explicit yes before running it.

## [0.6.1] - 2026-10-16

### Fixed
- **A released claim kept winning for 10 minutes.** `board.sh release` cleared only the Agent
  field and left the claim comment, so the next claim on the item (the reviewer after the
  developer, QA after the merge, the developer back for rework) lost the race to it and
  returned `claimed_elsewhere` until the comment was 10 minutes old. Release now marks this
  machine's claim comments `· released <time>` (all of them with `--force`), so they no
  longer count; the "Started by" prefix and creation time stay, so metrics are unchanged.
- Claim comments are filtered by `created_at` as well: GitHub's `since` filters by
  `updated_at`, so an old claim comment edited later came back into the race window.

## [0.6.0] - 2026-10-15

### Added
- **Several machines on one board.** `board.sh claim <issue> <who>`: before a developer, QA
  or review run starts on an item it posts a "Started by <who>@<machine> · claim" comment;
  of the claims of the last 10 minutes the earliest wins, the loser deletes its comment and
  returns `claimed_elsewhere`. The Agent field holds `<who>@<machine> <time>`;
  `board.sh release` clears it. `next.sh` does not offer QA, review, rebase or merge for an
  item another worker holds, and reports claims older than `parallel.claim_ttl_minutes`
  (default 120) as stale.
- Machine names (`SQUAD_HOST`, default the short hostname); developer slots are per machine
  (`dev-1@laptop-a`), so `max_parallel_dev` counts per machine.
- Doctor checks that the account can push to the repository and change the board, and shows
  the machine name.
- README (EN, VI) and the field guide: "Joining an existing squad project".

### Fixed
- Two machines running `/squad:run` on the same scope could both take the same task (a
  developer saw the other machine's identical slot name as its own resumed run).

## [0.5.0] - 2026-10-15

### Added
- **Model routing by complexity.** The Team Lead gives every task a `Complexity`
  (`low`/`medium`/`high`) judged by risk, not size: auth, permissions, money, personal data,
  security, migrations, concurrency and public API contracts are high even when small.
  `next.sh` picks dev, review and QA models by complexity (falling back to Size for older
  tasks) and adds `model_reason` to each action. Unlike a run-time classifier, this costs no
  extra model call: the Team Lead already reads the code when planning.
- **Escalate on retry** (`models.escalate_on_retry`, default on): a task sent back by review
  or QA runs one tier higher (haiku → sonnet → opus) on its next attempt.

## [0.4.0] - 2026-10-15

### Added
- **DevOps runs Railway with the Railway CLI** under the stakeholder's own `railway login`
  (OAuth): `scripts/railway.sh` (`check`, `status`, `logs`, `deployments`, `vars` names only,
  `deploy`, `set-var`, `add-db`, `config`, `redeploy`, `rollback`). No Railway token in
  GitHub or the repository.
- **Infra tasks** (label `infra`): the Team Lead plans platform work (databases, variables,
  service settings such as the pre-deploy migration command); `next.sh` routes them to DevOps.
- DevOps modes `infra` and `rollback`; statuses `infra_done`, `needs_approval`,
  `rollback_proposed`, `rolled_back`.
- Guard: subagents reach Railway only through `railway.sh`; only DevOps may change it.
- Doctor checks the Railway CLI, the login and the project.
- `railway.sh errors <env> --since <t>`: app error lines and HTTP 5xx in a period, grouped.
  DevOps scans after every staging and production deploy, and in the new `mode=health`
  (`/squad:deploy health`, e.g. every 6 hours with `/loop`), filing or updating bugs with a
  priority (P0 main flow down, P1 repeated 5xx/exceptions, P2 occasional).
- `railway.sh domain <env>`: the public URL, generated when missing.

### Changed
- Releases: DevOps deploys staging, then exactly the approved commit to production, with the
  CLI. GATE 3 stays on GitHub: `templates/release-gate.yml` (replaces `deploy.yml`) only
  records the approval and holds no secrets. `release.sh deploy` is now `release.sh approval`.
- Production changes need the stakeholder: the GATE 3 run (checked against the commit) for a
  release, their quoted words for infra changes and rollbacks; every change is commented on
  the issue. Secrets are refused; the stakeholder sets them with the command DevOps gives.
- Failed deploys come with build and runtime logs in the P0 bug.
- Found by the live test and fixed before release: `railway up --ci` never returns (it follows
  the running app's logs), so deploys use `--detach` and poll the deployment by id;
  `railway environment edit --service-config` applied nothing, so service settings use the
  `serviceInstanceUpdate` API; deployments show their commit from the upload message.
- Config: `deploy.railway.{project, service, environments}`, `deploy.gate_workflow`,
  `models.infra`.

## [0.3.1] - 2026-10-15

### Fixed
- Guard hook on macOS: paths through symlinks (`/var` → `/private/var`) were compared with
  git's resolved root, so legitimate writes were blocked. Found by the new macOS CI job.

## [0.3.0] - 2026-10-15

### Added
- **Guard hook** (`hooks/hooks.json`, `scripts/guard.sh`): blocks pushes to `main`,
  `gh pr merge --admin` and `gh pr review --approve`; developers may write only inside their
  worktree, the BA only under `docs/requirements/`, the reporter only under `.squad/reports/`,
  and the reviewer, QA, Team Lead and DevOps never edit files. Active only in repositories
  with `.squad/config.yml`.
- **Test suite** (`tests/`, 65 tests) with a fake `gh`: config parsing, the guard hook,
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

[0.6.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/congdang-agilityio/agile-squad/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/congdang-agilityio/agile-squad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/congdang-agilityio/agile-squad/releases/tag/v0.1.0
