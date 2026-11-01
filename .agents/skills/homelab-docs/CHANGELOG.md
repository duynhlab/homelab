# homelab-docs changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [1.1.0] - 2026-11-01

- Runbook shape follows `docs/observability/runbooks/_TEMPLATE.md` (adds
  Safety, Recovery validation, Escalation) instead of restating the older
  five-section order.
- Route the optional RFC domain doc (RFC process step 4) here.
- Link ADR-090, which partly supersedes ADR-083's "no second documentation
  skill" clause.

## [1.0.0] - 2026-11-01

- Baseline: a router over the homelab docs conventions with five references:
  page shapes mapped to Diátaxis, style rules with the homelab term table and
  the current-state-vs-records boundary, an editing workflow with triage, a
  five-pass review framework with homelab blockers, and a prose-quality pass.
  Adapted from an open-source technical-writing skill; the verification order
  (manifests and cluster first, records by status, Context7 for upstream) and
  the status labels are homelab's own.
