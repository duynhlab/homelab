# Diagram IR — the source a diagram is generated from

A homelab Draw.io diagram is written as a small YAML model, the **IR**, and
`scripts/generate.py` projects it into the `.drawio`. The IR says *what* is on
the diagram — boxes, frames, relationships, tiers — and never *where*. Layout is
the generator's job, so a change to the platform is a one-line IR edit instead
of an afternoon of nudging coordinates, and the same IR always gives the same
file.

The IR is the **plan phase made executable**. Everything you would decide before
drawing — the question, the level, the boundaries, the components, what flows
between them, the tier each sits in, which rules must hold — is a field here.
Filling it in is the plan; generating it is the drawing.

The schema is [`../schema/diagram-ir.schema.json`](../schema/diagram-ir.schema.json).
The three committed examples are `docs/architecture/*.ir.yaml`.

## Shape

```yaml
diagram:
  id: topology                    # Draw.io <diagram id>, stable
  title: "duynhlab homelab — Request-path topology"
  scope: "What this covers, and what it leaves to another diagram."
  question: request-path          # one of the five in diagram-types.md
  level: L2                       # L0-L5, diagram-types.md
  pin_order: true                 # optional, see Ordering
  legend:                         # optional wording overrides
    roles: {data: "SQL / object store"}
    edges: {control: "releases (the target's dependsOn)"}
  assumptions: ["..."]            # plan notes; not drawn

layers: [client, edge, apps, workflow, pooling, data]   # top of canvas first

boundaries:                       # frames; may nest via parent
  - {id: f_apps, label: "Applications"}

nodes:
  - {id: envoy, label: "Envoy Gateway\ngateway.duynh.me", role: edge, layer: edge, icon: envoy}
  - {id: svc, label: "10 Go services", role: service, layer: apps, parent: f_apps, icon: go}
  - {id: db, label: "product-db\nHA + DR replica", role: data, layer: data, shape: datastore}
  - {id: search, label: "search (planned)", role: service, layer: apps, parent: f_apps, status: planned}

edges:
  - {id: e1, source: envoy, target: svc, type: traffic, label: HTTPRoute}
  - {id: e2, source: svc, target: db, type: data, protocol: SQL}
  - {id: e3, source: svc, target: otel, type: telemetry, signal: trace}

notes:                            # reading notes under the diagram
  - {id: note, title: "Retention", text: "..."}

tests:                            # architecture rules to enforce
  - {rule: no-public-datastore}
```

| Field | Rule |
|---|---|
| `label` | `\n` breaks the line; the first line is the name and is drawn bold. Keep a line under 48 characters. |
| `role` | One of the twelve palette roles ([house-style.md](house-style.md#semantic-palette)). |
| `layer` | Every node sits in one tier. Peers in a tier share a row. |
| `parent` | A boundary id. The frame owns the box (`container=1`), so moving it moves them. |
| `icon` | A catalogue name ([icons.md](icons.md)). A logo needs a card; a `datastore` cylinder takes none. |
| `status: planned` | Drawn dashed; the label must contain the word `planned` (AGENTS.md step 5). |
| edge `type` | One of eight relationship types ([house-style.md](house-style.md#relationship-types)). |
| edge `status` | `planned` or `optional` draws it dashed, and it must then carry a label. |
| edge `signal` | Telemetry only: colour by metric / log / trace / profile. |
| edge `via`, `label_pos` | Escape hatches: absolute waypoints, or a label position from -1 (source) to 1 (target). |

`generate.py` refuses an IR with any of these wrong, before it draws anything:
- an unknown role or type;
- a dangling edge;
- a parent cycle;
- a planned box without the word "planned";
- a duplicate id across nodes, edges, frames and notes.

## How it is laid out

- **Top-down.** One rank per `layer`, in list order, so the primary flow reads
  down the page and peers sit side by side. Put the tier that *starts* the
  journey first: users, then edge, platform, applications, data.
- **Graphviz `dot` places the boxes.** Boundaries are nested clusters, and dot
  orders peers to reduce crossings.
- **Edges are routed by `generate.py`, not Draw.io.**
  - The gap between two tiers is a *channel*, and each horizontal run in a
    channel gets its own lane.
  - Ports are spread along the side an edge leaves from, ordered by where it goes.
  - An edge that skips a tier passes that tier through the free slot dot kept for
    it.
  - The route is written into the file, so `validate.py` checks the path a reader
    will actually see.
- **Labels are placed**, not left at the path's middle. Each label goes on its
  edge's longest vertical run, then on any other run long enough for it. It
  avoids boxes, frame titles and labels placed before it.
- **Title, scope, notes and legend are generated.** The legend lists only the
  roles and edge types this IR uses.

### Ordering

By default dot orders each tier to minimise crossings, which is usually the
better picture. Set `diagram.pin_order: true` when a reading order matters more
than one crossing. The generator then starts from the IR's order and all but
switches off dot's reordering.

A flat edge between two peers still decides their order: its source goes left.
List the nodes of one boundary together, or the frame cannot be contiguous.

Neither option is always right. `validate.py` counts crossings, so try both:
- on 2026-09-28 the topology read best pinned (8 crossings against 12);
- the signal-flow and delivery diagrams read best with dot's own order (12 and 6).

## When the picture is wrong

Fix it in the IR, regenerate, re-validate. In order of preference:

1. **Split the view.** More than one question, or more than ~25 boxes, is two
   diagrams.
2. **Re-tier.** A node in the wrong layer causes long upward edges and
   crossings. Moving it one tier is usually the whole fix.
3. **Reorder peers**, then use `pin_order`.
4. **Collapse repetition.** Ten services that behave alike are one box whose
   label says ten.
5. **Only then** use `via` or `label_pos` for a single edge.

Hand-editing the generated `.drawio` is not a fix. `validate.py --ir` fails a
file that no longer matches its IR (`structural.stale_projection`), and the next
regeneration would silently undo the edit anyway.

## Diagrams without an IR

A `.drawio` authored by hand before this pipeline, or one that needs free-form
geometry the IR cannot express, stays hand-edited. `validate.py` still runs
every gate except the architecture rules and the stale check. Its edges are
checked only where their path is in the file (waypoints or ports); the rest are
reported once as `geometry.route_unknown`.
