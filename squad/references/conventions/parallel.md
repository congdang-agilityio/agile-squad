# Conventions: parallel development (Team Lead, PM)

Read the real values from `parallel` in `.squad/config.yml`.

- Tasks share a wave **only if** they do not depend on each other **and** their
  `Files (expected)` lists do not overlap.
- Always serialized (alone in their wave relative to the same area): database
  migrations/schema, dependency changes (`package.json`, lockfiles), shared routing/config
  files, CI/build config.
- At most `parallel.max_parallel_dev` developers at once; a wave never has more tasks.
- Waves are computed by `scripts/waves.sh` (never by hand) and stored in the `Wave` field;
  the Team Lead explains them in a dispatch plan comment on the epic.
- Each developer slot gets its own worktree, port (`port_base + slot`) and test database
  (`<test_db_prefix>_<slot>`).
- Developers rebase on the latest `main` before opening a PR. When a merge makes another open
  PR conflict, the Team Lead labels it `needs-rebase`; the PM dispatches a developer in
  `rebase` mode.
- While `parallel.max_open_prs` or more PRs wait in `In Review`, the PM dispatches no new
  developers until the queue drains.
