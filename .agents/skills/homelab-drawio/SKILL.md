---
name: homelab-drawio
description: >-
  Author, edit, and export Draw.io (`.drawio`) architecture diagrams in the
  homelab repo: plan the diagram as a YAML IR, generate a top-down `.drawio`
  in the house style with curated logos, run the quality gates, and export
  SVG/PNG. Use whenever the request names Draw.io / diagrams.net / a `.drawio`
  file, asks to edit an existing `.drawio`, or asks to export/re-render one.
  Mermaid stays the default for diagrams in this repo (AGENTS.md); reach for
  this skill only when Draw.io is asked for by name or a `.drawio` already
  exists. For a plain Mermaid diagram, do NOT use this skill.
---

# homelab-drawio

Draw.io authoring for the homelab platform. The diagram is **planned as a
model**, a small YAML IR ([`references/ir.md`](references/ir.md)).
`scripts/generate.py` projects the model into a top-down `.drawio`:
- tiers run down the page and peers sit side by side;
- frames nest;
- edges are orthogonal, in routing channels;
- colours come from the semantic palette shared with the Mermaid convention;
- boxes carry curated logos.

`scripts/validate.py` then runs the quality gates.

Everything a step here *requires* is in this directory, plus the `drawio` CLI
and Graphviz `dot`. Nothing in the workflow depends on another skill being
installed.

**Mermaid is the repo default** ([AGENTS.md](../../../AGENTS.md) Diagrams).
Draw.io earns its extra weight only in two cases:
- a large multi-domain overview;
- an editable source someone will hand-tune.

Even then, only when asked for by name, or when a `.drawio` already exists. A
normal flowchart, sequence or state diagram is Mermaid: write that instead and
stop.

## Workflow

1. **One question, one level.** Pick the question from
   [`references/diagram-types.md`](references/diagram-types.md): platform
   landscape, domain topology, request path, delivery/lifecycle, or migration.
   Pick one level of abstraction, L0–L5. The same file's primary/supporting
   split decides what goes in. A diagram that answers two questions is two
   diagrams.
2. **Verify deployed reality.** A diagram is an executable summary of the repo,
   not decoration.
   - Cross-check every box and edge against the manifests and
     [`docs/api/`](../../../docs/api/README.md), the API source of truth (see the
     [platform-engineer skill](../platform-engineer/SKILL.md)).
   - [`references/domains.md`](references/domains.md) says, per area, where to
     look and what is easy to get wrong.
   - Anything not deployed is `status: planned`: the generator dashes it and
     refuses a label without the word.
   - Record what you checked in the IR's header comment.
3. **Plan it as an IR.** Write `docs/architecture/<domain>/<name>.ir.yaml` (one
   directory per domain: `platform`, `observability`, `databases`, `security`,
   `workflows`, …) beside where the
   `.drawio` will live. It holds:
   - the question and level;
   - ordered `layers` (top of the canvas first);
   - `boundaries`, `nodes` (role, layer, icon) and `edges` (one of eight
     relationship types, with a label saying what flows);
   - an outermost `boundaries` frame for the cluster (`Kind cluster · homelab`)
     that every platform node and frame sits in; only `external` nodes stay
     outside;
   - `notes` for what the boxes cannot say;
   - the architecture `tests` that must hold;
   - `assumptions` for anything you could not verify.

   Field rules: [`references/ir.md`](references/ir.md); colours and relationship
   types: [`references/house-style.md`](references/house-style.md); logos:
   [`references/icons.md`](references/icons.md).
4. **Generate.** Run `python3 scripts/doctor.py` once, then:
   ```bash
   python3 scripts/generate.py docs/architecture/<domain>/<name>.ir.yaml     # writes <name>.drawio
   ```
5. **Validate.**
   ```bash
   python3 scripts/validate.py docs/architecture/<domain>/<name>.drawio --ir docs/architecture/<domain>/<name>.ir.yaml
   ```
   Fix every ERROR. Read each WARN and either fix it or be able to say why it
   stays. Crossings are the WARN most worth reducing. The gates and the finding
   format are in [`references/quality-gates.md`](references/quality-gates.md).
6. **Export and look.**
   ```bash
   python3 scripts/export.py docs/architecture/<domain>/<name>.drawio --png --png-dir docs/architecture/<domain>/img
   ```
   Then **open the PNG** and walk the review checklist in
   [`diagram-types.md`](references/diagram-types.md#review-it-before-you-export)
   and the self-check in [`quality-gates.md`](references/quality-gates.md#self-check-after-rendering).
   This step finds what no validator can.
7. **Fix in the IR, then return to step 4.**
   - Order of preference: split the view, re-tier a node, reorder peers or
     toggle `pin_order`, and only then use `via` / `label_pos`.
   - Never hand-edit the generated XML. `validate.py --ir` fails a file that no
     longer matches its IR.
   - At most five rounds. After two geometry rounds that do not converge, ask the
     owner: the model is unclear.
8. **Embed, report and commit.** The page shows the SVG (so the primary flow
   moves; GitHub renders it with its labels) and links the PNG, under a
   one-line lead-in saying which question this copy answers (and, beside a Mermaid
   map of the same question, what it adds). The caption is only the source link:
   ```html
   <p align="center"><a href="../architecture/<domain>/<name>.svg"><img src="../architecture/<domain>/<name>.svg" alt="…" width="960"></a></p>
   <p align="center"><sub>Source <a href="../architecture/<domain>/<name>.drawio"><code><domain>/<name>.drawio</code></a> · <a href="../architecture/<domain>/img/<name>.png">PNG</a></sub></p>
   ```
   Commit the `.ir.yaml`, the `.drawio`, the SVG and the PNG together, and add the
   row to `docs/architecture/README.md`.

**A `.drawio` without an IR** is hand-drawn, or needs geometry the IR cannot
express. Edit it in place (house style: [`references/house-style.md`](references/house-style.md);
domain frames own their children through `container=1`), then run steps 5–6.
For a large hand-drawn graph, let ELK lay it out and write the result back into
the source:

```bash
drawio --layout '[{"layout":"elkLayered","config":{"elk.direction":"DOWN"}}]' \
       -x -f xml -u -o <file>.drawio <file>.drawio
```

Prefer converting a diagram you touch often into an IR.

## Scripts

Run from this skill directory (`.agents/skills/homelab-drawio/`), or give
repo-root paths from the repo root.

| Command | Does |
|---|---|
| `scripts/doctor.py [--adding-icon]` | Preflight. Required: `drawio` (wrapped in `xvfb-run -a` without a display, `--no-sandbox` as root), Graphviz `dot`, PyYAML and jsonschema. Optional: Pillow for PNG quantizing, ImageMagick + `rsvg-convert` when adding icons. Also reports which font renders Helvetica. Install hints follow the OS |
| `scripts/generate.py <ir> [-o <drawio>] [--check]` | IR → top-down `.drawio`, deterministic. `--check` exits 1 when the file on disk is stale |
| `scripts/validate.py <drawio> [--ir <ir>] [--json] [--strict]` | The quality gates: house, structural, connectivity, geometry, typography, architecture. Findings as `{severity, rule_id, objects, message, fix}` |
| `scripts/validate_house.py <file> [--strict]` | House rules alone. `validate.py` runs them as its first gate |
| `scripts/icon_style.py style <name> --role <role>` | A paste-ready logo style for hand-drawn boxes (`dashed=1` added for `planned`) |
| `scripts/icon_style.py list` / `audit <dir>` | The icon catalogue; product boxes still missing a logo (advisory) |
| `scripts/export.py <file> [--png --png-dir <dir>]` | Reproducible SVG/PNG export. The PNG is quantized to 256 colours, and each format has a size budget |

`python3 -m unittest discover -s tests` covers:
- the helpers;
- every validator rule, with a passing and a failing fixture;
- the generator (determinism, top-down order, frames, legend, IR rejection).

It also checks that **every committed `.ir.yaml` still generates its committed
`.drawio` byte for byte**. It needs no network and no `drawio` binary. The
generator tests skip without `dot`. Run the suite after touching `scripts/`,
`assets/` or `schema/`. `evals/evals.json` holds end-to-end authoring evals in
skill-creator format; they are a judgement aid, not a gate.

## Guardrails

- **The palette is not invented here.** Node colours mirror the Mermaid
  `classDef` in AGENTS.md, so a Draw.io diagram and the Mermaid beside it read as
  one system. The single source is [`assets/homelab.json`](assets/homelab.json);
  change it and AGENTS.md together.
- **PNG logos, comma-joined.** Write `image=data:image/png,<base64>`. Never
  `;base64,`, which truncates the style, and never an SVG data URI, which exports
  blank. The generator and `icon_style.py` get this right; hand-rolling does not.
- **A logo must not assert something false.**
  - Icon the box's *subject*, never a product its label merely mentions.
  - Grouping frames and concept boxes stay plain.
  - Never invent or counterfeit a vendor mark.
  - The catalogue is deployed-platform-only.
- **Planned = dashed + the word "planned".** The generator refuses a planned
  node or edge without the word. `validate_house.py` errors on a planned-styled
  box that omits it, and warns on the word without the dash.
- **Architecture rules are declared, never assumed.** Only the rules an IR lists
  under `tests` run. A common best practice becomes a rule here when an ADR says
  so.
- **Never assert a path without evidence.** A packet path, a pooler or a
  hostname comes from the manifests, not from how such platforms usually look.
- **Commit** per [platform-engineer](../platform-engineer/SKILL.md): branch, no
  attribution trailers, `make validate` when repo manifests change. Commit the
  IR, the `.drawio` and its exports together. A source edit without a re-export
  ships a stale picture.
