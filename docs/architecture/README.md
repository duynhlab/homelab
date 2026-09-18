# Architecture diagrams

Draw.io (`.drawio`) diagram sources for the platform, plus their committed
exports. Draw.io is the **exception** here — [Mermaid is the default](../../AGENTS.md)
for diagrams in this repo; these files exist for the large, logo-bearing views
that earn an editable vector source. They are authored with the
[`homelab-drawio`](../../.agents/skills/homelab-drawio/SKILL.md) skill.

| Fact | Value |
|------|-------|
| Sources | `*.drawio` in this directory |
| Exports | SVG beside the source; PNG under [`img/`](img/) (GitHub strips text from Draw.io SVG, so a Markdown page embeds the PNG and links the SVG for zooming) |
| Style | homelab house style — palette mirrors the Mermaid `classDef` in [AGENTS.md](../../AGENTS.md) |
| Regenerate | edit the `.drawio`, then `python3 .agents/skills/homelab-drawio/scripts/export.py <file> --png --png-dir docs/architecture/img` |
| Re-layout | a dependency graph is laid out, not hand-placed: `drawio --layout '[{"layout":"elkLayered","config":{"elk.direction":"DOWN"}}]' -x -f xml -u -o <file> <file>` |

## Sources

| Source | Answers | Published |
|--------|---------|-----------|
| [`topology.drawio`](topology.drawio) | **Request path** — how a request travels once the platform is up: edge → apps → data, with the observability and secrets planes. | [`README.md` § Topology](../../README.md#topology) (as [`img/topology.png`](img/topology.png), [`topology.svg`](topology.svg) to zoom) |
| [`observability-delivery.drawio`](observability-delivery.drawio) | **Delivery order** — how Flux delivers the observability stack and what releases each wave, including the two ClickHouse waves that omit `wait` so their `healthChecks` stay live. | [`observability/README.md` § Deployment](../observability/README.md#deployment) (as [`img/observability-delivery.png`](img/observability-delivery.png), [`observability-delivery.svg`](observability-delivery.svg) to zoom) |

## Conventions

- **One question per file**, kebab-case name. Pick the question from
  [`references/diagram-types.md`](../../.agents/skills/homelab-drawio/references/diagram-types.md),
  which also carries the pre-export review checklist.
- **Accurate to deployed reality**; anything not deployed is drawn dashed and
  labelled `planned`.
- **Logos** come from the skill's curated catalog
  ([`assets/icons/manifest.json`](../../.agents/skills/homelab-drawio/assets/icons/manifest.json));
  a box gets a logo only for the product it is.
- **Commit the source and its export together** — a source edit without a
  re-export ships a stale picture.
- **Frames own their children** (`container=1`): moving a domain frame moves the
  boxes inside it, and it is what makes the "no logo on a grouping frame" check
  able to fire at all.
- Validate before exporting:
  `python3 .agents/skills/homelab-drawio/scripts/validate_house.py <file>` — then
  **open the render and look**, which is where clipping and overlapping labels
  are caught.

_Last updated: 2026-09-18._
