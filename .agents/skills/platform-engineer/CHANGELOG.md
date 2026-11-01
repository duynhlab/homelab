# platform-engineer changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [1.1.0]

- Route the RFC/ADR lifecycle to the new [homelab-proposals](../homelab-proposals/SKILL.md) skill: collapse § RFC / ADR gate to a dispatcher pointer, replace the RFC and ADR rows in the IDE skills map (they sent authoring to `spec-driven-development`, `planning-and-task-breakdown`, and `documentation-and-adrs`, whose templates and paths do not match this repo) with one row, and name the skill in the override footnote.

## [1.0.0] - 2026-09-15

- Baseline: the agent operating procedure, created in #1050 and reshaped since (commit conventions moved to git-commits in #1281, ADR tracking issues in #1302, the git-worktrees and homelab-troubleshooting skills linked in #1401 and #1402).
