# homelab-proposals changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [1.0.0] - 2026-11-01

- Replace mandatory per-ADR trackers with outcome-based initiatives and optional
  independent ADR trackers. Require index consistency checks on metadata changes.

## [0.2.0] - 2026-11-01

- Add the optional domain-doc step (RFC process step 4) to the phase table,
  routed to homelab-docs, so the page no longer falls between the two skills.
- The `proposals-researcher` sub-agent no longer preloads this skill: the
  skill tells its reader to spawn that sub-agent, so the researcher was
  reading an instruction to delegate to itself. It links the research
  template and gate directly.

## [0.1.0] - 2026-11-01

- Baseline: route the RFC/ADR lifecycle to its owning files in `docs/proposals/`
  (reserve a number, research gate, RFC, one-per-ADR split, acceptance, tracking
  issue) without copying the templates or process. Split from platform-engineer,
  which stays the dispatcher.
- Delegate the research phase to the `proposals-researcher` sub-agent
  (`.agents/agents/`); the skill keeps the index row, commit and owner gate.
