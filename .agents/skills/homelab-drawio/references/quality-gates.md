# Quality gates

`scripts/validate.py` runs every gate below. It prints a report for a person, or
`--json` for a machine. A diagram ships when it has **no ERROR**. Each WARN is
either fixed, or you can say why it stays. The render is then reviewed by eye,
because no validator sees what a reader sees.

```bash
python3 scripts/validate.py docs/architecture/platform/topology.drawio \
        --ir docs/architecture/platform/topology.ir.yaml          # --json, --strict
```

## Severity

| Severity | Means | Exit |
|---|---|---|
| **ERROR** | The diagram is broken or misleading. | 1 |
| **WARN** | A readability or quality problem. | 0 (1 with `--strict`) |
| **INFO** | Something the gate could not check. | 0 |

Every finding has the same shape, so a fix loop can act on it:

```json
{"severity": "ERROR", "rule_id": "geometry.edge_through_shape",
 "objects": ["e_sec", "cnpg"], "message": "edge passes through 'CloudNativePG operator'",
 "fix": "route it through a free channel (IR `via`) or move the box"}
```

## The gates, in order

| # | Gate | ERROR | WARN |
|---|---|---|---|
| 0 | **house** (`validate_house.py`) | `;base64,` / SVG data URI, logo on a frame, planned style without the word | planned word without the dash, v1 fills / white text / shadows, no legend, no title, unlabelled dashed edge, non-Helvetica |
| 1 | **structural** | duplicate id, broken parent / source / target, parent cycle; with `--ir`: IR schema errors, and `stale_projection` when the file is not exactly what its IR generates | with `--ir`: `layout.unframed_node`, a platform node outside every frame (only `external` nodes belong on the bare canvas) |
| 2 | **connectivity** | edge with no source or target (outside the legend) | orphan box, duplicate edge, unlabelled pair of opposite edges |
| 3 | **geometry** | overlapping boxes, child outside its frame, box on a frame it does not belong to, off-canvas or zero-size cell, edge through an unrelated box | edge crossings, gap under 10px, peers of one layer off their row (`--ir`), edge longer than the canvas |
| 4 | **typography** | — | text wider or taller than its box, font under 10px, box label line over 48 chars, duplicate box names, edge label on a box or a frame title, two edge labels overlapping, an edge drawn through a frame title |
| 5 | **architecture** (`--ir`) | the rules the IR declares in `tests` | — |

Geometry and typography only judge a path that is in the file. A generated
diagram always has one, because `generate.py` writes the route. A hand-drawn
edge with neither waypoints nor ports is left to Draw.io's router and reported
once as `geometry.route_unknown` (INFO).

## Architecture rules

Rules are **declared, never assumed**. A common best practice is still not a
rule here until the IR lists it under `tests`, because what the platform
promises is written down in its ADRs, not in the validator. Unknown rule names
are schema errors, so a typo cannot silently pass.

| Rule | Fails when |
|---|---|
| `no-public-datastore` | an `external` node and a datastore role (`data`, `metric`, `log`, `trace`, `profile`) share an edge |
| `entry-via-edge` | an `external` node (or one listed in `nodes`) enters at anything but an `edge` node |
| `telemetry-has-destination` | a telemetry source's signal, followed along telemetry edges, never reaches a store |
| `gitops-has-reconciler` | a node listed in `nodes` has no incoming `control` edge from a `platform` node |

## Self-check after rendering

Export (`scripts/export.py`) and open the PNG. Work through
[`diagram-types.md` § Review it before you export](diagram-types.md#review-it-before-you-export),
then these questions, which are about the rendered picture rather than the model:

1. Is the top-level boundary obvious at a glance?
2. Does the intended flow read top to bottom without hunting?
3. Are the tiers visibly separate, and peers on one row?
4. Does any arrow cross a box it has nothing to do with?
5. Is every label readable at the README width (960px)?
6. Is any label sitting in the wrong frame?
7. Is there a large empty area, or a crowded corner?
8. Is the diagram overloaded? If so, split it: it is two questions.
9. Is every logo the box's own product (icons.md)?
10. Would a reader who opened only this file know what it covers?

## The fix loop

```
generate → validate → export → look → fix the IR → regenerate
```

- **At most five rounds.** A diagram still wrong after five is usually answering
  two questions: split it.
- **After two rounds of geometry fixes** (re-tiering, reordering, `via`) that do
  not converge, stop and ask the owner. The layout is telling you the model is
  unclear.
- Fix in the IR, never in the generated XML (`structural.stale_projection`).
