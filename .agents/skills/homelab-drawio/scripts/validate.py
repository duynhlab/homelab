#!/usr/bin/env python3
"""validate.py -- the quality gates for a homelab .drawio (references/quality-gates.md).

Gates, in order; every finding is machine-readable
({severity, rule_id, objects, message, fix}):

  0 house         validate_house.py's rules (palette, planned, embeds, legend, title)
  1 structural    parse, duplicate ids, broken parent/source/target, parent
                  cycles; with --ir also the IR schema, whether the file is
                  still exactly what its IR generates, and (WARN) a platform
                  node standing outside the cluster frame
  2 connectivity  dangling edges, orphan nodes, duplicate edges, an unlabelled
                  pair of opposite edges
  3 geometry      overlapping boxes, a child outside its frame, a box straddling
                  a frame it does not belong to, off-canvas and zero-size cells,
                  an edge through an unrelated box, edge crossings, tight gaps,
                  misaligned peers (--ir), over-long edges
  4 typography    text wider/taller than its box, fonts under 10px, long
                  labels, duplicate labels, an edge label sitting on a box
  5 architecture  only the rules the IR declares under `tests` (--ir)

ERROR fails the run (exit 1); WARN fails it only with --strict. An edge whose
path is not in the file (no waypoints, no ports, endpoints not aligned) is left
to Draw.io's router and reported once as INFO -- the geometry gate cannot see a
route Draw.io has not drawn yet.

Usage: validate.py <file.drawio> [--ir <file.ir.yaml>] [--json] [--strict]
"""
from __future__ import annotations

import argparse
import html
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

import validate_house
from _common import text_width

SEV_ORDER = {"ERROR": 0, "WARN": 1, "INFO": 2}
DATA_ROLES = {"data", "metric", "log", "trace", "profile"}


def finding(sev: str, rule: str, objects: list[str], message: str, fix: str) -> dict:
    return {"severity": sev, "rule_id": rule, "objects": objects, "message": message, "fix": fix}


def _attr(style: str, key: str) -> str | None:
    m = re.search(rf"(?:^|;){re.escape(key)}=([^;]*)", style or "")
    return m.group(1) if m else None


def _num(style: str, key: str, default: float) -> float:
    v = _attr(style, key)
    try:
        return float(v) if v is not None else default
    except ValueError:
        return default


def _plain(value: str) -> list[str]:
    text = re.sub(r"<br\s*/?>", "\n", value or "", flags=re.I)
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    return [l.strip() for l in text.split("\n") if l.strip()]


class Diagram:
    def __init__(self, path: str):
        with open(path, encoding="utf-8") as fh:
            self.text = fh.read()
        root = ET.fromstring(self.text)
        self.cells = list(root.iter("mxCell"))
        self.by_id: dict[str, ET.Element] = {}
        self.dupes: list[str] = []
        for c in self.cells:
            cid = c.get("id")
            if cid in self.by_id:
                self.dupes.append(cid)
            self.by_id[cid] = c
        self.parents = {c.get("parent") for c in self.cells if c.get("parent")}

    def is_edge(self, c) -> bool:
        return c.get("edge") == "1"

    def is_vertex(self, c) -> bool:
        return c.get("vertex") == "1"

    def is_frame(self, c) -> bool:
        return self.is_vertex(c) and (c.get("id") in self.parents or "container=1" in (c.get("style") or ""))

    def is_text(self, c) -> bool:
        return (c.get("style") or "").startswith("text;")

    def is_edge_label(self, c) -> bool:
        p = self.by_id.get(c.get("parent") or "")
        return p is not None and self.is_edge(p)

    def ancestors(self, cid: str) -> list[str]:
        out, cur, seen = [], self.by_id.get(cid), set()
        while cur is not None:
            pid = cur.get("parent")
            if not pid or pid in seen or pid not in self.by_id:
                break
            seen.add(pid)
            out.append(pid)
            cur = self.by_id[pid]
        return out

    def in_legend(self, cid: str) -> bool:
        for a in [cid, *self.ancestors(cid)]:
            c = self.by_id.get(a)
            if c is not None and "legend" in (c.get("value") or "").lower() and self.is_frame(c):
                return True
        return False

    def geo(self, c):
        g = c.find("mxGeometry")
        if g is None:
            return None
        return [float(g.get(k, 0)) for k in ("x", "y", "width", "height")]

    def abs_rect(self, cid: str):
        c = self.by_id[cid]
        r = self.geo(c)
        if r is None:
            return None
        x, y, w, h = r
        for a in self.ancestors(cid):
            pc = self.by_id[a]
            if self.is_vertex(pc):
                pr = self.geo(pc)
                if pr:
                    x, y = x + pr[0], y + pr[1]
        return [x, y, w, h]

    def route(self, e) -> list[tuple[float, float]] | None:
        s, t = e.get("source"), e.get("target")
        if s not in self.by_id or t not in self.by_id:
            return None
        sr, tr = self.abs_rect(s), self.abs_rect(t)
        if not sr or not tr:
            return None
        st = e.get("style") or ""
        g = e.find("mxGeometry")
        pts = []
        if g is not None:
            arr = g.find("Array")
            if arr is not None:
                pts = [(float(p.get("x", 0)), float(p.get("y", 0))) for p in arr.findall("mxPoint")]
        ex, ey = _attr(st, "exitX"), _attr(st, "exitY")
        nx, ny = _attr(st, "entryX"), _attr(st, "entryY")
        if ex is not None and nx is not None:
            p0 = (sr[0] + sr[2] * float(ex), sr[1] + sr[3] * float(ey))
            p1 = (tr[0] + tr[2] * float(nx), tr[1] + tr[3] * float(ny))
            return [p0, *pts, p1]
        sc = (sr[0] + sr[2] / 2, sr[1] + sr[3] / 2)
        tc = (tr[0] + tr[2] / 2, tr[1] + tr[3] / 2)
        if pts:
            return [sc, *pts, tc]
        if abs(sc[0] - tc[0]) < 1 or abs(sc[1] - tc[1]) < 1:
            return [sc, tc]
        return None


# --------------------------------------------------------------------- geometry

def _overlap(a, b, eps=0.5) -> bool:
    return a[0] + eps < b[0] + b[2] and b[0] + eps < a[0] + a[2] and a[1] + eps < b[1] + b[3] and b[1] + eps < a[1] + a[3]


def _seg_hits_rect(p, q, r, shrink=2.0) -> bool:
    x0, y0, x1, y1 = r[0] + shrink, r[1] + shrink, r[0] + r[2] - shrink, r[1] + r[3] - shrink
    if x1 <= x0 or y1 <= y0:
        return False
    # Liang-Barsky clip: does the segment enter the shrunken rectangle?
    dx, dy = q[0] - p[0], q[1] - p[1]
    t0, t1 = 0.0, 1.0
    for pk, qk in ((-dx, p[0] - x0), (dx, x1 - p[0]), (-dy, p[1] - y0), (dy, y1 - p[1])):
        if pk == 0:
            if qk < 0:
                return False
        else:
            t = qk / pk
            if pk < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                return False
    return True


def _segs_cross(p1, p2, p3, p4) -> bool:
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = orient(p3, p4, p1), orient(p3, p4, p2)
    d3, d4 = orient(p1, p2, p3), orient(p1, p2, p4)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def _length(poly) -> float:
    return sum(math.dist(a, b) for a, b in zip(poly, poly[1:]))


def _point_at(poly, frac: float):
    total = _length(poly)
    target, run = total * frac, 0.0
    for a, b in zip(poly, poly[1:]):
        seg = math.dist(a, b)
        if run + seg >= target and seg > 0:
            t = (target - run) / seg
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        run += seg
    return poly[-1]


# ------------------------------------------------------------------------ gates

def gate_structural(d: Diagram, ir: dict | None, ir_path: str | None) -> list[dict]:
    out = []
    for cid in d.dupes:
        out.append(finding("ERROR", "structural.duplicate_id", [cid], f"id '{cid}' is used twice", "give every cell a unique id"))
    for c in d.cells:
        pid = c.get("parent")
        if pid and pid not in d.by_id:
            out.append(finding("ERROR", "structural.broken_parent", [c.get("id")], f"parent '{pid}' does not exist", "fix or drop the parent"))
        if d.is_edge(c):
            for end in ("source", "target"):
                ref = c.get(end)
                if ref and ref not in d.by_id:
                    out.append(finding("ERROR", "structural.broken_endpoint", [c.get("id")],
                                       f"{end} '{ref}' does not exist", "point the edge at an existing cell"))
    for c in d.cells:
        seen, cur = [c.get("id")], d.by_id.get(c.get("parent") or "")
        while cur is not None:
            if cur.get("id") in seen:
                out.append(finding("ERROR", "structural.parent_cycle", seen, "parent chain loops", "break the cycle"))
                return out
            seen.append(cur.get("id"))
            cur = d.by_id.get(cur.get("parent") or "")
    if ir is not None:
        import generate
        probs = generate.ir_problems(ir)
        for rule, objs, msg in probs:
            out.append(finding("ERROR", rule, objs, msg, f"fix {ir_path}"))
        if not probs and ir.get("boundaries"):
            # The outermost frame is the system boundary (house-style.md): only
            # off-platform parties stand outside it.
            for n in ir["nodes"]:
                if not n.get("parent") and n["role"] != "external":
                    out.append(finding("WARN", "layout.unframed_node", [n["id"]],
                                       f"'{n['id']}' sits outside every frame but is not external",
                                       "put it inside the cluster frame (parent: f_cluster)"))
        if not probs:
            if generate.build(ir) != d.text:
                out.append(finding("ERROR", "structural.stale_projection", [ir_path or "ir"],
                                   "the .drawio is not what its IR generates (hand-edited, or the IR changed)",
                                   f"regenerate: generate.py {ir_path}; carry any hand edit into the IR"))
    return out


def gate_connectivity(d: Diagram) -> list[dict]:
    out = []
    edges = [c for c in d.cells if d.is_edge(c) and not d.in_legend(c.get("id"))]
    touched = set()
    seen: dict[tuple, str] = {}
    for e in edges:
        s, t, eid = e.get("source"), e.get("target"), e.get("id")
        if not s or not t:
            out.append(finding("ERROR", "connectivity.dangling_edge", [eid], "edge has no source or target",
                               "connect both ends (a free-floating arrow belongs in the legend)"))
            continue
        touched |= {s, t}
        if t in d.by_id and d.is_frame(d.by_id[t]):
            # An edge into a frame reaches every box in it.
            touched |= {c.get("id") for c in d.cells if t in d.ancestors(c.get("id"))}
        key = (s, t, (e.get("value") or "").strip())
        if key in seen:
            out.append(finding("WARN", "connectivity.duplicate_edge", [seen[key], eid], "same source, target and label twice",
                               "merge them"))
        seen[key] = eid
    pairs = {(e.get("source"), e.get("target")): e for e in edges}
    for (s, t), e in pairs.items():
        back = pairs.get((t, s))
        if back is not None and s < t and not (e.get("value") or "").strip() and not (back.get("value") or "").strip():
            out.append(finding("WARN", "connectivity.ambiguous_bidirectional", [e.get("id"), back.get("id")],
                               "opposite edges with no labels read as one two-way arrow", "label what flows each way"))
    for c in d.cells:
        cid = c.get("id")
        if (d.is_vertex(c) and not d.is_frame(c) and not d.is_text(c) and not d.in_legend(cid)
                and not d.is_edge_label(c) and (c.get("value") or "").strip() and cid not in touched):
            out.append(finding("WARN", "connectivity.orphan_node", [cid], f"'{_plain(c.get('value'))[0]}' has no edges",
                               "connect it, or drop it if it answers nothing (diagram-types.md: nothing is decoration)"))
    return out


def gate_geometry(d: Diagram, ir: dict | None) -> tuple[list[dict], list]:
    out = []
    verts = [c for c in d.cells if d.is_vertex(c) and not d.is_edge_label(c) and c.get("id") not in ("0", "1")]
    rects = {c.get("id"): d.abs_rect(c.get("id")) for c in verts}
    frames = [c.get("id") for c in verts if d.is_frame(c)]
    leaves = [c.get("id") for c in verts if not d.is_frame(c) and (c.get("value") or c.get("style"))]
    for cid, r in rects.items():
        if r is None:
            continue
        if r[2] <= 0 or r[3] <= 0:
            out.append(finding("ERROR", "geometry.bad_dimensions", [cid], f"size {r[2]:g}x{r[3]:g}", "give it a positive size"))
        if r[0] < 0 or r[1] < 0:
            out.append(finding("ERROR", "geometry.off_canvas", [cid], f"at ({r[0]:g},{r[1]:g})", "move it onto the canvas"))
    for c in verts:  # child overflow, relative to its frame
        p = d.by_id.get(c.get("parent") or "")
        if p is None or not d.is_vertex(p):
            continue
        g, pg = d.geo(c), d.geo(p)
        if g and pg and (g[0] < 0 or g[1] < 0 or g[0] + g[2] > pg[2] + 0.5 or g[1] + g[3] > pg[3] + 0.5):
            out.append(finding("ERROR", "geometry.child_overflow", [c.get("id"), p.get("id")],
                               "box spills outside its frame", "grow the frame or move the box inside"))
    for i, a in enumerate(leaves):
        for b in leaves[i + 1:]:
            ra, rb = rects[a], rects[b]
            if ra and rb and _overlap(ra, rb):
                out.append(finding("ERROR", "geometry.overlap", [a, b], "boxes overlap", "move one of them"))
            elif (ra and rb and d.by_id[a].get("parent") == d.by_id[b].get("parent") and not d.in_legend(a)
                  and not (d.is_text(d.by_id[a]) or d.is_text(d.by_id[b]))):
                gx = max(rb[0] - (ra[0] + ra[2]), ra[0] - (rb[0] + rb[2]))
                gy = max(rb[1] - (ra[1] + ra[3]), ra[1] - (rb[1] + rb[3]))
                if (0 <= gx < 10 and gy < 0) or (0 <= gy < 10 and gx < 0):
                    out.append(finding("WARN", "geometry.tight_gap", [a, b], "boxes closer than 10px", "space them on the grid"))
    for f in frames:
        for cid in leaves + frames:
            if cid == f or f in d.ancestors(cid) or cid in d.ancestors(f) or d.in_legend(cid) != d.in_legend(f):
                continue
            if rects[cid] and rects[f] and _overlap(rects[cid], rects[f]):
                out.append(finding("ERROR", "geometry.frame_intrusion", [cid, f],
                                   "a box sits on a frame it does not belong to", "move it out, or parent it to that frame"))

    edges = [c for c in d.cells if d.is_edge(c) and not d.in_legend(c.get("id"))]
    routes, unrouted = {}, []
    for e in edges:
        r = d.route(e)
        if r is None:
            unrouted.append(e.get("id"))
        else:
            routes[e.get("id")] = r
    if unrouted:
        out.append(finding("INFO", "geometry.route_unknown", unrouted,
                           f"{len(unrouted)} edge(s) left to Draw.io's router; their path is not checked",
                           "regenerate from the IR, or add waypoints"))
    canvas = max((r[0] + r[2] for r in rects.values() if r), default=0), max((r[1] + r[3] for r in rects.values() if r), default=0)
    for eid, poly in routes.items():
        e = d.by_id[eid]
        skip = {e.get("source"), e.get("target"), *d.ancestors(e.get("source")), *d.ancestors(e.get("target"))}
        for cid in leaves:
            if cid in skip or d.in_legend(cid) or not rects[cid]:
                continue
            if any(_seg_hits_rect(p, q, rects[cid]) for p, q in zip(poly, poly[1:])):
                out.append(finding("ERROR", "geometry.edge_through_shape", [eid, cid],
                                   f"edge passes through '{(_plain(d.by_id[cid].get('value')) or [cid])[0]}'",
                                   "route it through a free channel (IR `via`) or move the box"))
        if _length(poly) > max(canvas):
            out.append(finding("WARN", "geometry.long_edge", [eid], f"edge is {_length(poly):.0f}px long",
                               "move the two ends closer, or split the view"))
    ids = sorted(routes)
    crossings = []
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            pa, pb = routes[a], routes[b]
            if any(_segs_cross(p1, p2, p3, p4) for p1, p2 in zip(pa, pa[1:]) for p3, p4 in zip(pb, pb[1:])):
                crossings.append([a, b])
    moving = [eid for eid in (e.get("id") for e in edges) if "flowAnimation=1" in (d.by_id[eid].get("style") or "")]
    kinds = {_attr(e.get("style") or "", "strokeColor") for e in edges}
    still = {_attr(e.get("style") or "", "strokeColor") for e in edges
             if "flowAnimation=1" not in (e.get("style") or "")}
    # Animation marks the primary flow, so something must stay still for it to
    # stand out. A graph with one kind of edge (a delivery graph) is all
    # primary flow and may move entirely.
    if moving and len(kinds) > 1 and not still:
        out.append(finding("WARN", "house.animation_overuse", moving,
                           "every kind of edge animates, so nothing marks the primary flow",
                           "narrow diagram.animate to the flow the diagram is about (house-style.md § Flow animation)"))
    for pair in crossings:
        out.append(finding("WARN", "geometry.edge_crossing", pair, "edges cross", "reorder peers in the IR, or accept and keep the count low"))
    if ir is not None:
        by_layer: dict[str, list[str]] = {}
        for n in ir.get("nodes", []):
            by_layer.setdefault(n["layer"], []).append(n["id"])
        for layer, members in by_layer.items():
            cys = {m: rects[m][1] + rects[m][3] / 2 for m in members if rects.get(m)}
            if cys and max(cys.values()) - min(cys.values()) > 5:
                out.append(finding("WARN", "geometry.peer_misaligned", sorted(cys),
                                   f"layer '{layer}' peers are not on one row", "keep a layer's nodes the same height, or regenerate"))
    return out, routes


def gate_typography(d: Diagram, routes: dict) -> list[dict]:
    out = []
    labels: dict[str, list[str]] = {}
    for c in d.cells:
        cid, st, val = c.get("id"), c.get("style") or "", c.get("value") or ""
        lines = _plain(val)
        if not lines or d.is_edge(c) or d.is_edge_label(c):
            continue
        size = _num(st, "fontSize", 11)
        if size < 10:
            out.append(finding("WARN", "typography.small_font", [cid], f"font {size:g}px", "use 10px or more"))
        for l in lines if not d.is_text(c) else []:  # prose (title, scope, notes) may run long
            if len(l) > 48:
                out.append(finding("WARN", "typography.long_label", [cid], f"line of {len(l)} chars", "shorten it or break the line"))
                break
        r = d.geo(c)
        if r and not d.is_frame(c):
            pad = _num(st, "spacingLeft", 0) + _num(st, "spacingRight", 0) + (8 if not d.is_text(c) else 0)
            bold_first = "<b>" in val.split("<br>")[0].lower()
            widths = [text_width(l, size, bold=bold_first and i == 0) for i, l in enumerate(lines)]
            avail = r[2] - pad
            if "whiteSpace=wrap" in st:
                # Draw.io wraps: overflow shows up as extra lines, i.e. height.
                n_lines = sum(max(1, math.ceil(w / avail)) if avail > 0 else 99 for w in widths)
                if n_lines * size * 1.2 > r[3] + 2:
                    out.append(finding("WARN", "typography.text_overflow", [cid],
                                       f"text wraps to {n_lines} lines, box fits {int(r[3] // (size * 1.2))}",
                                       "widen or heighten the box, or shorten the label"))
            elif max(widths) + pad > r[2] + 4:
                out.append(finding("WARN", "typography.text_overflow", [cid],
                                   f"text needs ~{max(widths) + pad:.0f}px, box is {r[2]:g}px",
                                   "widen the box or shorten the label"))
        if d.is_vertex(c) and not d.is_frame(c) and not d.is_text(c) and not d.in_legend(cid):
            labels.setdefault(lines[0].lower(), []).append(cid)
    for name, ids in labels.items():
        if len(ids) > 1:
            out.append(finding("WARN", "typography.duplicate_label", ids, f"'{name}' appears {len(ids)} times",
                               "name each box specifically (diagram-types.md check 4)"))
    leaves = [c for c in d.cells if d.is_vertex(c) and not d.is_frame(c) and not d.in_legend(c.get("id"))
              and (c.get("value") or "").strip() and not d.is_edge_label(c)]
    label_boxes: list[tuple[str, str, list[float]]] = []
    frames = [c for c in d.cells if d.is_frame(c) and (c.get("value") or "").strip()]
    for f in frames:  # an edge drawn through a frame's name hides it
        fr = d.abs_rect(f.get("id"))
        if not fr or d.in_legend(f.get("id")):
            continue
        band = [fr[0], fr[1], min(fr[2], text_width(_plain(f.get("value"))[0], 13, bold=True) + 30), 22]
        for eid, poly in routes.items():
            if any(_seg_hits_rect(p, q, band, shrink=0) for p, q in zip(poly, poly[1:])):
                out.append(finding("WARN", "typography.edge_over_frame_title", [eid, f.get("id")],
                                   f"edge runs through the title of frame '{_plain(f.get('value'))[0]}'",
                                   "regenerate (ports avoid titles), or move the edge with IR `via`"))
    for eid, poly in routes.items():
        e = d.by_id[eid]
        text = " ".join(_plain(e.get("value") or ""))
        if not text:
            continue
        g = e.find("mxGeometry")
        pos = float(g.get("x", 0)) if g is not None else 0.0
        cx, cy = _point_at(poly, (pos + 1) / 2)
        w = text_width(text, _num(e.get("style") or "", "fontSize", 10)) + 4
        box = [cx - w / 2, cy - 8, w, 16]
        for other, otext, obox in label_boxes:
            if _overlap(box, obox):
                out.append(finding("WARN", "typography.label_collision", [other, eid],
                                   f"labels '{otext}' and '{text}' overlap", "set label_pos on one of them in the IR"))
        label_boxes.append((eid, text, box))
        for f in frames:
            fr = d.abs_rect(f.get("id"))
            band = [fr[0], fr[1], min(fr[2], text_width(_plain(f.get("value"))[0], 13, bold=True) + 30), 24] if fr else None
            if band and not d.in_legend(f.get("id")) and _overlap(box, band):
                out.append(finding("WARN", "typography.label_over_shape", [eid, f.get("id")],
                                   f"label '{text}' covers the title of frame '{_plain(f.get('value'))[0]}'",
                                   "set the edge's label_pos in the IR"))
        for c in leaves:  # endpoints included: a label on its own box is just as unreadable
            r = d.abs_rect(c.get("id"))
            if r and _overlap(box, r):
                out.append(finding("WARN", "typography.label_over_shape", [eid, c.get("id")],
                                   f"label '{text}' sits on '{_plain(c.get('value'))[0]}'", "set the edge's label_pos in the IR"))
    return out


def gate_architecture(ir: dict) -> list[dict]:
    out = []
    nodes = {n["id"]: n for n in ir["nodes"]}
    edges = ir["edges"]
    for test in ir.get("tests", []):
        rule, scope = test["rule"], set(test.get("nodes") or [])
        rid = f"architecture.{rule}"
        if rule == "no-public-datastore":
            for e in edges:
                a, b = nodes[e["source"]], nodes[e["target"]]
                if {a["role"], b["role"]} & {"external"} and ({a["role"], b["role"]} & DATA_ROLES):
                    out.append(finding("ERROR", rid, [e["id"]], "an external party talks to a datastore directly",
                                       "route it through the edge or a service"))
        elif rule == "entry-via-edge":
            for e in edges:
                a, b = nodes[e["source"]], nodes[e["target"]]
                if a["role"] == "external" and (not scope or a["id"] in scope) and b["role"] not in ("edge", "external"):
                    out.append(finding("ERROR", rid, [e["id"]], f"'{a['id']}' enters at '{b['id']}', not through the edge",
                                       "send public traffic through the gateway"))
        elif rule == "telemetry-has-destination":
            out_t: dict[str, list[str]] = {}
            for e in edges:
                if e["type"] == "telemetry":
                    out_t.setdefault(e["source"], []).append(e["target"])
            for start in sorted(out_t):
                seen, stack, ok = {start}, [start], False
                while stack and not ok:
                    for nxt in out_t.get(stack.pop(), []):
                        if nodes[nxt]["role"] in DATA_ROLES:
                            ok = True
                            break
                        if nxt not in seen:
                            seen.add(nxt)
                            stack.append(nxt)
                if not ok:
                    out.append(finding("ERROR", rid, [start], f"telemetry from '{start}' reaches no store",
                                       "draw where the signal is kept"))
        elif rule == "gitops-has-reconciler":
            if not scope:
                out.append(finding("ERROR", rid, [], "gitops-has-reconciler needs `nodes`", "list the Flux-managed nodes"))
            for nid in sorted(scope):
                if not any(e["target"] == nid and e["type"] == "control" and nodes[e["source"]]["role"] == "platform"
                           for e in edges):
                    out.append(finding("ERROR", rid, [nid], f"'{nid}' has no reconciler edge",
                                       "add a control edge from the controller that applies it"))
    return out


def gate_house(path: str) -> list[dict]:
    errors, warnings = validate_house.check_file(path)
    out = []
    for sev, items in (("ERROR", errors), ("WARN", warnings)):
        for msg in items:
            obj = msg.split("#", 1)[1].split(":", 1)[0] if "#" in msg.split(":", 1)[0] else ""
            out.append(finding(sev, "house", [obj] if obj else [], msg.split(": ", 1)[-1], "see references/house-style.md"))
    return out


def validate(path: str, ir_path: str | None = None) -> list[dict]:
    try:
        d = Diagram(path)
    except (ET.ParseError, OSError) as exc:
        return [finding("ERROR", "structural.parse", [path], str(exc), "fix the XML")]
    ir = None
    if ir_path:
        import generate
        ir = generate.load_ir(ir_path)
    out = gate_house(path) + gate_structural(d, ir, ir_path)
    if any(f["severity"] == "ERROR" and f["rule_id"].startswith("structural.broken") for f in out):
        return out
    out += gate_connectivity(d)
    geo, routes = gate_geometry(d, ir)
    out += geo + gate_typography(d, routes)
    if ir is not None and not any(f["rule_id"].startswith("ir.") for f in out):
        out += gate_architecture(ir)
    return sorted(out, key=lambda f: (SEV_ORDER[f["severity"]], f["rule_id"], f["objects"]))


def main() -> int:
    p = argparse.ArgumentParser(description="homelab .drawio quality gates")
    p.add_argument("file")
    p.add_argument("--ir", help="the .ir.yaml this file was generated from")
    p.add_argument("--json", action="store_true", help="machine-readable report")
    p.add_argument("--strict", action="store_true", help="WARN fails the run too")
    a = p.parse_args()
    findings = validate(a.file, a.ir)
    counts = {s: sum(f["severity"] == s for f in findings) for s in SEV_ORDER}
    failed = counts["ERROR"] > 0 or (a.strict and counts["WARN"] > 0)
    if a.json:
        print(json.dumps({"file": a.file, "status": "fail" if failed else "pass", "counts": counts,
                          "findings": findings}, indent=2))
    else:
        for f in findings:
            objs = ",".join(f["objects"])
            print(f"{f['severity']:5} {f['rule_id']:36} {objs:28} {f['message']}")
            print(f"{'':6}fix: {f['fix']}")
        print(f"\n{a.file}: {counts['ERROR']} error(s), {counts['WARN']} warning(s), {counts['INFO']} info -- "
              f"{'FAIL' if failed else 'pass'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
