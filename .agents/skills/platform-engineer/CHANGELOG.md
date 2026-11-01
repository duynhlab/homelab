# platform-engineer changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [3.1.0] - 2026-11-01

- Route active research to Analysis and execution to In progress under the shared
  work limit in the tracking procedure.

## [3.0.0] - 2026-11-01

- Require an existing work-item check at task entry and an evidence/next-action
  handoff at exit. Route work state to the shared tracking procedure.

## [2.0.0] - 2026-11-01

- Add § Working with the owner: ten binding rules the owner set through
  corrections (gate→merge→tag→Kind order, no green report mid-push, admin
  merge only on green, named-path staging, evidence over memory, read the
  service code, adoptable features hold a bump, pre-deployment contracts,
  Envoy-Gateway-native edge, explain the mechanism). Major: a new contract
  every agent must follow.
- Fix the chart names: `duynh` and `slo`, not `mop`.
- IDE skills map: add git-pr and the proposals-researcher sub-agent; say
  which skill owns a runbook decision and which writes the page.
- Description names the skills it routes to.

## [1.2.0] - 2026-11-01

- Route docs pages, runbooks and hubs to the new [homelab-docs](../homelab-docs/SKILL.md) skill in the IDE skills map.

## [1.1.0] - 2026-11-01

- Route the RFC/ADR lifecycle to the new [homelab-proposals](../homelab-proposals/SKILL.md) skill: collapse § RFC / ADR gate to a dispatcher pointer, replace the RFC and ADR rows in the IDE skills map (they sent authoring to `spec-driven-development`, `planning-and-task-breakdown`, and `documentation-and-adrs`, whose templates and paths do not match this repo) with one row, and name the skill in the override footnote.

## [1.0.0] - 2026-09-15

- Baseline: the agent operating procedure, created in #1050 and reshaped since (commit conventions moved to git-commits in #1281, ADR tracking issues in #1302, the git-worktrees and homelab-troubleshooting skills linked in #1401 and #1402).
