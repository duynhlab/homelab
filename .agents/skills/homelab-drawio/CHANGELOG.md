# homelab-drawio changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [1.0.1] - 2026-11-01

- Eval 0 asserts the v2 palette from `assets/homelab.json`; the v1 fills
  failed a correct diagram. Evals 0–2 save under `docs/architecture/<domain>/`.
- `icon_style.py` commands in house-style and icons run from the skill
  directory, as SKILL.md says.
- Link to git-pr after the git-commits rename (#1473).

## [1.0.0] - 2026-09-22

- Baseline: IR-driven Draw.io authoring, created in #1069. Latest behaviour: edges stay in their frames with 14 px lanes (#1390) and `house.missing_logo` with the PgBouncer and PeerDB icons (#1391).
