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
    LOGO_SUFFIX,
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
ICON_SIZE = 24         # px of the logo itself
CYLINDER_CAP = 8       # px of the cylinder's top ellipse (`size=8`)
LINE_H = 1.3           # line height, in em
LANE_MIN = 10          # px between two lanes in a channel
BORDER_GAP = 10        # px an edge run keeps from a frame border it runs beside
LANE_GAP = 14          # px between two parallel lanes; a channel grows to fit its lanes
ROUTE_PASSES = 4       # routing passes while channels are still growing
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
        if node_icon(n) and n["icon"] not in icons:
            out.append(("structural.unknown_icon", [n["id"]], f"node '{n['id']}' icon '{n['icon']}' is not in the catalogue"))
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


def frame_title_style(ir: dict, fid: str) -> dict:
    """Title size, colour and side of a frame: the outermost frame is the system
    boundary, every frame inside it is an inner frame (assets/homelab.json
    frame.titles)."""
    bounds = {b["id"]: b for b in ir.get("boundaries", [])}
    kind = "inner" if bounds.get(fid, {}).get("parent") else "boundary"
    t = dict(load_preset()["frame"]["titles"][kind])
    # A frame that holds frames keeps its title on the left, so it never stacks
    # in the corner its innermost child already uses.
    if kind == "inner" and any(b.get("parent") == fid for b in bounds.values()):
        t["align"] = "left"
    return t


def title_span(ir: dict, fid: str, rect: list[float]) -> tuple[float, float]:
    """x-span of a frame's title text, on the side the title is drawn."""
    label = next((b["label"] for b in ir.get("boundaries", []) if b["id"] == fid), "")
    t = frame_title_style(ir, fid)
    w = text_width(label, t["fontSize"], bold=True) + 30
    if t["align"] == "right":
        return (rect[0] + rect[2] - w, rect[0] + rect[2])
    return (rect[0], rect[0] + w)


def node_icon(n: dict) -> str | None:
    """The node's catalogue icon. `icon: none` marks a box that names a
    product without being it (validate.py's house.missing_logo skips it)."""
    icon = n.get("icon")
    return None if icon in (None, "none") else icon


def node_size(n: dict, font_size: int) -> tuple[int, int]:
    lines = n["label"].split("\n")
    multi = len(lines) > 1
    tw = max(text_width(l, font_size, bold=multi and i == 0) for i, l in enumerate(lines))
    pad = (ICON_PAD if node_icon(n) else PAD_TEXT) + PAD_TEXT
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
        return [title_span(self.ir, fid, f) for fid, f in self.frame.items() if above <= f[1] <= top]

    def frame_title(self, fid: str) -> list[tuple[float, float, float]]:
        f = self.frame[fid]
        return [(*title_span(self.ir, fid, f), f[1])]

    def ancestor_titles(self, nid: str) -> list[tuple[float, float, float]]:
        """(x0, x1, frame top) of the title text of every frame around `nid`."""
        bounds = {b["id"]: b for b in self.ir.get("boundaries", [])}
        parent = {n["id"]: n.get("parent") for n in self.ir["nodes"]}.get(nid)
        spans = []
        while parent:
            f = self.frame.get(parent)
            if f:
                spans.append((*title_span(self.ir, parent, f), f[1]))
            parent = bounds[parent].get("parent")
        return spans

    def frames_around(self, nid: str) -> list[str]:
        """The frames around `nid`, innermost first."""
        bounds = {b["id"]: b for b in self.ir.get("boundaries", [])}
        cur = {n["id"]: n.get("parent") for n in self.ir["nodes"]}.get(nid, bounds.get(nid, {}).get("parent"))
        out = []
        while cur:
            out.append(cur)
            cur = bounds[cur].get("parent")
        return out

    def scope(self, s: str, t: str) -> str | None:
        """The innermost frame around both ends: the edge must not leave it."""
        around_t = set(self.frames_around(t)) | {t}
        return next((f for f in self.frames_around(s) if f in around_t and f in self.frame), None)

    def insert_space(self, at: float, d: float) -> None:
        """Open `d` px of vertical space at y=`at`: everything below moves
        down, and every frame that spans or ends at `at` grows."""
        for r in [*self.box.values(), *self.frame.values()]:
            if r[1] >= at:
                r[1] += d
            elif r[1] + r[3] >= at:
                r[3] += d
        self.spline = {k: [(x, y + d if y >= at else y) for x, y in v] for k, v in self.spline.items()}
        self.rows = [None if r is None else (r[0] + d if r[0] >= at else r[0], r[1] + d if r[1] >= at else r[1])
                     for r in self.rows]

    def channel(self, upper: int, scope: str | None = None) -> tuple[float, float]:
        """Free vertical band between layer `upper` and `upper + 1`. A run
        stays inside its scope frame (and the frames around it) and outside
        every other frame, BORDER_GAP clear of each border."""
        lo, hi = self.rows[upper][1], self.rows[upper + 1][0]
        raw = (lo, hi)
        inside = set([scope, *self.frames_around(scope)]) if scope else set()
        for fid, (x, y, w, h) in self.frame.items():
            if fid in inside:
                if lo < y + h <= hi:
                    hi = min(hi, y + h)
                if lo <= y < hi:
                    lo = max(lo, y + FRAME_TITLE_H + 2)
                continue
            if lo < y + h <= hi:
                lo = max(lo, y + h)
            if lo <= y < hi:
                hi = min(hi, y)
        if hi - lo >= 2 * LANE_MIN:
            # Lanes sit strictly inside the band; the gap keeps the outermost
            # off the borders without starving a narrow band of lanes.
            g = min(BORDER_GAP, (hi - lo - 2 * LANE_MIN) / 2)
            return (lo + g, hi - g)
        if hi > lo:
            return (lo, hi)  # a real but narrow gutter: route_edges widens it
        # Frames touch, so there is no gap between them. Run the lanes inside
        # the lower frame instead, but never in a frame's title band or on a
        # border.
        # Lanes sit strictly inside a free stretch, so a small gap is enough
        # here; a full BORDER_GAP would push them into the frames below.
        gap = BORDER_GAP / 2 - 1
        blocked = [(f[1] - gap, f[1] + FRAME_TITLE_H + 2) for f in self.frame.values()
                   if raw[0] <= f[1] < raw[1]]
        blocked += [(f[1] + f[3] - gap, f[1] + f[3] + gap) for f in self.frame.values()
                    if raw[0] <= f[1] + f[3] <= raw[1]]
        free, cur = [], raw[0]
        for y0, y1 in sorted(blocked):
            if y0 > cur:
                free.append((cur, y0))
            cur = max(cur, y1)
        if raw[1] > cur:
            free.append((cur, raw[1]))
        return max(free, key=lambda r: (r[1] - r[0], -r[0])) if free else raw

    def clear_of_sides(self, x: float, y0: float, y1: float) -> float:
        """`x`, moved right until a vertical run from y0 to y1 keeps
        BORDER_GAP from every frame's side border."""
        lo, hi = min(y0, y1), max(y0, y1)
        moved = True
        while moved:
            moved = False
            for fx, fy, fw, fh in self.frame.values():
                if fy < hi and fy + fh > lo:
                    for side in (fx, fx + fw):
                        if abs(x - side) < BORDER_GAP:
                            x, moved = side + BORDER_GAP, True
        return x

    def free_x(self, layer: int, x: float, exclude: set[str], scope: str | None = None) -> float:
        """Nearest x in `layer` whose vertical line hits no node, runs on no
        frame border, and stays inside the scope frame."""
        spans = [(b[0], b[0] + b[2]) for n, b in self.box.items()
                 if self.li[n] == layer and n not in exclude] + self._titles_opening(layer)
        # The run spans the channels on either side of the layer, so it must
        # clear the side borders of frames that open or close in them too.
        top, bottom = self.rows[layer]
        if layer > 0 and self.rows[layer - 1]:
            top = self.rows[layer - 1][1]
        if layer + 1 < len(self.rows) and self.rows[layer + 1]:
            bottom = self.rows[layer + 1][0]
        for fx, fy, fw, fh in self.frame.values():  # side borders beside this run
            if fy < bottom and fy + fh > top:
                spans += [(fx, fx), (fx + fw, fx + fw)]
        if scope:
            f = self.frame[scope]
            spans += [(-1e8, f[0]), (f[0] + f[2], 1e8)]
        spans.sort()
        if all(not (a - 10 < x < b + 10) for a, b in spans):
            return x
        gaps, prev = [], -1e9
        for a, b in spans:
            gaps.append((prev + 10, a - 10))
            prev = max(prev, b)
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


def _side_ports(lay: Layout, s: str, t: str) -> tuple | None:
    """Ports for a straight side-to-side run between two peers of one layer
    with nothing between their facing sides; None when there is no such run."""
    sb, tb = lay.box[s], lay.box[t]
    left, right = (sb, tb) if sb[0] < tb[0] else (tb, sb)
    y = (max(sb[1], tb[1]) + min(sb[1] + sb[3], tb[1] + tb[3])) / 2
    blocked = any(n not in (s, t) and lay.li[n] == lay.li[s] and left[0] + left[2] <= b[0] < right[0]
                  and b[1] < y < b[1] + b[3] for n, b in lay.box.items())
    if blocked or max(sb[1], tb[1]) >= min(sb[1] + sb[3], tb[1] + tb[3]):
        return None
    sx = 1 if sb[0] < tb[0] else 0
    return (sx, (y - sb[1]) / sb[3], 1 - sx, (y - tb[1]) / tb[3])


def route_edges(ir: dict, lay: Layout) -> dict[str, dict]:
    """Per edge: ports (exit/entry fractions) and absolute waypoints.

    Dot spaces the layers without knowing how many lanes a channel will
    carry, so route, widen every channel too narrow for its lanes
    (LANE_GAP apart, which grows the gutter between the frames around it),
    and route again until nothing grows."""
    for _ in range(ROUTE_PASSES):
        routes, bands = _route_pass(ir, lay)
        grow: dict[float, float] = {}
        for (lo, hi), n in bands.items():
            short = (n + 1) * LANE_GAP - (hi - lo)
            if short > 0:
                grow[hi] = max(grow.get(hi, 0), short)
        if not grow:
            return routes
        for at, d in sorted(grow.items(), reverse=True):
            lay.insert_space(at, _ceil(d))
    return _route_pass(ir, lay)[0]


def _route_pass(ir: dict, lay: Layout) -> tuple[dict[str, dict], dict[tuple[float, float], int]]:
    """One routing pass: the routes, and how many lanes each channel band holds."""
    routes: dict[str, dict] = {}
    plans = []
    scope_of: dict[str, str | None] = {}
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
        scope_of[e["id"]] = lay.scope(s, t)
        if ls == lt:
            # Facing sides with nothing between: a straight side-to-side run.
            ports = _side_ports(lay, s, t)
            if ports:
                routes[e["id"]] = {"points": [], "ports": ports}
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
            mids.append(lay.free_x(k, _snap(x), {s, t}, scope_of[e["id"]]))
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
        if (hi - lo) / (k + 1) < LANE_GAP:
            # Too narrow beside the titles for LANE_GAP between ports: spread
            # over the whole side; a top port under a title takes the detour
            # route_edges draws around it.
            lo, hi = b[0] + 10, b[0] + b[2] - 10
        for i, (_, eid, which) in enumerate(items):
            x = lo + _snap((hi - lo) * (i + 1) / (k + 1), 5)
            port_x[(eid, which)] = x

    # Horizontal runs per channel band (a channel clipped to each run's scope
    # frame), then one lane per overlapping run.
    runs: dict[tuple[float, float], list[list]] = {}
    for e, s_side, t_side, chans, mids in plans:
        xs = [port_x[(e["id"], "exit")], *mids, port_x[(e["id"], "entry")]]
        for j, c in enumerate(chans):
            a, b = xs[j], xs[j + 1]
            runs.setdefault(lay.channel(c, scope_of[e["id"]]), []).append([min(a, b), max(a, b), e["id"], j, None])
    lane_y: dict[tuple[str, int], float] = {}
    bands: dict[tuple[float, float], int] = {}
    for (lo, hi), items in sorted(runs.items()):
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
        n = len(lanes)
        bands[(lo, hi)] = n
        for r in items:
            lane_y[(r[2], r[3])] = round(lo + (hi - lo) * (r[4] + 1) / (n + 1))

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
            for (x0, x1, fy), fid in zip(lay.ancestor_titles(e["target"]),
                                         [f for f in lay.frames_around(e["target"]) if f in lay.frame]):
                if x0 - 10 < px < x1 + 10 and lane < fy:
                    y_in = fy + FRAME_TITLE_H + 6
                    # Come down on the side of the title that is inside the
                    # frame: a right-aligned title leaves no room on its right.
                    f = lay.frame[fid]
                    inner = [x for x in (x1 + 10, x0 - 10) if f[0] + BORDER_GAP <= x <= f[0] + f[2] - BORDER_GAP]
                    xd = lay.clear_of_sides(min(inner or [x1 + 10], key=lambda x: abs(x - px)), lane, y_in)
                    pts[-1:] = [(xd, lane), (xd, y_in), (px, y_in)]
                    break
        sb, tb = lay.box[e["source"]], lay.box[e["target"]]
        ports = ((xs[0] - sb[0]) / sb[2], 1 if s_side == "bottom" else 0,
                 (xs[-1] - tb[0]) / tb[2], 1 if t_side == "bottom" else 0)
        routes[eid] = {"points": pts, "ports": ports}
    _space_frame_runs(ir, lay, routes, bands)
    return routes, bands


def _space_frame_runs(ir: dict, lay: Layout, routes: dict[str, dict],
                      bands: dict[tuple[float, float], int]) -> None:
    """An edge into a frame crosses the gutter above it on a run of its own;
    keep that run LANE_GAP clear of the lanes already in the gutter, or
    report the gutter as a band to widen."""
    taken = [(p[1], min(p[0], q[0]), max(p[0], q[0]))
             for r in routes.values() for p, q in zip(r["points"], r["points"][1:])
             if abs(p[1] - q[1]) < 0.5]
    for e in ir["edges"]:
        r = routes.get(e["id"])
        if e["target"] not in lay.frame or not r or len(r["points"]) != 2:
            continue
        (sx, y), (tx, _) = r["points"]
        x0, x1 = min(sx, tx), max(sx, tx)
        sb, fr = lay.box[e["source"]], lay.frame[e["target"]]
        lo, hi = sb[1] + sb[3], fr[1]
        near = [ty for ty, a, b in taken if a < x1 + LANE_MIN and b > x0 - LANE_MIN and lo < ty < hi]
        free = [c for c in range(int(lo) + LANE_GAP // 2, int(hi) - LANE_GAP // 2 + 1)
                if all(abs(c - ty) >= LANE_GAP for ty in near)]
        if free:
            y = min(free, key=lambda c: (abs(c - (lo + hi) / 2), c))
        else:
            bands[(lo, hi)] = len(near) + 1
        r["points"] = [(sx, y), (tx, y)]
        taken.append((y, x0, x1))


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
        # A logo is a child cell (logo_cell); the text moves right to clear it.
        logo = "align=left;spacingLeft=42;" if node_icon(n) else ""
        return (P["shapes"]["datastore"] + ("dashed=1;" if dashed else "") + logo +
                f"size={CYLINDER_CAP};fillColor={rs['fillColor']};strokeColor={rs['strokeColor']};strokeWidth=1.5;"
                f"fontColor={rs['fontColor']};fontFamily={font['fontFamily']};fontSize={font['fontSize']};")
    if node_icon(n):
        return _style(P["label_style"], n["role"], dashed, n["icon"], font)
    return _style(P["plain_style"].replace("rounded=1;", "rounded=1;{dashed}", 1), n["role"], dashed, None, font)


def logo_cell(n: dict, h: float) -> tuple[str, tuple[float, float, float, float]]:
    """(style, geometry) of a datastore's logo, drawn as an image cell inside
    the cylinder: draw.io paints no `image=` on `cylinder3`. Centred on the
    body, i.e. below the top cap."""
    path, _ = resolve_icon(n["icon"])
    with open(path, "rb") as fh:
        payload = base64.b64encode(fh.read()).decode()
    y = (h - ICON_SIZE + CYLINDER_CAP) / 2
    return f"shape=image;html=1;imageAspect=1;image=data:image/png,{payload};", (10, _snap(y, 1), ICON_SIZE, ICON_SIZE)


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


def _straddles(box: list[float], f: list[float]) -> bool:
    """True when a label box is cut by a frame border (half in, half out)."""
    return _hits(box, f) and not (f[0] <= box[0] and box[0] + box[2] <= f[0] + f[2]
                                  and f[1] <= box[1] and box[1] + box[3] <= f[1] + f[3])


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
    boxes = list(lay.box.values())
    for fid, f in lay.frame.items():
        x0, x1 = title_span(ir, fid, f)
        x0 = max(x0, f[0])
        boxes.append([x0, f[1], min(f[0] + f[2], x1) - x0, FRAME_TITLE_H])
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
        lines = label.split("\n")
        w = max(text_width(line, EDGE_FONT) for line in lines) + 6
        h = len(lines) * EDGE_FONT * LINE_H + 3
        cands = []
        for k, (p, q) in enumerate(zip(poly, poly[1:])):
            vertical = abs(p[0] - q[0]) < 1
            if segs[k] < (h + 8 if vertical else w + 8):
                continue
            for f in (0.5, 0.3, 0.7):
                cands.append((0 if vertical else 1, -segs[k], k, f))
        cands.sort()
        # Best candidate: clear of boxes and labels, then also clear of frame
        # borders; ties keep the candidate order.
        chosen, best = None, None
        for i, (_, _, k, f) in enumerate(cands):
            p, q = poly[k], poly[k + 1]
            cx, cy = p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f
            box = [cx - w / 2, cy - h / 2, w, h]
            pos = 2 * (sum(segs[:k]) + segs[k] * f) / total - 1
            score = (any(_hits(box, b) for b in boxes) or any(_hits(box, b) for b in placed),
                     any(_straddles(box, fr) for fr in lay.frame.values()), i)
            if best is None or score < best:
                chosen, best = (pos, box), score
            if not any(score[:2]):
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

    def titled(fid: str) -> str:
        t = frame_title_style(ir, fid)
        side = "align=right;spacingRight=10;" if t["align"] == "right" else "align=left;spacingLeft=10;"
        return (P["shapes"]["container"] + f"fillColor={FR['fillColor']};strokeColor={FR['strokeColor']};"
                f"strokeWidth={FR['strokeWidth']};fontColor={t['fontColor']};fontFamily={font['fontFamily']};"
                f"fontSize={t['fontSize']};fontStyle={FR['fontStyle']};{side}spacingTop=2;")

    def emit_frames(parent: str | None) -> None:
        for b in ir.get("boundaries", []):
            if b.get("parent") == parent and b["id"] in lay.frame:
                x, y, w, h = lay.frame[b["id"]]
                ox, oy = origin(parent)
                _cell(root, b["id"], html.escape(b["label"], quote=False), titled(b["id"]),
                      parent or "1", (x - ox, y - oy, w, h))
                emit_frames(b["id"])

    emit_frames(None)
    for n in ir["nodes"]:
        x, y, w, h = lay.box[n["id"]]
        ox, oy = origin(n.get("parent"))
        _cell(root, n["id"], label_html(n["label"]), node_style(n, P), n.get("parent") or "1", (x - ox, y - oy, w, h))
        if n.get("shape") == "datastore" and node_icon(n):
            style, geo = logo_cell(n, h)
            _cell(root, n["id"] + LOGO_SUFFIX, "", style, n["id"], geo)

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
