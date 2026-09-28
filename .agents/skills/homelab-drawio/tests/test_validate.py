#!/usr/bin/env python3
"""Tests for validate.py -- one fixture per gate rule, pass and fail.

Run: python3 -m unittest discover -s tests  (from the skill directory)
Stdlib only: the fixtures are hand-written XML, so no dot and no drawio.
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SKILL, "scripts"))

import validate  # noqa: E402

HEAD = ('<mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
        '<mxCell id="title" value="Fixture — scope" style="text;html=1;fontFamily=Helvetica;fontSize=18;" '
        'vertex="1" parent="1"><mxGeometry x="0" y="0" width="300" height="28" as="geometry"/></mxCell>'
        '<mxCell id="legend" value="Legend" style="rounded=1;container=1;fontFamily=Helvetica;" vertex="1" parent="1">'
        '<mxGeometry x="0" y="900" width="200" height="60" as="geometry"/></mxCell>')
TAIL = "</root></mxGraphModel>"
CARD = "rounded=1;whiteSpace=wrap;html=1;fillColor=#CFFAFE;strokeColor=#0891B2;fontColor=#164E63;fontFamily=Helvetica;fontSize=11;"


def box(cid, x, y, w=120, h=40, value=None, parent="1", style=CARD):
    return (f'<mxCell id="{cid}" value="{value if value is not None else cid}" style="{style}" vertex="1" '
            f'parent="{parent}"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')


def frame(cid, x, y, w, h, value="Frame"):
    return box(cid, x, y, w, h, value, style="rounded=1;container=1;fontFamily=Helvetica;fontSize=13;")


def edge(cid, s, t, points=(), value="", ports="exitX=0.5;exitY=1;entryX=0.5;entryY=0;"):
    pts = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in points)
    arr = f'<Array as="points">{pts}</Array>' if points else ""
    return (f'<mxCell id="{cid}" value="{value}" style="edgeStyle=orthogonalEdgeStyle;{ports}fontFamily=Helvetica;fontSize=10;" '
            f'edge="1" parent="1" source="{s}" target="{t}"><mxGeometry relative="1" as="geometry">{arr}'
            f'</mxGeometry></mxCell>')


def run(*cells, ir=None) -> list[dict]:
    fd, path = tempfile.mkstemp(suffix=".drawio")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(HEAD + "".join(cells) + TAIL)
    try:
        return validate.validate(path)
    finally:
        os.unlink(path)


def rules(findings, severity=None) -> set[str]:
    return {f["rule_id"] for f in findings if severity is None or f["severity"] == severity}


class TestGates(unittest.TestCase):
    def test_clean_pair_passes(self):
        f = run(box("a", 0, 100), box("b", 0, 240), edge("e", "a", "b"))
        self.assertEqual(rules(f, "ERROR"), set())
        self.assertFalse({"geometry.overlap", "connectivity.orphan_node"} & rules(f))

    def test_duplicate_id(self):
        self.assertIn("structural.duplicate_id", rules(run(box("a", 0, 100), box("a", 0, 300)), "ERROR"))

    def test_broken_parent(self):
        self.assertIn("structural.broken_parent", rules(run(box("a", 0, 100, parent="ghost")), "ERROR"))

    def test_dangling_edge(self):
        cell = ('<mxCell id="e" value="" style="" edge="1" parent="1" source="a">'
                '<mxGeometry relative="1" as="geometry"/></mxCell>')
        self.assertIn("connectivity.dangling_edge", rules(run(box("a", 0, 100), cell), "ERROR"))

    def test_orphan_node_warns(self):
        self.assertIn("connectivity.orphan_node", rules(run(box("a", 0, 100)), "WARN"))

    def test_overlap(self):
        f = run(box("a", 0, 100), box("b", 60, 110), edge("e", "a", "b"))
        self.assertIn("geometry.overlap", rules(f, "ERROR"))

    def test_child_overflow(self):
        f = run(frame("f", 0, 100, 100, 60), box("a", 10, 30, parent="f"), box("b", 0, 300), edge("e", "a", "b"))
        self.assertIn("geometry.child_overflow", rules(f, "ERROR"))

    def test_frame_intrusion(self):
        f = run(frame("f", 0, 100, 300, 100), box("in", 10, 40, parent="f"),
                box("out", 250, 150), edge("e", "in", "out", ports="exitX=1;exitY=0.5;entryX=0;entryY=0.5;"))
        self.assertIn("geometry.frame_intrusion", rules(f, "ERROR"))

    def test_off_canvas(self):
        f = run(box("a", -20, 100), box("b", 0, 300), edge("e", "a", "b"))
        self.assertIn("geometry.off_canvas", rules(f, "ERROR"))

    def test_edge_through_shape(self):
        # a -> c drawn straight down through b
        f = run(box("a", 0, 100), box("b", 0, 200), box("c", 0, 300),
                edge("e", "a", "c"), edge("e2", "b", "c", ports="exitX=1;exitY=0.5;entryX=1;entryY=0.5;",
                                         points=[(160, 220), (160, 320)]))
        self.assertIn("geometry.edge_through_shape", rules(f, "ERROR"))

    def test_edge_crossing_warns(self):
        f = run(box("a", 0, 100), box("b", 300, 100), box("c", 0, 400), box("d", 300, 400),
                edge("e1", "a", "d", points=[(60, 250), (360, 250)]),
                # leaves b at x=330 and runs down through e1's horizontal at y=250
                edge("e2", "b", "c", points=[(330, 300), (60, 300)],
                     ports="exitX=0.25;exitY=1;entryX=0.5;entryY=0;"))
        self.assertIn("geometry.edge_crossing", rules(f, "WARN"))

    def test_text_overflow_nowrap(self):
        style = CARD.replace("whiteSpace=wrap;", "whiteSpace=nowrap;")
        f = run(box("a", 0, 100, w=60, value="a-very-long-service-name", style=style), box("b", 0, 300),
                edge("e", "a", "b"))
        self.assertIn("typography.text_overflow", rules(f, "WARN"))

    def test_small_font(self):
        f = run(box("a", 0, 100, style=CARD.replace("fontSize=11", "fontSize=8")), box("b", 0, 300), edge("e", "a", "b"))
        self.assertIn("typography.small_font", rules(f, "WARN"))

    def test_label_collision(self):
        f = run(box("a", 0, 100), box("b", 200, 100), box("c", 0, 400), box("d", 200, 400),
                edge("e1", "a", "c", value="first label"),
                edge("e2", "b", "d", value="second label", points=[(260, 260), (80, 260), (80, 300), (260, 300)]))
        self.assertIn("typography.label_collision", rules(f, "WARN"))

    def test_animation_overuse(self):
        blue = "strokeColor=#2563EB;flowAnimation=1;"
        green = "strokeColor=#16A34A;"
        def e(cid, s, t, extra):
            return edge(cid, s, t, ports="exitX=0.5;exitY=1;entryX=0.5;entryY=0;" + extra)
        base = (box("a", 0, 100), box("b", 0, 300), box("c", 300, 300))
        all_move = run(*base, e("e1", "a", "b", blue), e("e2", "a", "c", green + "flowAnimation=1;"))
        primary = run(*base, e("e1", "a", "b", blue), e("e2", "a", "c", green))
        one_kind = run(*base, e("e1", "a", "b", blue), e("e2", "a", "c", blue))
        self.assertIn("house.animation_overuse", rules(all_move, "WARN"))
        self.assertNotIn("house.animation_overuse", rules(primary))
        self.assertNotIn("house.animation_overuse", rules(one_kind))  # a delivery graph may move entirely

    def test_one_box_many_products(self):
        import base64
        with open(os.path.join(SKILL, "assets", "icons", "victoriametrics.png"), "rb") as fh:
            logo = base64.b64encode(fh.read()).decode()
        st = CARD + f"shape=label;image=data:image/png,{logo};"
        mixed = run(box("vm", 0, 100, w=300, value="VictoriaMetrics · Logs&lt;br&gt;Pyroscope · ClickHouse", style=st),
                    box("g", 0, 300), edge("e", "vm", "g"))
        family = run(box("vm", 0, 100, w=300, value="VictoriaMetrics · VictoriaLogs&lt;br&gt;Pyroscope SDK", style=st),
                     box("g", 0, 300), edge("e", "vm", "g"))
        self.assertIn("house.one_box_many_products", rules(mixed, "WARN"))
        self.assertNotIn("house.one_box_many_products", rules(family))  # same family; a mention is not a part

    def test_legend_is_exempt(self):
        # an arrow sample inside the legend frame is not a dangling edge
        cell = ('<mxCell id="lg" value="" style="endArrow=classic;" edge="1" parent="legend">'
                '<mxGeometry relative="1" as="geometry"><mxPoint x="0" y="0" as="sourcePoint"/>'
                '<mxPoint x="20" y="0" as="targetPoint"/></mxGeometry></mxCell>')
        self.assertNotIn("connectivity.dangling_edge", rules(run(box("a", 0, 100), box("b", 0, 300),
                                                                 edge("e", "a", "b"), cell)))


class TestArchitecture(unittest.TestCase):
    NODES = [
        {"id": "u", "label": "Browser", "role": "external", "layer": "l"},
        {"id": "gw", "label": "Gateway", "role": "edge", "layer": "l"},
        {"id": "svc", "label": "svc", "role": "service", "layer": "l"},
        {"id": "db", "label": "db", "role": "data", "layer": "l"},
        {"id": "col", "label": "collector", "role": "collector", "layer": "l"},
        {"id": "flux", "label": "Flux", "role": "platform", "layer": "l"},
    ]

    def check(self, rule, edges, nodes_scope=None):
        test = {"rule": rule}
        if nodes_scope:
            test["nodes"] = nodes_scope
        return validate.gate_architecture({"nodes": self.NODES, "edges": edges, "tests": [test]})

    def test_no_public_datastore(self):
        bad = self.check("no-public-datastore", [{"id": "x", "source": "u", "target": "db", "type": "data"}])
        good = self.check("no-public-datastore", [{"id": "x", "source": "svc", "target": "db", "type": "data"}])
        self.assertEqual((len(bad), len(good)), (1, 0))

    def test_entry_via_edge(self):
        bad = self.check("entry-via-edge", [{"id": "x", "source": "u", "target": "svc", "type": "traffic"}])
        good = self.check("entry-via-edge", [{"id": "x", "source": "u", "target": "gw", "type": "traffic"}])
        self.assertEqual((len(bad), len(good)), (1, 0))

    def test_telemetry_has_destination(self):
        dead = [{"id": "t", "source": "svc", "target": "col", "type": "telemetry"}]
        kept = dead + [{"id": "t2", "source": "col", "target": "db", "type": "telemetry"}]
        self.assertEqual(len(self.check("telemetry-has-destination", dead)), 1)  # svc's signal ends at col
        self.assertEqual(self.check("telemetry-has-destination", kept), [])

    def test_gitops_has_reconciler(self):
        bad = self.check("gitops-has-reconciler", [], ["svc"])
        good = self.check("gitops-has-reconciler", [{"id": "c", "source": "flux", "target": "svc", "type": "control"}], ["svc"])
        self.assertEqual((len(bad), len(good)), (1, 0))


if __name__ == "__main__":
    unittest.main()
