# Architecture diagrams

Draw.io (`.drawio`) diagram sources for the platform, plus their committed
exports. Draw.io is the **exception** here — [Mermaid is the default](../../AGENTS.md)
for diagrams in this repo; these files exist for the large, logo-bearing views
that earn an editable vector source. Each is **generated top-down from a YAML
model** (`<name>.ir.yaml`, the IR) by the
[`homelab-drawio`](../../.agents/skills/homelab-drawio/SKILL.md) skill, so the
IR is what you edit and the `.drawio` is its output.

| Fact | Value |
|------|-------|
| Sources | `*.ir.yaml` (the model you edit) → `*.drawio` (generated, still editable in Draw.io) |
| Exports | SVG beside the source; PNG under [`img/`](img/) (GitHub strips text from Draw.io SVG, so a Markdown page embeds the PNG and links the SVG for zooming) |
| Style | homelab house style — palette mirrors the Mermaid `classDef` in [AGENTS.md](../../AGENTS.md) |
| Regenerate | `S=.agents/skills/homelab-drawio/scripts; python3 $S/generate.py docs/architecture/<name>.ir.yaml && python3 $S/export.py docs/architecture/<name>.drawio --png --png-dir docs/architecture/img` |
| Validate | `python3 .agents/skills/homelab-drawio/scripts/validate.py docs/architecture/<name>.drawio --ir docs/architecture/<name>.ir.yaml` — 0 errors to ship |

## Sources

| Source | Answers | Published |
|--------|---------|-----------|
| [`topology.drawio`](topology.drawio) | **Request path** — how a request travels once the platform is up: edge → apps → data, with the observability and secrets planes. | [`README.md` § Topology](../../README.md#topology) (as [`img/topology.png`](img/topology.png), [`topology.svg`](topology.svg) to zoom) |
| [`observability-signal-flow.drawio`](observability-signal-flow.drawio) | **Signal flow + retention** — which OTel Collector pipeline carries each signal, which backend stores it and for how long, and the paths that bypass the collector (Pyroscope SDK, vmagent scrape, Vector). | [`observability/README.md` § Architecture](../observability/README.md#architecture) (as [`img/observability-signal-flow.png`](img/observability-signal-flow.png), [`observability-signal-flow.svg`](observability-signal-flow.svg) to zoom) |
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
- **Edit the IR, never the generated `.drawio`.** `validate.py --ir` fails a
  file that no longer matches its IR, and the skill's tests check every IR in the
  repo against its committed `.drawio`.
- **Commit the IR, the `.drawio` and its exports together** — a source edit
  without a regenerate and re-export ships a stale picture.
- **Frames own their children** (`container=1`): moving a domain frame moves the
  boxes inside it, and it is what makes the "no logo on a grouping frame" check
  able to fire at all.
- Validate before exporting (the table above), then **open the render and
  look**, which is where a crowded corner or an ambiguous crossing is caught.

_Last updated: 2026-09-28 — every source now sits in a `Kind cluster · homelab` frame (only the browser stays outside); all three sources redrawn top-down from YAML IRs (`*.ir.yaml`) by the skill's generator, with routed edges and placed labels; PNGs quantized to 256 colours. Earlier the same day: `observability-signal-flow.drawio` added and the v2 soft-tint palette applied._
