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

Draw.io authoring for the homelab platform: a semantic palette shared with the
Mermaid convention, a curated logo catalog, house-style validation, and
reproducible export.

Everything a step here *requires* is in this directory or in the `drawio` CLI —
nothing in the workflow depends on another skill being installed. A generic
Draw.io skill in the agent IDE is a useful **complement** for shape search and
structural scoring, and step 5 names it, but as an optional extra.

**Mermaid is the repo default** ([AGENTS.md](../../../AGENTS.md) Diagrams). Draw.io
earns its extra weight only for a large multi-domain overview or an editable
source someone will hand-tune — and only when asked for by name, or when a
`.drawio` already exists. If the request is a normal flowchart/sequence/state
diagram, write Mermaid instead and stop.

## Workflow

1. **One question.** Pick a row from
   [`references/diagram-types.md`](references/diagram-types.md) — platform
   landscape, domain topology, request path, delivery/lifecycle, or migration —
   and use its primary/supporting split to decide what goes in. That file is what
   makes [AGENTS.md § Diagram workflow](../../../AGENTS.md#diagram-workflow)
   step 1 actionable. Split a diagram that tries to answer more than one
   question.
2. **Verify deployed reality.** A diagram is an executable summary of the repo,
   not decoration. Cross-check every box against the manifests and
   [`docs/api/`](../../../docs/api/README.md) (the API source of truth — see the
   [platform-engineer skill](../platform-engineer/SKILL.md)). Anything not
   deployed is labelled **planned** and drawn dashed — both, or the check in
   step 6 fails.
3. **Preflight.** `python3 scripts/doctor.py` — confirms `drawio` is present
   before you invest in authoring (add `--adding-icon` when you will also
   rasterise a new logo, which needs `rsvg-convert`).
4. **Author native XML** (`.drawio` under `docs/**`), applying the house style
   and logos:
   - Colours/shapes/edges → [`references/house-style.md`](references/house-style.md).
   - A box that IS a deployed product gets its logo →
     [`references/icons.md`](references/icons.md); paste a ready style with
     `python3 scripts/icon_style.py style <name> --role <role>`.
   - Domain frames use `shapes.container` and **own** their children: set each
     child's `parent` to the frame id and write its geometry relative to the
     frame origin ([`references/house-style.md`](references/house-style.md)).
   - Large graph (~15+ nodes)? Do not hand-place it — let ELK lay it out and
     write the result back into the source:
     ```bash
     drawio --layout '[{"layout":"elkLayered","config":{"elk.direction":"RIGHT"}}]' \
            -x -f xml -u -o <file>.drawio <file>.drawio
     ```
     (`--layout` also takes the presets `verticalFlow`, `horizontalFlow`,
     `verticalTree`, `horizontalTree`, `radialTree`, `organic`. Without
     `-f xml -u` the layout applies to the export only and the source keeps its
     old coordinates.)
   - Every diagram carries its own **legend**.
5. **Validate.** `python3 scripts/validate_house.py <file.drawio>` — required.
   Fix every ERROR before exporting; read the WARNings and either fix them or be
   able to say why not. If the agent IDE's generic Draw.io skill is installed, its
   `validate.py --score` adds a structural score on top; skip it when it is not.
6. **Export + look.** `python3 scripts/export.py <file.drawio>` writes the SVG;
   add `--png --png-dir <dir>` for the one raster GitHub needs
   ([`references/export.md`](references/export.md)). Then **open the render** and
   walk the review checklist in
   [`references/diagram-types.md`](references/diagram-types.md#review-it-before-you-export):
   clipping, edge-through-node crossings, labels overlapping their boxes, icons
   that vanish at render size. This step finds what no validator can.
   `python3 scripts/icon_style.py audit docs` flags product boxes still missing a
   logo (advisory, recursive).
7. **Report** the editable `.drawio` and the exported path(s).

## Scripts

Run from this skill directory (`.agents/skills/homelab-drawio/`).

| Command | Does |
|---|---|
| `scripts/doctor.py [--adding-icon]` | Preflight: `drawio` (required), ImageMagick + `rsvg-convert` (for adding icons) |
| `scripts/icon_style.py style <name> --role <role>` | Emit a paste-ready label style with the logo embedded + palette applied (adds `dashed=1` for `planned`) |
| `scripts/icon_style.py list` | Show the icon catalogue, aliases, and `none` decisions |
| `scripts/icon_style.py audit <dir>` | Advisory, recursive: product boxes rendering without a logo; logos on frames |
| `scripts/validate_house.py <file> [--strict]` | House-style checks (embed traps, planned state, frame icons, font, legend, title, unlabelled dashed edges) |
| `scripts/export.py <file> [--png --png-dir <dir>]` | Reproducible SVG/PNG export with version + per-format size budget |

`python3 -m unittest discover -s tests` covers the helpers (catalog checksums,
style emission, every validator rule) with no network and no `drawio` binary —
run it after touching `scripts/` or `assets/`. `evals/evals.json` holds three
end-to-end authoring evals in skill-creator format; they need that plugin and a
live repo, so they are a judgement aid, not a gate.

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
  plain. Catalogue is deployed-platform-only. Both checks key on a frame that
  actually owns children, so a frame drawn as a bare rectangle is a frame nothing
  can police — see `container=1` in
  [`references/house-style.md`](references/house-style.md).
- **Planned = dashed + the word "planned".** `validate_house.py` **errors** on a
  planned-styled box (dashed + the planned stroke) whose label omits the word,
  and **warns** on a label that says "planned" without the dash — a warning
  because legends and prose like "planned migration" say it innocently, so
  annotations and legend cells are exempt.
- **Commit** per [platform-engineer](../platform-engineer/SKILL.md): branch, no
  attribution trailers, `make validate` when repo manifests change. Commit the
  `.drawio` source and its exports together (a source edit without a re-export
  ships a stale picture).
