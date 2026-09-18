# Homelab Draw.io house style

The visual language every homelab `.drawio` follows. The goal is one system: a
Draw.io diagram and the Mermaid diagram beside it use the **same semantic
colours**, so a reader learns the palette once. The machine-readable source is
[`../assets/homelab.json`](../assets/homelab.json); this file explains how to
apply it. When they disagree, the JSON wins — and the JSON must track the Mermaid
`classDef` block in [AGENTS.md](../../../../AGENTS.md § Diagram workflow, step 4).

## Semantic palette

Each role carries a fill, a stroke, and the font colour that stays legible on
that fill — all three copied from the AGENTS.md `classDef` verbatim.

| Role | Fill | Stroke | Font | Use for |
|---|---|---|---|---|
| `edge` | `#2563EB` | `#1E3A8A` | `#FFFFFF` | Envoy Gateway, ingress, the edge |
| `service` | `#06B6D4` | `#0E7490` | `#082F49` | platform / app services |
| `worker` | `#F59E0B` | `#B45309` | `#451A03` | Temporal workers, async processors |
| `platform` | `#7C3AED` | `#5B21B6` | `#FFFFFF` | control-plane controllers (Flux, KEDA, operators) |
| `data` | `#22C55E` | `#15803D` | `#052E16` | datastores (Postgres, Valkey, ClickHouse, buckets) |
| `external` | `#64748B` | `#334155` | `#FFFFFF` | third-party / off-platform |
| `metric` | `#FFE8CC` | `#E8590C` | `#111111` | observability: metrics (VictoriaMetrics) |
| `log` | `#D3F9D8` | `#2F9E44` | `#111111` | observability: logs (VictoriaLogs) |
| `trace` | `#C5F6FA` | `#0C8599` | `#111111` | observability: traces (VictoriaTraces) |
| `profile` | `#F3D9FA` | `#9C36B5` | `#111111` | observability: profiles (Pyroscope) |
| `collector` | `#A5D8FF` | `#1971C2` | `#111111` | observability: collectors (Vector, OTel) |
| `planned` | `#FFFFFF` | `#64748B` | `#475569` | not-yet-deployed — **always dashed** |

Do not invent decorative per-node colours, and never rely on colour alone to
carry meaning (label the state too).

## Shapes

- **Card** (a component): the `shapes.card` prefix — rounded, subtle shadow,
  wrap. With a logo it becomes a `shape=label` (logo left, text right); the
  `icon_style.py` output already encodes this.
- **Container / domain frame**: the `shapes.container` prefix — rounded, top-
  aligned title, no shadow. A frame groups; it never carries a logo.
- **Datastore**: `shape=cylinder3` (`shapes.datastore`), always the `data` role.

Fonts: **Helvetica** everywhere (web-safe, resolves locally, so SVG export needs
no embedded font). Titles use `fontSize=13; fontStyle=1`.

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
- Every diagram carries its own **legend** (a small box mapping the roles it
  uses). `validate_house.py` warns when one is missing.

## Legend snippet

A minimal legend box lists only the roles the diagram actually uses, one line
each, coloured swatch + label — so the diagram and the prose beside it read as
one system.
