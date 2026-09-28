# Homelab Draw.io house style

The visual language every homelab `.drawio` follows. The goal is one system: a
Draw.io diagram and the Mermaid diagram beside it use the **same semantic
colours**, so a reader learns the palette once. The machine-readable source is
[`../assets/homelab.json`](../assets/homelab.json); this file explains how to
apply it. When they disagree, the JSON wins — and the JSON must track the Mermaid
`classDef` block in [AGENTS.md § Diagram workflow](../../../../AGENTS.md#diagram-workflow)
(step 4).

## Semantic palette

Each role carries a fill, a stroke, and the font colour that stays legible on
that fill — all three copied from the AGENTS.md `classDef` verbatim.

**v2 soft tints (2026-09-28).** A light fill, the role hue on the stroke, dark
text. v1 filled boxes with the saturated role colour and white text; on a
30-box canvas that read as a wall of colour. Every role now clears **7:1** text
contrast and **3:1** stroke contrast against white (WCAG formula), so the
diagram stays legible printed, projected or in a dark-mode viewer that keeps
the image as-is. `validate_house.py` warns on a v1 fill, white text on a content
box, or a drop shadow.

| Role | Fill | Stroke | Font | Use for |
|---|---|---|---|---|
| `edge` | `#DBEAFE` | `#2563EB` | `#1E3A8A` | Envoy Gateway, ingress, the edge |
| `service` | `#CFFAFE` | `#0891B2` | `#164E63` | platform / app services |
| `worker` | `#FEF3C7` | `#D97706` | `#78350F` | Temporal workers, async processors |
| `platform` | `#EDE9FE` | `#7C3AED` | `#4C1D95` | control-plane controllers (Flux, KEDA, operators) |
| `data` | `#DCFCE7` | `#16A34A` | `#14532D` | datastores (Postgres, Valkey, ClickHouse, buckets) |
| `external` | `#F1F5F9` | `#64748B` | `#334155` | third-party / off-platform |
| `metric` | `#FFE8CC` | `#E8590C` | `#111111` | observability: metrics (VictoriaMetrics) |
| `log` | `#D3F9D8` | `#2F9E44` | `#111111` | observability: logs (VictoriaLogs) |
| `trace` | `#C5F6FA` | `#0C8599` | `#111111` | observability: traces (VictoriaTraces) |
| `profile` | `#F3D9FA` | `#9C36B5` | `#111111` | observability: profiles (Pyroscope) |
| `collector` | `#E0F2FE` | `#1971C2` | `#0C4A6E` | observability: collectors (Vector, OTel) |
| `planned` | `#FFFFFF` | `#64748B` | `#475569` | not-yet-deployed — **always dashed** |

Do not invent decorative per-node colours, and never rely on colour alone to
carry meaning (label the state too).

## Shapes

- **Card** (a component): the `shapes.card` prefix — rounded, no shadow,
  `strokeWidth=1.5`, wrap. With a logo it becomes a `shape=label` (logo left, text right); the
  `icon_style.py` output already encodes this.
- **Container / domain frame**: the `shapes.container` prefix — rounded, top-
  aligned title, no shadow, and `container=1`. A frame groups; it never carries a
  logo.

  `container=1` is load-bearing. A frame must **own** its children, so that
  moving the frame moves them and the "no logo on a grouping frame" check has
  something to fire on — a styled rectangle that merely sits behind its boxes
  looks identical and does neither. Two consequences when you author one:

  - Set each child's `parent` to the frame id, and write its `mxGeometry`
    **relative to the frame origin** (child abs x − frame x).
  - Edges stay on the root layer even when both endpoints are inside frames;
    Draw.io resolves them from `source`/`target`.

  For an untitled, invisible grouping, Draw.io's own mechanism is the `group;`
  style instead — use it only when the group needs no label.
- **Datastore**: `shape=cylinder3` (`shapes.datastore`), always the `data` role.

Fonts: **Helvetica** everywhere (web-safe, resolves locally, so SVG export needs
no embedded font). Titles use `fontSize=13; fontStyle=1`. macOS ships Helvetica;
Linux has none and fontconfig substitutes a metric-compatible clone (Nimbus Sans
from `fonts-urw-base35`, or Liberation Sans), so a label measures the same on
both and the style never needs a per-OS font. `doctor.py` reports the
substitute; a non-metric fallback such as DejaVu Sans is wider and can overflow
a box.

Frames (domain groups and the legend) are neutral: `fillColor=#F8FAFC;
strokeColor=#CBD5E1;fontColor=#334155;fontSize=13;fontStyle=1` (`frame` in the
preset). A frame never takes a role colour.

## Edges

Colour the edge by what flows, matching the node palette:

| Role | Meaning |
|---|---|
| `request` (blue) | request / control flow |
| `storage` (green) | reads/writes to a datastore |
| `scaling` (amber) | autoscaling / capacity signal |
| `planned` (slate, dashed, open arrow) | planned or optional path |

Solid = a current path. Dashed = optional, planned, or a documented exception —
and a dashed edge must carry a label saying which. A planned edge's label
contains the word `planned` (same rule as nodes).

### Relationship types

An IR edge carries one of eight types (`assets/homelab.json` → `edges`). Each
colour reuses the stroke of the node role it most often touches, so the palette
stays one system:

| Type | Colour / head | Means | Label with |
|---|---|---|---|
| `traffic` | edge blue, filled head | a runtime request | the protocol or route: HTTPS, HTTPRoute, gRPC |
| `data` | data green | reads / writes a store, or a store read by a viewer | what is read: SQL, cache-aside, queried |
| `control` | platform violet | reconciles / manages / releases | the verb: manages, syncs Secrets |
| `dependency` | slate, open head | needs, without a runtime flow | why: depends on, skips a layer |
| `event` | worker amber, hollow head | asynchronous message or signal | the queue or event |
| `replication` | data green, thick | a store copying to a store | the mechanism: WAL, DR replica |
| `trust` | edge navy, open circle at the relying party | authentication / authorization | the artefact: JWKS, OIDC |
| `telemetry` | collector blue, or the signal's colour with `signal:` | logs / metrics / traces / profiles | the protocol: OTLP/HTTP, scrape |

`request` / `storage` / `scaling` remain for hand-authored diagrams. The
`planned` edge style is what a `status: planned` edge of any type becomes.

## Top-down layout

The default for every generated diagram (`scripts/generate.py`), and the
shape to aim for when hand-editing one:

- **Tiers run top to bottom** in the order a request meets them: users → edge
  → platform / applications → data. One IR `layer` is one row, and the primary
  flow reads down the page.
- **Peers sit side by side**, one row per tier: replicas, workers, pipelines,
  stores.
- **Boundaries nest** (cluster → domain → group). A frame owns its boxes, and a
  frame is never used for decoration.
- **Orthogonal edges only.** A horizontal run belongs in the channel between two
  tiers, never through a box. Each run gets its own lane.
- **Labels sit on a vertical run**, where they do not collide. Never on a box,
  on another label, or over a frame title.
- **When it gets crowded:**
  1. split into two views;
  2. collapse repetition into one box;
  3. re-tier or reorder;
  4. only then shrink text or boxes, and never under 10px.

The generator implements these; `validate.py` checks them
([`quality-gates.md`](quality-gates.md)).

### Flow animation (`flowAnimation=1`)

Append `;flowAnimation=1;` to an edge (or use the `request_animated` role in the
preset) to animate the dashes travelling along the connector — a strong cue for
the diagram's **primary** flow direction. Caveats:

- It moves **only in SVG and in the Draw.io editor**. A PNG export is static,
  and GitHub may strip the animation from an embedded SVG. Never let the meaning
  depend on motion.
- Use it **sparingly** — one flow, not every edge. Animating everything is
  noise and defeats the cue.

## Applying it

- Logo box: `python3 ../scripts/icon_style.py style <name> --role <role>` →
  paste as the cell `style`.
- Plain box (no catalogued logo): use `plain_style` / `shapes.card` from the
  preset with the role's fill/stroke/font.
- **`planned` boxes must carry `dashed=1;` in the style as well as the word
  "planned" in the label** — both halves, per
  [AGENTS.md § Diagram workflow](../../../../AGENTS.md#diagram-workflow) step 5.
  `icon_style.py style --role planned` adds `dashed=1` for you; `plain_style` is
  a raw template, so add it by hand there. `validate_house.py` errors on a
  planned-styled box whose label omits the word, and warns on a label that says
  "planned" without the dash.
- Every diagram carries its own **legend** (a small box mapping the roles it
  uses). `validate_house.py` warns when one is missing.

## Legend snippet

A minimal legend box lists only the roles the diagram actually uses, one line
each, coloured swatch + label — so the diagram and the prose beside it read as
one system.
