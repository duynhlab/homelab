# Architecture diagrams

Draw.io (`.drawio`) diagram sources for the platform, plus their committed
exports. Draw.io is the **exception** here — [Mermaid is the default](../../AGENTS.md)
for diagrams in this repo; these files exist for the large, logo-bearing views
that earn an editable vector source. They are authored with the
[`homelab-drawio`](../../.agents/skills/homelab-drawio/SKILL.md) skill.

| Fact | Value |
|------|-------|
| Sources | `*.drawio` in this directory |
| Exports | SVG beside the source; PNG under [`img/`](img/) (GitHub strips text from Draw.io SVG, so README embeds the PNG) |
| Style | homelab house style — palette mirrors the Mermaid `classDef` in [AGENTS.md](../../AGENTS.md) |
| Regenerate | edit the `.drawio`, then `python3 .agents/skills/homelab-drawio/scripts/export.py <file> --png --out-dir docs/architecture/img` |

## Sources

| Source | Answers | Published |
|--------|---------|-----------|
| [`topology.drawio`](topology.drawio) | The request path once the platform is up: edge → apps → data, with the observability and secrets planes. | [`README.md` § Topology](../../README.md#topology) (as [`img/topology.png`](img/topology.png)) |

## Conventions

- **One question per file**, kebab-case name — same rule as the
  [AGENTS.md diagram workflow](../../AGENTS.md).
- **Accurate to deployed reality**; anything not deployed is drawn dashed and
  labelled `planned`.
- **Logos** come from the skill's curated catalog
  ([`assets/icons/manifest.json`](../../.agents/skills/homelab-drawio/assets/icons/manifest.json));
  a box gets a logo only for the product it is.
- **Commit the source and its export together** — a source edit without a
  re-export ships a stale picture.
- Validate before exporting:
  `python3 .agents/skills/homelab-drawio/scripts/validate_house.py <file>`.

_Last updated: 2026-09-18._
