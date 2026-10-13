# Phase 0: Preparation — test log

Date: 2026-10-13

## Decisions (stakeholder)
- Skill set name: **squad** (commands `/squad:<skill>`, config `.squad/config.yml`)
- Deploy target: **Railway**
- Sandbox repository: https://github.com/congdang-agilityio/squad-sandbox (private)
- Git: repository initialized at the project root; commit after each phase

## Created
- `squad/.claude-plugin/plugin.json`
- Skeleton: `skills/{setup,ba,plan,dev,review,qa,deploy,report,run}`, `agents/`, `references/`, `scripts/`, `templates/`
- `references/board-conventions.md` (plan section 3, plus language and gates)
- `references/agent-output.md` (result block and allowed statuses per role)
- 7 agents: ba-analyst, team-lead, developer, reviewer, qa-tester, devops, reporter

## Checks
- `plugin.json` parses as JSON: OK
- All 7 agent frontmatters parse as YAML; `tools` match plan 2.1: OK
- Models: reviewer and qa-tester = opus, reporter = haiku, others inherit

## Open items for Phase 1
- Verify that `${CLAUDE_PLUGIN_ROOT}` resolves inside agent bodies when installed as a plugin;
  if not, switch agents to a relative lookup.
- `yq` is not installed; scripts need a YAML reader (install `yq` or use a small built-in parser).
- `pandoc` and `markitdown` are not installed (needed by `ingest.sh` in Phase 2).
- `congdang-agilityio` token now has the `project` and `workflow` scopes (resolved).
