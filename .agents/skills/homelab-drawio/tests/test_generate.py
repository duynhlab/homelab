#!/usr/bin/env python3
"""Tests for generate.py (Diagram IR -> top-down .drawio).

Run: python3 -m unittest discover -s tests  (from the skill directory)
Needs Graphviz `dot`, PyYAML and jsonschema; each test class skips cleanly
without them. No network, no drawio binary.
"""
from __future__ import annotations

import copy
import glob
import os
import shutil
import sys
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(SKILL)))
sys.path.insert(0, os.path.join(SKILL, "scripts"))

try:
    import jsonschema  # noqa: F401
    import yaml  # noqa: F401
    import generate
    HAVE_DEPS = shutil.which("dot") is not None
except ImportError:
    HAVE_DEPS = False

BASE = {
    "diagram": {"id": "t", "title": "Test — fixture", "scope": "unit test", "question": "request-path", "level": "L2"},
    "layers": ["client", "edge", "apps", "data"],
    "boundaries": [{"id": "f_apps", "label": "Applications"}],
    "nodes": [
        {"id": "browser", "label": "Browser", "role": "external", "layer": "client"},
        {"id": "gw", "label": "Envoy Gateway", "role": "edge", "layer": "edge", "icon": "envoy"},
        {"id": "a", "label": "user-service", "role": "service", "layer": "apps", "parent": "f_apps"},
        {"id": "b", "label": "order-service", "role": "service", "layer": "apps", "parent": "f_apps"},
        {"id": "db", "label": "product-db", "role": "data", "layer": "data", "shape": "datastore"},
    ],
    "edges": [
        {"id": "e1", "source": "browser", "target": "gw", "type": "traffic", "protocol": "HTTPS"},
        {"id": "e2", "source": "gw", "target": "a", "type": "traffic"},
        {"id": "e3", "source": "gw", "target": "b", "type": "traffic"},
        {"id": "e4", "source": "a", "target": "db", "type": "data", "label": "SQL"},
        {"id": "e5", "source": "gw", "target": "db", "type": "dependency", "label": "skips a layer"},
    ],
}


def _ir(**changes) -> dict:
    ir = copy.deepcopy(BASE)
    for k, v in changes.items():
        ir[k] = v
    return ir


def _cells(xml: str) -> dict[str, ET.Element]:
    return {c.get("id"): c for c in ET.fromstring(xml).iter("mxCell")}


def _abs_y(cells, cid) -> float:
    c, y = cells[cid], 0.0
    while c is not None:
        g = c.find("mxGeometry")
        if g is not None and c.get("vertex") == "1":
            y += float(g.get("y", 0))
        c = cells.get(c.get("parent") or "")
    return y


@unittest.skipUnless(HAVE_DEPS, "needs graphviz dot, PyYAML and jsonschema")
class TestGenerate(unittest.TestCase):
    def test_deterministic(self):
        self.assertEqual(generate.build(_ir()), generate.build(_ir()))

    def test_layers_run_top_down(self):
        cells = _cells(generate.build(_ir()))
        ys = [_abs_y(cells, n) for n in ("browser", "gw", "a", "db")]
        self.assertEqual(ys, sorted(ys))
        self.assertEqual(_abs_y(cells, "a"), _abs_y(cells, "b"))  # peers share a row

    def test_children_are_owned_by_their_frame(self):
        cells = _cells(generate.build(_ir()))
        self.assertEqual(cells["a"].get("parent"), "f_apps")
        self.assertIn("container=1", cells["f_apps"].get("style"))

    def test_routes_are_written_into_the_file(self):
        cells = _cells(generate.build(_ir()))
        e5 = cells["e5"]
        self.assertIn("exitX=", e5.get("style"))
        self.assertIsNotNone(e5.find("mxGeometry/Array"))  # skip-layer edge carries waypoints

    def test_legend_lists_only_used_roles_and_edges(self):
        cells = _cells(generate.build(_ir()))
        roles = {c[len("legend-role-"):] for c in cells if c.startswith("legend-role-") and not c.endswith("-text")}
        edges = {c[len("legend-edge-"):] for c in cells if c.startswith("legend-edge-") and not c.endswith("-text")}
        self.assertEqual(roles, {"external", "edge", "service", "data"})
        self.assertEqual(edges, {"traffic", "data", "dependency"})

    def test_planned_node_is_dashed(self):
        ir = _ir()
        ir["nodes"].append({"id": "p", "label": "search (planned)", "role": "service", "layer": "apps",
                            "parent": "f_apps", "status": "planned"})
        ir["edges"].append({"id": "e6", "source": "gw", "target": "p", "type": "traffic",
                            "status": "planned", "label": "planned route"})
        cells = _cells(generate.build(ir))
        self.assertIn("dashed=1", cells["p"].get("style"))
        self.assertIn("dashed=1", cells["e6"].get("style"))

    def test_notes_are_drawn_above_the_legend(self):
        cells = _cells(generate.build(_ir(notes=[{"id": "n1", "title": "Read me", "text": "one note"}])))
        self.assertLess(_abs_y(cells, "n1"), _abs_y(cells, "legend"))

    def test_rejects_planned_without_the_word(self):
        ir = _ir()
        ir["nodes"][2]["status"] = "planned"
        with self.assertRaises(generate.IRError) as cm:
            generate.build(ir)
        self.assertIn("house.planned_label", [p[0] for p in cm.exception.problems])

    def test_rejects_dangling_edge(self):
        ir = _ir()
        ir["edges"].append({"id": "bad", "source": "a", "target": "nope", "type": "data"})
        with self.assertRaises(generate.IRError) as cm:
            generate.build(ir)
        self.assertIn("connectivity.dangling_edge", [p[0] for p in cm.exception.problems])

    def test_rejects_unknown_role_via_schema(self):
        ir = _ir()
        ir["nodes"][0]["role"] = "sparkly"
        with self.assertRaises(generate.IRError) as cm:
            generate.build(ir)
        self.assertEqual(cm.exception.problems[0][0], "ir.schema")

    def test_rejects_icon_on_datastore(self):
        ir = _ir()
        ir["nodes"][4]["icon"] = "postgresql"
        with self.assertRaises(generate.IRError) as cm:
            generate.build(ir)
        self.assertIn("structural.icon_on_datastore", [p[0] for p in cm.exception.problems])

    def test_rejects_duplicate_ids_across_kinds(self):
        ir = _ir()
        ir["edges"][0]["id"] = "gw"
        with self.assertRaises(generate.IRError) as cm:
            generate.build(ir)
        self.assertIn("structural.duplicate_id", [p[0] for p in cm.exception.problems])

    def test_repo_diagrams_match_their_ir(self):
        """Every committed .drawio with an IR beside it is exactly that IR's output."""
        irs = sorted(glob.glob(os.path.join(REPO, "docs", "**", "*.ir.yaml"), recursive=True))
        self.assertTrue(irs, "no .ir.yaml under docs/")
        for path in irs:
            with self.subTest(ir=os.path.relpath(path, REPO)):
                with open(path[: -len(".ir.yaml")] + ".drawio", encoding="utf-8") as fh:
                    self.assertEqual(generate.build(generate.load_ir(path)), fh.read(),
                                     "stale: run generate.py on this IR")


if __name__ == "__main__":
    unittest.main()
