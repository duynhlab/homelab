---
name: homelab-drawio
description: >-
  Author, edit, and export Draw.io (`.drawio`) architecture diagrams in the
  homelab repo with the house style and curated logos. Use whenever the request
  names Draw.io / diagrams.net / a `.drawio` file, asks to edit an existing
  `.drawio`, or asks to export/re-render one to SVG/PNG. Mermaid stays the
  default for diagrams in this repo (AGENTS.md); reach for this skill only when
  Draw.io is asked for by name or a `.drawio` already exists. For a plain
  Mermaid diagram, do NOT use this skill.
---

# homelab-drawio

Draw.io authoring for the homelab platform. This is a thin **overlay on the
generic IDE `drawio-skill`**: that skill owns Draw.io mechanics (XML structure,
ELK `--layout`, shape search, URL/PNG export invariants); this one adds what
makes a diagram *this repo's* — a semantic palette shared with the Mermaid
convention, a curated logo catalog, house-style validation, and reproducible
export. Read the generic skill for XML/layout; read the references here for
homelab policy.

**Mermaid is the repo default** ([AGENTS.md](../../../AGENTS.md) Diagrams). Draw.io
earns its extra weight only for a large multi-domain overview or an editable
source someone will hand-tune — and only when asked for by name, or when a
`.drawio` already exists. If the request is a normal flowchart/sequence/state
diagram, write Mermaid instead and stop.

## Workflow

1. **One question.** State whether the diagram answers topology, a request path,
   ownership, lifecycle, or a migration — the same rule as
   [AGENTS.md § Diagram workflow](../../../AGENTS.md). Split a diagram that tries
   to answer more than one.
2. **Verify deployed reality.** A diagram is an executable summary of the repo,
   not decoration. Cross-check every box against the manifests and
   [`docs/api/`](../../../docs/api/README.md) (the API source of truth — see the
   [platform-engineer skill](../platform-engineer/SKILL.md)). Anything not
   deployed is labelled **planned** and drawn dashed — both, or the check in
   step 6 fails.
3. **Preflight.** `python3 scripts/doctor.py` — confirms `drawio` and
   `rsvg-convert` are present before you invest in authoring.
4. **Author native XML** (`.drawio` under `docs/**`), applying the house style
   and logos:
   - Colours/shapes/edges → [`references/house-style.md`](references/house-style.md).
   - A box that IS a deployed product gets its logo →
     [`references/icons.md`](references/icons.md); paste a ready style with
     `python3 scripts/icon_style.py style <name> --role <role>`.
   - Large graph (~15+ nodes)? Let the generic skill's ELK `--layout` place it;
     do not hand-place more than ~15 nodes.
   - Every diagram carries its own **legend**.
5. **Validate.** `python3 scripts/validate_house.py <file.drawio>` (house style)
   and the generic skill's `validate.py --score` (structure). Fix errors before
   exporting.
6. **Export + look.** `python3 scripts/export.py <file.drawio>` writes SVG (add
   `--png` for the one raster GitHub needs). Open the SVG and inspect for
   clipping, edge-through-node crossings, and icons that vanish at render size.
   `python3 scripts/icon_style.py audit docs/<dir>` flags product boxes still
   missing a logo (advisory).
7. **Report** the editable `.drawio` and the exported path(s).

## Scripts

Run from this skill directory (`.agents/skills/homelab-drawio/`).

| Command | Does |
|---|---|
| `scripts/doctor.py` | Preflight: `drawio`, `rsvg-convert`, ImageMagick, Python versions |
| `scripts/icon_style.py style <name> --role <role>` | Emit a paste-ready label style with the logo embedded + palette applied |
| `scripts/icon_style.py list` | Show the icon catalogue, aliases, and `none` decisions |
| `scripts/icon_style.py audit <dir>` | Advisory: product boxes rendering without a logo; logos on frames |
| `scripts/validate_house.py <file>` | House-style checks (embed traps, planned state, frame icons, font, legend) |
| `scripts/export.py <file> [--png]` | Reproducible SVG/PNG export with version + size budget |

## Guardrails

- **Palette is not invented here.** Node colours mirror the Mermaid `classDef`
  in AGENTS.md so a Draw.io diagram and the Mermaid beside it read as one
  system. The single source is [`assets/homelab.json`](assets/homelab.json);
  change it and AGENTS.md together.
- **PNG logos, comma-joined.** `image=data:image/png,<base64>` — never
  `;base64,` (truncates the style) and never an SVG data URI (exports blank).
  `icon_style.py` gets this right; hand-rolling does not.
- **A logo must not assert something false.** Icon the box's *subject*, never a
  product its label merely mentions; grouping frames and concept boxes stay
  plain. Catalogue is deployed-platform-only.
- **Planned = dashed + the word "planned".** `validate_house.py` enforces both.
- **Commit** per [platform-engineer](../platform-engineer/SKILL.md): branch, no
  attribution trailers, `make validate` when repo manifests change. Commit the
  `.drawio` source and its exports together (a source edit without a re-export
  ships a stale picture).
