# homelab-troubleshooting changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [0.1.0] - 2026-10-29

- Added a **Known traps** section to seven domain references (22 traps): merge
  vs deploy, Flux `force`, chart renames, ZFS hosts, `cpu: null`, the Kind
  seed, alert-signal traps (`absent()`, count-once `increase()`, re-born
  series, label values, missing metrics, scrape intervals), mockpay
  discrepancies, Collector and Grafana traps, CNPG monitoring, pooler TLS,
  pg_stat_ch, CDC mirror status and stale slots, ClickHouse users, engines,
  XML comments and lazy log tables. Each trap was re-checked against the repo
  and links the doc that owns it; traps no doc owned were written there first.
- Added six evals (11 total) for the most common traps.
- SKILL.md tells the reader to check a domain's known traps before forming a
  new hypothesis.

## [0.0.1] - 2026-10-28

- Baseline: first draft, added in #1402. Entry modes, non-negotiables, ten domain routes and five evals.
