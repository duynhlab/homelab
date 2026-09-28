#!/usr/bin/env python3
"""generate.py -- project a Diagram IR (.ir.yaml) into a top-down homelab .drawio.

The IR is the source of truth (references/ir.md); the .drawio is its
projection, so a change is made in the IR and the file regenerated, never
hand-edited. Output is deterministic: the same IR gives the same bytes, which
is what lets validate.py prove a committed .drawio still matches its IR.

Layout, top-down:
  * Graphviz `dot` places the boxes: one rank per IR layer (top of the list =
    top of the canvas), boundaries as nested clusters, peers side by side.
  * Edges are routed here, not by Draw.io, so their path is written into the
    file and can be checked. A gap between two layers is a routing channel;
    each horizontal run in a channel gets its own lane, ports are spread along
    the side they leave from, and an edge that skips a layer passes it through
    the free slot dot reserved for it.

Usage: generate.py <file.ir.yaml> [-o <file.drawio>] [--check]
  --check   exit 1 if <file.drawio> differs from what the IR generates
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import math
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

import yaml

from _common import (
    SCHEMA,
    load_manifest,
    load_preset,
    resolve_icon,
    role_style,
    text_width,
)

GRID = 10
MARGIN_X = 40          # canvas left margin
TOP = 100              # title + scope band above the diagram
NODESEP = 0.5          # inches between peers
RANKSEP = 1.25         # inches between layers: the routing channel
FRAME_PAD = 18         # points of cluster margin around its children
FRAME_TITLE_H = 24     # px Draw.io needs for a frame title
PAD_TEXT = 14          # px of horizontal padding inside a card
ICON_PAD = 44          # px the logo takes on the left of a card
LINE_H = 1.3           # line height, in em
LANE_MIN = 10          # px between two lanes in a channel
EDGE_FONT = 10

LEGEND_ROLE = {
    "edge": "Edge / gateway", "service": "Service", "worker": "Worker",
    "platform": "Platform controller", "data": "Datastore", "external": "External / off-platform",
    "metric": "Metrics store", "log": "Logs store", "trace": "Traces store",
    "profile": "Profiles store", "collector": "Collector", "planned": "planned (not deployed)",
}
LEGEND_EDGE = {
    "traffic": "request / traffic", "data": "reads · writes", "control": "manages / reconciles",
    "dependency": "depends on", "event": "async event", "replication": "replication",
    "trust": "trust / authentication", "telemetry": "telemetry",
}
SIGNAL_LABEL = {"metric": "metrics", "log": "logs", "trace": "traces", "profile": "profiles"}


class IRError(Exception):
    def __init__(self, problems: list[tuple[str, list[str], str]]):
        self.problems = problems
        super().__init__("; ".join(p[2] for p in problems))


# --------------------------------------------------------------------------- IR

class _StrictLoader(yaml.SafeLoader):
    """SafeLoader that refuses a repeated mapping key. PyYAML keeps the last
    one silently, so a pasted-twice `nodes:` block would quietly win over the
    one you edited."""


def _no_duplicates(loader: yaml.SafeLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None, None, f"duplicate key '{key}'", key_node.start_mark)
        seen.add(key)
    return loader.construct_mapping(node, deep)


_StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates)


def load_ir(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return yaml.load(fh, Loader=_StrictLoader)  # noqa: S506 - SafeLoader subclass


def ir_problems(ir: dict) -> list[tuple[str, list[str], str]]:
    """Schema + referential checks. Each problem is (rule_id, objects, message)."""
    out: list[tuple[str, list[str], str]] = []
    try:
        import jsonschema
        with open(SCHEMA, encoding="utf-8") as fh:
            schema = json.load(fh)
        for err in sorted(jsonschema.Draft202012Validator(schema).iter_errors(ir), key=lambda e: list(e.path)):
            where = "/".join(str(p) for p in err.path) or "(root)"
            out.append(("ir.schema", [where], f"{where}: {err.message}"))
    except ImportError:
        out.append(("ir.schema", [], "jsonschema not installed -- cannot validate the IR shape"))
    if out:
        return out

    layers = ir["layers"]
    bounds = {b["id"]: b for b in ir.get("boundaries", [])}
    nodes = {n["id"]: n for n in ir["nodes"]}
    seen: dict[str, str] = {}
    for kind, items in (("boundary", ir.get("boundaries", [])), ("node", ir["nodes"]), ("edge", ir["edges"]),
                        ("note", ir.get("notes", []))):
        for it in items:
            if it["id"] in seen:
                out.append(("structural.duplicate_id", [it["id"]], f"id '{it['id']}' used by a {seen[it['id']]} and a {kind}"))
            seen[it["id"]] = kind
    for b in bounds.values():
        if b.get("parent") and b["parent"] not in bounds:
            out.append(("structural.broken_parent", [b["id"]], f"boundary '{b['id']}' parent '{b['parent']}' is not a boundary"))
    for bid in bounds:  # parent cycles
        chain, cur = [], bid
        while cur and cur not in chain:
            chain.append(cur)
            cur = bounds.get(cur, {}).get("parent")
        if cur:
            out.append(("structural.parent_cycle", chain, f"boundary parent cycle through {' -> '.join(chain)}"))
            break
    manifest = load_manifest()
    icons = set(manifest.get("icons", {})) | set(manifest.get("aliases", {}))
    for n in nodes.values():
        if n["layer"] not in layers:
            out.append(("structural.unknown_layer", [n["id"]], f"node '{n['id']}' layer '{n['layer']}' is not in layers"))
        if n.get("parent") and n["parent"] not in bounds:
            out.append(("structural.broken_parent", [n["id"]], f"node '{n['id']}' parent '{n['parent']}' is not a boundary"))
        if n.get("icon") and n["icon"] not in icons:
            out.append(("structural.unknown_icon", [n["id"]], f"node '{n['id']}' icon '{n['icon']}' is not in the catalogue"))
        if n.get("icon") and n.get("shape") == "datastore":
            out.append(("structural.icon_on_datastore", [n["id"]], f"node '{n['id']}': a logo needs a card, not a cylinder"))
        planned = n.get("status") == "planned" or n["role"] == "planned"
        if planned and "planned" not in n["label"].lower():
            out.append(("house.planned_label", [n["id"]], f"node '{n['id']}' is planned but its label omits the word 'planned'"))
    for e in ir["edges"]:
        if e["source"] not in nodes:
            out.append(("connectivity.dangling_edge", [e["id"]], f"edge '{e['id']}' source '{e['source']}' is not a node"))
        if e["target"] not in nodes and e["target"] not in bounds:
            out.append(("connectivity.dangling_edge", [e["id"]],
                        f"edge '{e['id']}' target '{e['target']}' is neither a node nor a boundary"))
        elif e["target"] in bounds and e.get("via"):
            out.append(("structural.frame_edge_via", [e["id"]], f"edge '{e['id']}' into a frame cannot take `via`"))
        if e.get("status") in ("planned", "optional") and not (e.get("label") or e.get("protocol")):
            out.append(("house.dashed_unlabelled", [e["id"]], f"edge '{e['id']}' is {e['status']} (dashed) and needs a label"))
        if e.get("status") == "planned" and "planned" not in (e.get("label") or "").lower():
            out.append(("house.planned_label", [e["id"]], f"edge '{e['id']}' is planned but its label omits the word 'planned'"))
        if e.get("signal") and e["type"] != "telemetry":
            out.append(("structural.signal_type", [e["id"]], f"edge '{e['id']}': `signal` only applies to telemetry edges"))
    return out


# ----------------------------------------------------------------------- sizing

def _ceil(v: float, g: int = GRID) -> int:
    return int(math.ceil(v / g) * g)


def _snap(v: float, g: int = GRID) -> int:
    return int(math.floor(v / g + 0.5) * g)


def node_size(n: dict, font_size: int) -> tuple[int, int]:
    lines = n["label"].split("\n")
    multi = len(lines) > 1
    tw = max(text_width(l, font_size, bold=multi and i == 0) for i, l in enumerate(lines))
    pad = (ICON_PAD if n.get("icon") else PAD_TEXT) + PAD_TEXT
    w = max(120, _ceil(tw + pad + 4))
    h = max(40, _ceil(len(lines) * font_size * LINE_H + 18))
    if n.get("shape") == "datastore":
        w, h = max(w, 120), h + 20
    return n.get("w", w), n.get("h", h)


def label_html(label: str) -> str:
    lines = [html.escape(l, quote=False) for l in label.split("\n")]
    if len(lines) > 1:
        lines[0] = f"<b>{lines[0]}</b>"
    return "<br>".join(lines)


# ----------------------------------------------------------------------- layout

def _dot_id(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_dot(ir: dict, sizes: dict[str, tuple[int, int]], flat_labels: bool = True) -> str:
    layers = ir["layers"]
    li = {n["id"]: layers.index(n["layer"]) for n in ir["nodes"]}
    bounds = ir.get("boundaries", [])
    # pin_order: start from the IR's left-to-right order and all but switch off
    # dot's crossing minimisation (mclimit), so the author's order survives. A
    # flat edge between two peers still wins -- its source goes left.
    pin = "mclimit=0.001, " if ir["diagram"].get("pin_order") else ""
    out = [
        "digraph G {",
        f"graph [{pin}rankdir=TB, newrank=true, nodesep={NODESEP}, ranksep={RANKSEP}, "
        'splines=spline, fontname="Helvetica-Bold", fontsize=13];',
        'node [shape=box, fixedsize=true, label=""];',
        "edge [arrowhead=none];",
    ]

    def emit(parent: str | None) -> None:
        for b in bounds:
            if b.get("parent") == parent:
                out.append(f"subgraph {_dot_id('cluster_' + b['id'])} {{")
                out.append(f"graph [label={_dot_id(b['label'])}, labeljust=l, margin={FRAME_PAD}];")
                emit(b["id"])
                out.append("}")
        for n in ir["nodes"]:
            if n.get("parent") == parent:
                w, h = sizes[n["id"]]
                out.append(f"{_dot_id(n['id'])} [width={w / 72:.4f}, height={h / 72:.4f}];")

    emit(None)
    # One invisible anchor per layer, chained, pins the layer order even
    # between two layers no edge connects.
    for i in range(len(layers)):
        out.append(f'"__L{i}" [shape=point, width=0.01, height=0.01, style=invis];')
    for i in range(len(layers) - 1):
        out.append(f'"__L{i}" -> "__L{i + 1}" [style=invis];')
    for i, layer in enumerate(layers):
        ids = [n["id"] for n in ir["nodes"] if n["layer"] == layer]
        out.append(f'{{rank=same; "__L{i}"; {" ".join(_dot_id(x) for x in ids)}}}')
        if ir["diagram"].get("pin_order"):
            # Invisible flat edges fix the left-to-right order to the IR's.
            for a, b in zip(ids, ids[1:]):
                out.append(f"{_dot_id(a)} -> {_dot_id(b)} [style=invis, weight=0];")
    for e in ir["edges"]:
        if e["target"] not in li:
            continue  # an edge into a whole frame is routed after layout
        attrs = [f"id={_dot_id(e['id'])}"]
        if li[e["target"]] < li[e["source"]]:
            attrs.append("constraint=false")  # an upward edge must not re-rank the layers
        elif flat_labels and li[e["target"]] == li[e["source"]] and (e.get("label") or e.get("protocol")):
            # A flat edge's label sits between the two boxes: let dot keep room for it.
            attrs.append(f'label={_dot_id(_edge_label(e))}, fontname="Helvetica", fontsize={EDGE_FONT}')
        out.append(f"{_dot_id(e['source'])} -> {_dot_id(e['target'])} [{', '.join(attrs)}];")
    out.append("}")
    return "\n".join(out)


def _edge_label(e: dict) -> str:
    label = e.get("label") or ""
    if e.get("protocol"):
        label = f"{label} ({e['protocol']})" if label else e["protocol"]
    return label


def layout_dot(ir: dict, sizes: dict[str, tuple[int, int]]) -> dict:
    """dot with room reserved for flat-edge labels; without it if dot's spline
    router rejects the labelled flat edges (a known `routesplines` failure)."""
    try:
        return run_dot(build_dot(ir, sizes))
    except SystemExit:
        return run_dot(build_dot(ir, sizes, flat_labels=False))


def run_dot(src: str) -> dict:
    dot = shutil.which("dot")
    if not dot:
        raise SystemExit("generate.py: Graphviz `dot` not found -- sudo apt install graphviz (brew install graphviz)")
    res = subprocess.run([dot, "-Tjson"], input=src, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise SystemExit(f"generate.py: dot failed: {res.stderr.strip()}")
    return json.loads(res.stdout)


def _spline_points(pos: str) -> list[tuple[float, float]]:
    # dot writes one spline per piece, separated by ';' (an edge split around
    # a flat label or a cluster), each with optional e,/s, arrow endpoints.
    pts = []
    for tok in pos.replace(";", " ").split():
        if tok.startswith(("e,", "s,")):
            continue
        x, y = tok.split(",")
        pts.append((float(x), float(y)))
    return pts


def _x_at(poly: list[tuple[float, float]], y: float) -> float | None:
    for (x1, y1), (x2, y2) in zip(poly, poly[1:]):
        if min(y1, y2) <= y <= max(y1, y2) and y1 != y2:
            return x1 + (x2 - x1) * (y - y1) / (y2 - y1)
    return None


class Layout:
    """Absolute boxes for nodes and frames, plus the routing channels."""

    def __init__(self, ir: dict, sizes: dict[str, tuple[int, int]], dot: dict):
        self.ir = ir
        H = float(dot["bb"].split(",")[3])
        self.box: dict[str, list[int]] = {}      # id -> [x, y, w, h] absolute
        self.frame: dict[str, list[int]] = {}
        self.spline: dict[str, list[tuple[float, float]]] = {}
        names = {o["_gvid"]: o["name"] for o in dot.get("objects", [])}
        for o in dot.get("objects", []):
            name = o["name"]
            if name.startswith("cluster_"):
                llx, lly, urx, ury = (float(v) for v in o["bb"].split(","))
                x0, y0 = math.floor(llx / GRID) * GRID, math.floor((H - ury) / GRID) * GRID
                self.frame[name[len("cluster_"):]] = [
                    x0 + MARGIN_X, y0 + TOP, _ceil(urx) - x0, _ceil(H - lly) - y0]
            elif name in sizes:
                cx, cy = (float(v) for v in o["pos"].split(","))
                w, h = sizes[name]
                cx, cy = _snap(cx), _snap(H - cy)
                self.box[name] = [cx - w // 2 + MARGIN_X, cy - h // 2 + TOP, w, h]
        for e in dot.get("edges", []):
            eid = e.get("id")
            if eid and "pos" in e:
                self.spline[eid] = [(x + MARGIN_X, H - y + TOP) for x, y in _spline_points(e["pos"])]
        self._frames_fit_children()
        self._normalise()
        self.layers = ir["layers"]
        self.li = {n["id"]: self.layers.index(n["layer"]) for n in ir["nodes"]}
        self.rows = []
        for i in range(len(self.layers)):
            members = [self.box[n] for n in self.box if self.li[n] == i]
            self.rows.append((min(b[1] for b in members), max(b[1] + b[3] for b in members)) if members else None)

    def _normalise(self) -> None:
        # dot's bounding box includes the invisible layer anchors and cluster
        # label space; pull the drawing up/left so it starts right under the
        # title band, whatever dot reserved.
        rects = list(self.box.values()) + list(self.frame.values())
        # Spline points count too: a skip-layer edge's detour becomes a waypoint.
        xs = [r[0] for r in rects] + [x for pts in self.spline.values() for x, _ in pts]
        dx = MARGIN_X - min(xs)
        dy = TOP - min(r[1] for r in rects)
        for r in rects:
            r[0] += dx
            r[1] += dy
        self.spline = {k: [(x + dx, y + dy) for x, y in v] for k, v in self.spline.items()}

    def _frames_fit_children(self) -> None:
        # Snapping can nudge a child past its frame edge; grow the frame instead.
        bounds = {b["id"]: b for b in self.ir.get("boundaries", [])}
        depth = {}
        for bid in bounds:
            d, cur = 0, bounds[bid].get("parent")
            while cur:
                d, cur = d + 1, bounds[cur].get("parent")
            depth[bid] = d
        for bid in sorted(bounds, key=lambda b: -depth[b]):
            f = self.frame.get(bid)
            if not f:
                continue
            kids = [self.box[n["id"]] for n in self.ir["nodes"] if n.get("parent") == bid]
            kids += [self.frame[b] for b in bounds if bounds[b].get("parent") == bid and b in self.frame]
            if not kids:
                continue
            x0 = min(f[0], min(k[0] for k in kids) - 10)
            y0 = min(f[1], min(k[1] for k in kids) - FRAME_TITLE_H - 10)
            x1 = max(f[0] + f[2], max(k[0] + k[2] for k in kids) + 10)
            y1 = max(f[1] + f[3], max(k[1] + k[3] for k in kids) + 10)
            self.frame[bid] = [x0, y0, x1 - x0, y1 - y0]

    def _titles_opening(self, layer: int) -> list[tuple[float, float]]:
        """Title x-spans of frames whose top border lies just above `layer`:
        a vertical run through that layer crosses those borders."""
        if not self.rows[layer]:
            return []
        top = self.rows[layer][0]
        above = self.rows[layer - 1][1] if layer > 0 and self.rows[layer - 1] else top - 200
        labels = {b["id"]: b["label"] for b in self.ir.get("boundaries", [])}
        return [(f[0], f[0] + text_width(labels.get(fid, ""), 13, bold=True) + 30)
                for fid, f in self.frame.items() if above <= f[1] <= top]

    def frame_title(self, fid: str) -> list[tuple[float, float, float]]:
        label = next((b["label"] for b in self.ir.get("boundaries", []) if b["id"] == fid), "")
        f = self.frame[fid]
        return [(f[0], f[0] + text_width(label, 13, bold=True) + 30, f[1])]

    def ancestor_titles(self, nid: str) -> list[tuple[float, float, float]]:
        """(x0, x1, frame top) of the title text of every frame around `nid`."""
        bounds = {b["id"]: b for b in self.ir.get("boundaries", [])}
        parent = {n["id"]: n.get("parent") for n in self.ir["nodes"]}.get(nid)
        spans = []
        while parent:
            f = self.frame.get(parent)
            if f:
                spans.append((f[0], f[0] + text_width(bounds[parent]["label"], 13, bold=True) + 30, f[1]))
            parent = bounds[parent].get("parent")
        return spans

    def channel(self, upper: int) -> tuple[float, float]:
        """Free vertical band between layer `upper` and `upper + 1`."""
        lo, hi = self.rows[upper][1], self.rows[upper + 1][0]
        raw = (lo, hi)
        for x, y, w, h in self.frame.values():
            if lo < y + h <= hi:
                lo = max(lo, y + h)
            if lo <= y < hi:
                hi = min(hi, y)
        if hi - lo >= 2 * LANE_MIN:
            return (lo, hi)
        # Frames touch, so there is no gap between them. Run the lanes inside
        # the lower frame instead, but never in a frame's title band.
        free, cur = [], raw[0]
        for y0, y1 in sorted((f[1], f[1] + FRAME_TITLE_H + 2) for f in self.frame.values()
                             if raw[0] <= f[1] < raw[1]):
            if y0 > cur:
                free.append((cur, y0))
            cur = max(cur, y1)
        if raw[1] > cur:
            free.append((cur, raw[1]))
        return max(free, key=lambda r: (r[1] - r[0], -r[0])) if free else raw

    def free_x(self, layer: int, x: float, exclude: set[str]) -> float:
        """Nearest x in `layer` whose vertical line hits no node."""
        spans = sorted([(b[0], b[0] + b[2]) for n, b in self.box.items()
                        if self.li[n] == layer and n not in exclude] + self._titles_opening(layer))
        if all(not (a - 10 < x < b + 10) for a, b in spans):
            return x
        gaps, prev = [], -1e9
        for a, b in spans:
            gaps.append((prev + 10, a - 10))
            prev = b
        gaps.append((prev + 10, 1e9))
        best = min((g for g in gaps if g[1] - g[0] >= 0),
                   key=lambda g: min(abs(x - max(g[0], min(x, g[1]))), 1e9))
        lo, hi = best
        return _snap(max(lo, min(x, hi)) if hi < 1e8 else max(lo, x))


# ---------------------------------------------------------------------- routing

def _widest_free(lo: float, hi: float, spans: list[tuple[float, float]]) -> tuple[float, float]:
    """The widest part of [lo, hi] outside every span (10px clear of each);
    [lo, hi] itself when nothing usable (20px) is left."""
    free, cur = [], lo
    for a, b in sorted((a - 10, b + 10) for a, b in spans if a < hi and b > lo):
        if a > cur:
            free.append((cur, a))
        cur = max(cur, b)
    if hi > cur:
        free.append((cur, hi))
    best = max(free, key=lambda r: r[1] - r[0], default=None)
    return best if best and best[1] - best[0] >= 20 else (lo, hi)


def _route_into_frame(lay: Layout, sb: list, fr: list, title: list) -> dict:
    """An edge that stands for "every box in this frame": from the bottom of the
    source to the top border of the frame, clear of the frame's title."""
    sx = sb[0] + sb[2] / 2
    lo, hi = _widest_free(fr[0] + 20, fr[0] + fr[2] - 20, title)
    tx = _snap(max(lo, min(sx, hi)), 5)
    ports = ((sx - sb[0]) / sb[2], 1, (tx - fr[0]) / fr[2], 0)
    if abs(tx - sx) < 1:
        return {"points": [], "ports": ports}
    y = _snap((sb[1] + sb[3] + fr[1]) / 2, 5)
    return {"points": [(sx, y), (tx, y)], "ports": ports}


def route_edges(ir: dict, lay: Layout) -> dict[str, dict]:
    """Per edge: ports (exit/entry fractions) and absolute waypoints."""
    routes: dict[str, dict] = {}
    plans = []
    for e in ir["edges"]:
        s, t = e["source"], e["target"]
        if t in lay.frame:
            routes[e["id"]] = _route_into_frame(lay, lay.box[s], lay.frame[t],
                                                [(a, b) for a, b, _ in lay.frame_title(t)])
            continue
        ls, lt = lay.li[s], lay.li[t]
        sb, tb = lay.box[s], lay.box[t]
        if e.get("via"):
            routes[e["id"]] = {"points": [tuple(p) for p in e["via"]], "ports": None}
            continue
        if ls == lt:
            # Facing sides with nothing between: a straight side-to-side run.
            left, right = (sb, tb) if sb[0] < tb[0] else (tb, sb)
            y = (max(sb[1], tb[1]) + min(sb[1] + sb[3], tb[1] + tb[3])) / 2
            blocked = any(n not in (s, t) and lay.li[n] == ls and left[0] + left[2] <= b[0] < right[0]
                          and b[1] < y < b[1] + b[3] for n, b in lay.box.items())
            if not blocked and max(sb[1], tb[1]) < min(sb[1] + sb[3], tb[1] + tb[3]):
                sx = 1 if sb[0] < tb[0] else 0
                routes[e["id"]] = {"points": [], "ports": (sx, (y - sb[1]) / sb[3], 1 - sx, (y - tb[1]) / tb[3])}
                continue
            down = ls + 1 < len(lay.layers) and lay.rows[ls + 1] is not None
            chans = [ls if down else ls - 1]
            plans.append((e, "bottom" if down else "top", "bottom" if down else "top", chans, []))
            continue
        step = 1 if lt > ls else -1
        chans = [i if step == 1 else i - 1 for i in range(ls, lt, step)]
        mids = []
        poly = lay.spline.get(e["id"], [])
        for k in range(ls + step, lt, step):
            ky = sum(lay.rows[k]) / 2
            x = _x_at(poly, ky)
            if x is None:
                x = (sb[0] + sb[2] / 2 + tb[0] + tb[2] / 2) / 2
            mids.append(lay.free_x(k, _snap(x), {s, t}))
        plans.append((e, "bottom" if step == 1 else "top", "top" if step == 1 else "bottom", chans, mids))

    # Spread ports along each side, ordered by where the edge goes next, so
    # parallel edges neither overlap nor cross at the box.
    side_edges: dict[tuple[str, str], list[tuple[float, str, str]]] = {}
    for e, s_side, t_side, chans, mids in plans:
        tb, sb = lay.box[e["target"]], lay.box[e["source"]]
        toward_t = mids[0] if mids else tb[0] + tb[2] / 2
        toward_s = mids[-1] if mids else sb[0] + sb[2] / 2
        side_edges.setdefault((e["source"], s_side), []).append((toward_t, e["id"], "exit"))
        side_edges.setdefault((e["target"], t_side), []).append((toward_s, e["id"], "entry"))
    port_x: dict[tuple[str, str], float] = {}
    for (nid, side), items in side_edges.items():
        b = lay.box[nid]
        items.sort(key=lambda it: (it[0], it[1]))
        # Keep ports clear of the title text of every frame the vertical run
        # crosses: the frames around the box for a top port, the frames that
        # open just below the box's layer for a bottom port.
        spans = ([(a, b) for a, b, _ in lay.ancestor_titles(nid)] if side == "top"
                 else lay._titles_opening(lay.li[nid] + 1) if lay.li[nid] + 1 < len(lay.layers) else [])
        lo, hi = _widest_free(b[0], b[0] + b[2], spans)
        k = len(items)
        for i, (_, eid, which) in enumerate(items):
            x = lo + _snap((hi - lo) * (i + 1) / (k + 1), 5)
            port_x[(eid, which)] = x

    # Horizontal runs per channel, then one lane per overlapping run.
    runs: dict[int, list[list]] = {}
    for e, s_side, t_side, chans, mids in plans:
        xs = [port_x[(e["id"], "exit")], *mids, port_x[(e["id"], "entry")]]
        for j, c in enumerate(chans):
            a, b = xs[j], xs[j + 1]
            runs.setdefault(c, []).append([min(a, b), max(a, b), e["id"], j, None])
    lane_y: dict[tuple[str, int], float] = {}
    for c, items in sorted(runs.items()):
        items.sort(key=lambda r: (r[0], r[1], r[2]))
        lanes: list[float] = []
        for r in items:
            for k, end in enumerate(lanes):
                if r[0] > end + LANE_MIN:
                    lanes[k] = r[1]
                    r[4] = k
                    break
            else:
                lanes.append(r[1])
                r[4] = len(lanes) - 1
        lo, hi = lay.channel(c)
        n = len(lanes)
        for r in items:
            lane_y[(r[2], r[3])] = _snap(lo + (hi - lo) * (r[4] + 1) / (n + 1), 5)

    for e, s_side, t_side, chans, mids in plans:
        eid = e["id"]
        xs = [port_x[(eid, "exit")], *mids, port_x[(eid, "entry")]]
        pts = []
        for j in range(len(chans)):
            y = lane_y[(eid, j)]
            pts += [(xs[j], y), (xs[j + 1], y)]
        if t_side == "top" and pts:
            # The box sits under a frame title no port can avoid: come down
            # beside the title and run in under it, inside the frame.
            px, lane = xs[-1], pts[-1][1]
            for x0, x1, fy in lay.ancestor_titles(e["target"]):
                if x0 - 10 < px < x1 + 10 and lane < fy:
                    y_in = fy + FRAME_TITLE_H + 6
                    pts[-1:] = [(x1 + 10, lane), (x1 + 10, y_in), (px, y_in)]
                    break
        sb, tb = lay.box[e["source"]], lay.box[e["target"]]
        ports = ((xs[0] - sb[0]) / sb[2], 1 if s_side == "bottom" else 0,
                 (xs[-1] - tb[0]) / tb[2], 1 if t_side == "bottom" else 0)
        routes[eid] = {"points": pts, "ports": ports}
    return routes


# ------------------------------------------------------------------------ emit

def _style(template: str, role: str, dashed: bool, icon: str | None, font: dict) -> str:
    rs = role_style(role)
    fmt = dict(dashed="dashed=1;" if dashed else "", fillColor=rs["fillColor"], strokeColor=rs["strokeColor"],
               fontColor=rs["fontColor"], fontFamily=font["fontFamily"], fontSize=font["fontSize"])
    if icon:
        path, _ = resolve_icon(icon)
        with open(path, "rb") as fh:
            fmt["payload"] = base64.b64encode(fh.read()).decode()
    return template.format(**fmt)


def node_style(n: dict, P: dict) -> str:
    font = P["font"]
    dashed = n.get("status") == "planned" or n["role"] == "planned"
    if n.get("shape") == "datastore":
        rs = role_style(n["role"])
        return (P["shapes"]["datastore"] + ("dashed=1;" if dashed else "") +
                f"size=8;fillColor={rs['fillColor']};strokeColor={rs['strokeColor']};strokeWidth=1.5;"
                f"fontColor={rs['fontColor']};fontFamily={font['fontFamily']};fontSize={font['fontSize']};")
    if n.get("icon"):
        return _style(P["label_style"], n["role"], dashed, n["icon"], font)
    return _style(P["plain_style"].replace("rounded=1;", "rounded=1;{dashed}", 1), n["role"], dashed, None, font)


def animated(e: dict, ir: dict) -> bool:
    """Primary-flow edges move in the SVG. A dashed (planned/optional) edge
    never does: moving dashes would read as flow, and it is not one."""
    if e.get("status") in ("planned", "optional"):
        return False
    return e.get("animate", e["type"] in ir["diagram"].get("animate", []))


def edge_style(e: dict, P: dict, ir: dict | None = None) -> str:
    edges = P["edges"]
    if e.get("status") == "planned":
        st = edges["planned"]
    else:
        st = edges[e["type"]] + ("dashed=1;" if e.get("status") == "optional" else "")
    if ir is not None and animated(e, ir):
        st += "flowAnimation=1;"
    if e.get("signal"):
        stroke = role_style(e["signal"])["strokeColor"]
        st = _replace_attr(st, "strokeColor", stroke)
    return st + (f"fontFamily={P['font']['fontFamily']};fontSize={EDGE_FONT};fontColor=#334155;"
                 "labelBackgroundColor=#FFFFFF;endSize=6;")


def _replace_attr(style: str, key: str, value: str) -> str:
    parts = [p for p in style.split(";") if p and not p.startswith(key + "=")]
    return ";".join(parts + [f"{key}={value}"]) + ";"


def _path(lay: Layout, e: dict, r: dict) -> list[tuple[float, float]]:
    sb, tb = lay.box[e["source"]], lay.box.get(e["target"]) or lay.frame[e["target"]]
    ex, ey, nx, ny = r["ports"]
    return [(sb[0] + sb[2] * ex, sb[1] + sb[3] * ey), *r["points"], (tb[0] + tb[2] * nx, tb[1] + tb[3] * ny)]


def _hits(a: list[float], b: list[float]) -> bool:
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def place_labels(ir: dict, lay: Layout, routes: dict[str, dict]) -> dict[str, float]:
    """Pick each edge label's position (-1..1 along its path) so it lands on
    no box and no label placed before it.

    Candidates are the middle, then the 30 % and 70 % points, of each segment
    long enough to carry the label -- vertical runs first, longest first,
    because in a top-down diagram verticals sit at distinct x while horizontal
    runs share a channel a few px apart. The first free candidate wins; with
    none free, the first candidate is kept and validate.py reports it."""
    placed: list[list[float]] = []
    # Boxes, plus each frame's title band -- a label there hides the frame's name.
    titles = {b["id"]: b["label"] for b in ir.get("boundaries", [])}
    boxes = list(lay.box.values()) + [
        [f[0], f[1], min(f[2], text_width(titles.get(fid, ""), 13, bold=True) + 30), FRAME_TITLE_H]
        for fid, f in lay.frame.items()]
    out: dict[str, float] = {}
    for e in ir["edges"]:
        label, r = _edge_label(e), routes[e["id"]]
        if not label or not r["ports"] or e.get("label_pos") is not None:
            continue
        poly = _path(lay, e, r)
        segs = [math.dist(a, b) for a, b in zip(poly, poly[1:])]
        total = sum(segs)
        if total == 0:
            continue
        w, h = text_width(label, EDGE_FONT) + 6, 16
        cands = []
        for k, (p, q) in enumerate(zip(poly, poly[1:])):
            vertical = abs(p[0] - q[0]) < 1
            if segs[k] < (h + 8 if vertical else w + 8):
                continue
            for f in (0.5, 0.3, 0.7):
                cands.append((0 if vertical else 1, -segs[k], k, f))
        cands.sort()
        chosen = None
        for _, _, k, f in cands:
            p, q = poly[k], poly[k + 1]
            cx, cy = p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f
            box = [cx - w / 2, cy - h / 2, w, h]
            pos = 2 * (sum(segs[:k]) + segs[k] * f) / total - 1
            if chosen is None:
                chosen = (pos, box)
            if not any(_hits(box, b) for b in boxes) and not any(_hits(box, b) for b in placed):
                chosen = (pos, box)
                break
        if chosen:
            out[e["id"]] = chosen[0]
            placed.append(chosen[1])
    return out


def _cell(root: ET.Element, cid: str, value: str, style: str, parent: str, geo: tuple | None,
          vertex: bool = True, extra: dict | None = None) -> ET.Element:
    attrs = {"id": cid, "value": value, "style": style}
    attrs["vertex" if vertex else "edge"] = "1"
    attrs["parent"] = parent
    attrs.update(extra or {})
    c = ET.SubElement(root, "mxCell", attrs)
    if geo is not None:
        x, y, w, h = geo
        ET.SubElement(c, "mxGeometry", {"x": _num(x), "y": _num(y), "width": _num(w), "height": _num(h), "as": "geometry"})
    return c


def _num(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else f"{v:.2f}".rstrip("0").rstrip(".")


def build(ir: dict) -> str:
    problems = ir_problems(ir)
    if problems:
        raise IRError(problems)
    P = load_preset()
    font = P["font"]
    FR = P["frame"]
    sizes = {n["id"]: node_size(n, font["fontSize"]) for n in ir["nodes"]}
    lay = Layout(ir, sizes, layout_dot(ir, sizes))
    routes = route_edges(ir, lay)
    label_at = place_labels(ir, lay, routes)

    mxfile = ET.Element("mxfile", {"host": "homelab-drawio"})
    diag = ET.SubElement(mxfile, "diagram", {"id": ir["diagram"]["id"], "name": ir["diagram"]["title"]})
    model = ET.SubElement(diag, "mxGraphModel", {
        "dx": "1600", "dy": "1000", "grid": "1", "gridSize": str(GRID), "guides": "1", "tooltips": "1",
        "connect": "1", "arrows": "1", "fold": "1", "page": "0", "pageScale": "1", "math": "0", "shadow": "0"})
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", {"id": "0"})
    ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})

    right = max([b[0] + b[2] for b in lay.box.values()] + [f[0] + f[2] for f in lay.frame.values()])
    bottom = max([b[1] + b[3] for b in lay.box.values()] + [f[1] + f[3] for f in lay.frame.values()])
    text = f"text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;fontFamily={font['fontFamily']};"
    title_w = max(right - MARGIN_X, _ceil(text_width(ir["diagram"]["title"], 18, bold=True) + 20))
    _cell(root, "title", html.escape(ir["diagram"]["title"], quote=False),
          text + "fontSize=18;fontColor=#1E293B;fontStyle=1;", "1", (MARGIN_X, 24, title_w, 28))
    _cell(root, "scope", html.escape(ir["diagram"]["scope"], quote=False),
          text + "fontSize=12;fontColor=#475569;", "1", (MARGIN_X, 54, title_w, 36))

    bounds = {b["id"]: b for b in ir.get("boundaries", [])}
    frame_style = (P["shapes"]["container"] + f"fillColor={FR['fillColor']};strokeColor={FR['strokeColor']};"
                   f"strokeWidth={FR['strokeWidth']};fontColor={FR['fontColor']};fontFamily={font['fontFamily']};"
                   f"fontSize={FR['fontSize']};fontStyle={FR['fontStyle']};align=left;spacingLeft=10;spacingTop=2;")

    def origin(parent: str | None) -> tuple[int, int]:
        return (lay.frame[parent][0], lay.frame[parent][1]) if parent else (0, 0)

    def emit_frames(parent: str | None) -> None:
        for b in ir.get("boundaries", []):
            if b.get("parent") == parent and b["id"] in lay.frame:
                x, y, w, h = lay.frame[b["id"]]
                ox, oy = origin(parent)
                _cell(root, b["id"], html.escape(b["label"], quote=False), frame_style,
                      parent or "1", (x - ox, y - oy, w, h))
                emit_frames(b["id"])

    emit_frames(None)
    for n in ir["nodes"]:
        x, y, w, h = lay.box[n["id"]]
        ox, oy = origin(n.get("parent"))
        _cell(root, n["id"], label_html(n["label"]), node_style(n, P), n.get("parent") or "1", (x - ox, y - oy, w, h))

    for e in ir["edges"]:
        r = routes[e["id"]]
        st = edge_style(e, P, ir)
        if r["ports"]:
            ex, ey, nx, ny = r["ports"]
            st += (f"exitX={_num(round(ex, 4))};exitY={_num(round(ey, 4))};exitDx=0;exitDy=0;"
                   f"entryX={_num(round(nx, 4))};entryY={_num(round(ny, 4))};entryDx=0;entryDy=0;")
        label = _edge_label(e)
        c = _cell(root, e["id"], html.escape(label, quote=False), st, "1", None, vertex=False,
                  extra={"source": e["source"], "target": e["target"]})
        g = ET.SubElement(c, "mxGeometry", {"relative": "1", "as": "geometry"})
        pos = e.get("label_pos", label_at.get(e["id"]))
        if pos is not None:
            g.set("x", _num(round(pos, 3)))
        if r["points"]:
            arr = ET.SubElement(g, "Array", {"as": "points"})
            for px, py in r["points"]:
                ET.SubElement(arr, "mxPoint", {"x": _num(px), "y": _num(py)})

    width = max(right - MARGIN_X, 640)
    y = bottom + 30
    for note in ir.get("notes", []):
        y = _note(root, note, font, MARGIN_X, y, width) + 12
    _legend(root, ir, P, MARGIN_X, y + 18, width, frame_style)
    ET.indent(mxfile, "  ")
    return ET.tostring(mxfile, encoding="unicode") + "\n"


def _note(root: ET.Element, note: dict, font: dict, x: int, y: int, width: int) -> int:
    """A reading note under the diagram; returns its bottom edge."""
    size = font["fontSize"]
    words, lines, cur = note["text"].split(), 0, ""
    for w in words:  # wrap the way Draw.io will, to size the cell honestly
        trial = f"{cur} {w}".strip()
        if text_width(trial, size) > width - 16 and cur:
            lines, cur = lines + 1, w
        else:
            cur = trial
    lines += 1 if cur else 0
    value = html.escape(note["text"], quote=False)
    if note.get("title"):
        value = f"<b>{html.escape(note['title'], quote=False)}</b><br>{value}"
        lines += 1
    h = _ceil(lines * size * LINE_H + 8)
    _cell(root, note["id"], value, f"text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;"
          f"fontFamily={font['fontFamily']};fontSize={size};fontColor=#475569;", "1", (x, y, width, h))
    return y + h


def _legend(root: ET.Element, ir: dict, P: dict, x: int, y: int, width: int, frame_style: str) -> None:
    font = P["font"]
    items: list[tuple[str, str, str]] = []   # (kind, key, text)
    roles = []
    for n in ir["nodes"]:
        r = "planned" if n.get("status") == "planned" else n["role"]
        if r not in roles:
            roles.append(r)
    legend = ir["diagram"].get("legend", {})
    for r in roles:
        items.append(("role", r, legend.get("roles", {}).get(r, LEGEND_ROLE[r])))
    types = []
    for e in ir["edges"]:
        k = ("planned" if e.get("status") == "planned" else e["type"], e.get("signal"))
        if k not in types:
            types.append(k)
    for t, sig in types:
        text = "planned path (dashed)" if t == "planned" else (
            legend.get("edges", {}).get(f"telemetry:{sig}", f"telemetry: {SIGNAL_LABEL[sig]}") if sig
            else legend.get("edges", {}).get(t, LEGEND_EDGE[t]))
        items.append(("edge", f"{t}{'-' + sig if sig else ''}", text))
    if any(e.get("status") == "optional" for e in ir["edges"]):
        items.append(("edge", "optional", "dashed = optional / indirect (labelled)"))

    text_st = (f"text;html=1;whiteSpace=nowrap;align=left;verticalAlign=middle;fontFamily={font['fontFamily']};"
               f"fontSize={font['fontSize']};fontColor=#334155;")
    cx, cy, row_h, inner = 14, FRAME_TITLE_H + 10, 22, width - 28
    cells = []
    for kind, key, label in items:
        tw = _ceil(text_width(label, font["fontSize"]) + 10)
        item_w = 34 + tw + 18
        if cx + item_w > inner and cx > 14:
            cx, cy = 14, cy + row_h
        cells.append((kind, key, label, cx, cy, tw))
        cx += item_w
    h = cy + row_h + 10
    _cell(root, "legend", "Legend", frame_style, "1", (x, y, width, h))
    for kind, key, label, ix, iy, tw in cells:
        if kind == "role":
            rs = role_style(key)
            st = (P["shapes"]["card"] + ("dashed=1;" if key == "planned" else "") +
                  f"fillColor={rs['fillColor']};strokeColor={rs['strokeColor']};strokeWidth=1.5;")
            _cell(root, f"legend-{kind}-{key}", "", st, "legend", (ix, iy + 4, 26, 14))
        else:
            if key == "optional":
                st = P["edges"]["dependency"] + "dashed=1;"
            elif key == "planned":
                st = P["edges"]["planned"]
            else:
                t, _, sig = key.partition("-")
                st = P["edges"][t]
                if sig:
                    st = _replace_attr(st, "strokeColor", role_style(sig)["strokeColor"])
                if t in ir["diagram"].get("animate", []):
                    st += "flowAnimation=1;"
            c = _cell(root, f"legend-{kind}-{key}", "", st, "legend", None, vertex=False)
            g = ET.SubElement(c, "mxGeometry", {"relative": "1", "as": "geometry"})
            ET.SubElement(g, "mxPoint", {"x": _num(ix), "y": _num(iy + 11), "as": "sourcePoint"})
            ET.SubElement(g, "mxPoint", {"x": _num(ix + 26), "y": _num(iy + 11), "as": "targetPoint"})
        _cell(root, f"legend-{kind}-{key}-text", html.escape(label, quote=False), text_st, "legend",
              (ix + 34, iy, tw, 22))


def main() -> int:
    p = argparse.ArgumentParser(description="Diagram IR -> top-down homelab .drawio")
    p.add_argument("ir")
    p.add_argument("-o", "--output", help="default: the IR path with .ir.yaml replaced by .drawio")
    p.add_argument("--check", action="store_true", help="exit 1 if the output file differs from the IR")
    a = p.parse_args()
    out = a.output or (a.ir[:-len(".ir.yaml")] if a.ir.endswith(".ir.yaml") else os.path.splitext(a.ir)[0]) + ".drawio"
    try:
        xml = build(load_ir(a.ir))
    except IRError as exc:
        for rule, objs, msg in exc.problems:
            print(f"ERROR [{rule}] {msg}", file=sys.stderr)
        return 1
    if a.check:
        try:
            with open(out, encoding="utf-8") as fh:
                same = fh.read() == xml
        except FileNotFoundError:
            same = False
        print(f"{out}: {'matches its IR' if same else 'STALE -- regenerate from ' + a.ir}")
        return 0 if same else 1
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(xml)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
