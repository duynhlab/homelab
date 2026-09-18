#!/usr/bin/env python3
"""Deterministic tests for the homelab-drawio helper scripts.

Run: python3 -m unittest discover -s tests  (from the skill directory)
Stdlib only -- no network, no drawio binary.
"""
from __future__ import annotations

import hashlib
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SKILL, "scripts"))

import _common  # noqa: E402
import export  # noqa: E402
import validate_house  # noqa: E402


def _write(text: str) -> str:
    fd, path = tempfile.mkstemp(suffix=".drawio")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


CLEAN = """<mxGraphModel><root>
<mxCell id="0"/><mxCell id="1" parent="0"/>
<mxCell id="ttl" value="Title — scope" style="text;html=1;fontFamily=Helvetica;fontSize=18;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="0" y="0" width="300" height="26" as="geometry"/></mxCell>
<mxCell id="a" value="user-service" style="rounded=1;fillColor=#06B6D4;strokeColor=#0E7490;fontColor=#082F49;fontFamily=Helvetica;" vertex="1" parent="1"><mxGeometry x="0" y="0" width="120" height="40" as="geometry"/></mxCell>
<mxCell id="lg" value="Legend" style="fillColor=none;fontFamily=Helvetica;" vertex="1" parent="1"><mxGeometry x="0" y="80" width="120" height="40" as="geometry"/></mxCell>
</root></mxGraphModel>"""


class TestCommon(unittest.TestCase):
    def test_resolve_icon_known(self):
        path, label = _common.resolve_icon("flux")
        self.assertTrue(path.endswith("flux.png"))
        self.assertEqual(label, "Flux")

    def test_resolve_icon_alias(self):
        path, _ = _common.resolve_icon("victorialogs")
        self.assertTrue(path.endswith("victoriametrics.png"))

    def test_resolve_icon_unknown(self):
        with self.assertRaises(KeyError):
            _common.resolve_icon("does-not-exist")

    def test_role_style_known(self):
        rs = _common.role_style("service")
        self.assertEqual(rs["fillColor"], "#06B6D4")
        self.assertEqual(rs["fontColor"], "#082F49")

    def test_role_style_unknown(self):
        with self.assertRaises(KeyError):
            _common.role_style("bogus")

    def test_planned_role_is_dashed(self):
        self.assertTrue(_common.role_style("planned").get("dashed"))

    def test_role_dashed_only_for_planned(self):
        self.assertEqual(_common.role_dashed("planned"), "dashed=1;")
        self.assertEqual(_common.role_dashed("service"), "")

    def test_is_frame_structural(self):
        """A cell that owns children is a frame whatever its style.

        The house container is a styled rectangle, so keying only on
        `container=1`/`swimlane` left this check unfireable.
        """
        parents = {"f_apps"}
        card = "rounded=1;fillColor=#06B6D4;"
        self.assertTrue(_common.is_frame(card, "f_apps", parents))
        self.assertFalse(_common.is_frame(card, "svc", parents))
        # declared forms still count, for hand-authored cells
        self.assertTrue(_common.is_frame("swimlane;html=1;", "x", set()))
        self.assertTrue(_common.is_frame("container=1;", "x", set()))
        # the unstyled layer cells parent everything but are not drawn
        self.assertFalse(_common.is_frame("", "1", {"1"}))


class TestManifestIntegrity(unittest.TestCase):
    """Every catalogued icon exists and its bytes match the recorded checksum."""

    def test_files_and_checksums(self):
        m = _common.load_manifest()
        self.assertGreaterEqual(len(m["icons"]), 10)
        for name, entry in m["icons"].items():
            p = os.path.join(_common.ICONS, entry["file"])
            self.assertTrue(os.path.isfile(p), f"missing {entry['file']} for {name}")
            with open(p, "rb") as fh:
                data = fh.read()
            self.assertEqual(len(data), entry["bytes"], f"{name} byte count drift")
            self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"], f"{name} checksum drift")
            self.assertTrue(data[:8] == b"\x89PNG\r\n\x1a\n", f"{name} is not a PNG")

    def test_aliases_point_at_real_icons(self):
        m = _common.load_manifest()
        for alias, target in m.get("aliases", {}).items():
            self.assertIn(target, m["icons"], f"alias {alias} -> unknown {target}")


class TestIconStyle(unittest.TestCase):
    def test_label_style_comma_not_base64(self):
        import icon_style  # imported here so a manifest error surfaces per-test

        class Args:
            name = "flux"
            role = "platform"
            label = None

        # cmd_style prints; capture stdout
        import io
        import contextlib

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = icon_style.cmd_style(Args())
        out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("image=data:image/png,", out)
        self.assertNotIn(";base64,", out)
        self.assertIn("fillColor=#7C3AED", out)  # platform fill
        self.assertIn("fontFamily=Helvetica", out)
        self.assertNotIn("dashed=1", out)  # platform is a solid role

    def test_planned_role_emits_dashed(self):
        """`--role planned` must produce a dashed box.

        The palette marks planned dashed, but the style template had no slot for
        it, so the one role with a hard rule was the one emitted wrong -- and the
        validator could not catch it, because an undashed box is not a planned
        box as far as the style is concerned.
        """
        import contextlib
        import io

        import icon_style

        class Args:
            name = "flux"
            role = "planned"
            label = None

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            icon_style.cmd_style(Args())
        self.assertIn("dashed=1", buf.getvalue())

    def test_first_line_splits_on_markup_breaks(self):
        """Draw.io writes line breaks as <br>/&#10;, never a literal newline.

        Stripping tags before splitting collapsed every line into one, which
        silently searched a box's prose as if it were its subject.
        """
        import icon_style

        self.assertEqual(
            icon_style._first_line("Leaf certificates<br>cert-manager-issued"),
            "leaf certificates",
        )
        self.assertEqual(
            icon_style._first_line("Leaf certificates&#10;cert-manager-issued"),
            "leaf certificates",
        )


class TestAuditRecursion(unittest.TestCase):
    """`audit <parent>` must find diagrams below the directory it is given.

    A non-recursive glob made it print "every box already carries its logo" and
    exit 0 while the diagrams sat one level down -- a false clean.
    """

    def _audit(self, root: str):
        import contextlib
        import io

        import icon_style

        class Args:
            dir = root

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = icon_style.cmd_audit(Args())
        return rc, buf.getvalue()

    def test_finds_nested_diagram(self):
        with tempfile.TemporaryDirectory() as td:
            nested = os.path.join(td, "architecture")
            os.makedirs(nested)
            with open(os.path.join(nested, "d.drawio"), "w", encoding="utf-8") as fh:
                fh.write(CLEAN.replace('value="user-service"', 'value="Grafana"'))
            rc, out = self._audit(td)
        self.assertEqual(rc, 0)
        self.assertIn("1 diagram(s)", out)
        self.assertIn("grafana", out)

    def test_annotations_and_legend_rows_are_exempt(self):
        """A caption or legend row names a product without being one.

        Flagging them turned the advisory into noise on a diagram whose legend
        says "Datastore (ClickHouse)".
        """
        doc = CLEAN.replace(
            "</root>",
            '<mxCell id="cap" value="Grafana reads this" style="text;html=1;" vertex="1" '
            'parent="1"><mxGeometry x="0" y="200" width="200" height="20" as="geometry"/></mxCell>'
            '<mxCell id="lgrow" value="Datastore (ClickHouse)" style="rounded=1;" vertex="1" '
            'parent="lg"><mxGeometry x="0" y="0" width="120" height="20" as="geometry"/></mxCell>'
            "</root>",
        )
        with tempfile.TemporaryDirectory() as td:
            with open(os.path.join(td, "d.drawio"), "w", encoding="utf-8") as fh:
                fh.write(doc)
            rc, out = self._audit(td)
        self.assertEqual(rc, 0)
        self.assertIn("already carries its logo", out)

    def test_empty_dir_is_not_a_silent_pass(self):
        with tempfile.TemporaryDirectory() as td:
            rc, out = self._audit(td)
        self.assertEqual(rc, 1)
        self.assertNotIn("already carries its logo", out)


class TestValidateHouse(unittest.TestCase):
    def _errs(self, text: str):
        p = _write(text)
        try:
            return validate_house.check_file(p)
        finally:
            os.unlink(p)

    def test_clean_passes(self):
        errors, warnings = self._errs(CLEAN)
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])  # has a legend, Helvetica

    def test_base64_trap(self):
        text = CLEAN.replace('style="rounded=1;fillColor=#06B6D4', 'style="rounded=1;image=data:image/png;base64,AAAA;fillColor=#06B6D4')
        errors, _ = self._errs(text)
        self.assertTrue(any("';base64,'" in e for e in errors))

    def test_svg_data_uri(self):
        text = CLEAN.replace('style="rounded=1;fillColor=#06B6D4', 'style="rounded=1;image=data:image/svg+xml,PHN2Zz48L3N2Zz4=;fillColor=#06B6D4')
        errors, _ = self._errs(text)
        self.assertTrue(any("SVG data URI" in e for e in errors))

    def test_icon_on_frame(self):
        text = CLEAN.replace('style="rounded=1;fillColor=#06B6D4', 'style="rounded=1;container=1;image=data:image/png,AAAA;fillColor=#06B6D4')
        errors, _ = self._errs(text)
        self.assertTrue(any("grouping frame" in e for e in errors))

    def test_planned_style_without_word(self):
        text = CLEAN.replace(
            '<mxCell id="lg" value="Legend"',
            '<mxCell id="p" value="checkout-worker" style="dashed=1;strokeColor=#64748B;fillColor=#FFFFFF;fontFamily=Helvetica;" vertex="1" parent="1"><mxGeometry x="0" y="140" width="120" height="40" as="geometry"/></mxCell>\n<mxCell id="lg" value="Legend"',
        )
        errors, _ = self._errs(text)
        self.assertTrue(any("omits 'planned'" in e for e in errors))

    def test_planned_legend_is_not_flagged(self):
        # A legend that lists 'planned' as a role must not be forced dashed.
        text = CLEAN.replace('value="Legend"', 'value="Legend: service, data, planned"')
        errors, _ = self._errs(text)
        self.assertEqual(errors, [])

    def test_dashed_external_box_is_not_planned(self):
        """#64748B is the planned STROKE and the external FILL.

        A substring test for the colour therefore flagged every dashed external
        box as a mislabelled planned one.
        """
        text = CLEAN.replace(
            'style="rounded=1;fillColor=#06B6D4;strokeColor=#0E7490',
            'style="rounded=1;dashed=1;fillColor=#64748B;strokeColor=#334155',
        )
        errors, _ = self._errs(text)
        self.assertEqual(errors, [])

    def test_planned_label_without_dash_warns(self):
        text = CLEAN.replace('value="user-service"', 'value="checkout-worker (planned)"')
        errors, warnings = self._errs(text)
        self.assertEqual(errors, [])
        self.assertTrue(any("not dashed" in w for w in warnings), warnings)

    def test_planned_word_in_annotation_is_exempt(self):
        text = CLEAN.replace('value="Title — scope"', 'value="Title — the planned migration"')
        errors, warnings = self._errs(text)
        self.assertEqual(errors, [])
        self.assertFalse(any("not dashed" in w for w in warnings), warnings)

    def _with_edge(self, style: str) -> str:
        return CLEAN.replace(
            "</root>",
            f'<mxCell id="e1" style="{style}" edge="1" parent="1" '
            'source="a" target="lg"><mxGeometry relative="1" as="geometry"/></mxCell></root>',
        )

    def test_unlabelled_dashed_edge_warns(self):
        _, warnings = self._errs(self._with_edge("edgeStyle=orthogonalEdgeStyle;dashed=1;"))
        self.assertTrue(any("unlabelled dashed edge" in w for w in warnings), warnings)

    def test_unlabelled_solid_edge_is_not_flagged(self):
        """A graph whose every arrow means one thing declares it in the legend.

        Only AGENTS.md's dashed-edge rule is mechanical; labelling solid edges is
        a judgement call on the review checklist.
        """
        _, warnings = self._errs(self._with_edge("edgeStyle=orthogonalEdgeStyle;"))
        self.assertFalse(any("unlabelled" in w for w in warnings), warnings)

    def test_missing_title_warns(self):
        text = CLEAN.replace('value="Title — scope"', 'value=""')
        _, warnings = self._errs(text)
        self.assertTrue(any("no title cell" in w for w in warnings), warnings)

    def test_non_helvetica_warns(self):
        text = CLEAN.replace("fontFamily=Helvetica;", "fontFamily=Comic Sans MS;")
        _, warnings = self._errs(text)
        self.assertTrue(any("not the house font" in w for w in warnings))

    def test_missing_legend_warns(self):
        text = CLEAN.replace('<mxCell id="lg" value="Legend" style="fillColor=none;fontFamily=Helvetica;" vertex="1" parent="1"><mxGeometry x="0" y="80" width="120" height="40" as="geometry"/></mxCell>', "")
        _, warnings = self._errs(text)
        self.assertTrue(any("no legend" in w for w in warnings))

    def test_compressed_file_reports_clearly(self):
        p = _write("<mxfile><diagram>7VpNc9s2</diagram></mxfile>")
        try:
            errors, _ = validate_house.check_file(p)
        finally:
            os.unlink(p)
        self.assertTrue(any("compressed" in e for e in errors))


class TestExport(unittest.TestCase):
    def test_page_count_single(self):
        p = _write(CLEAN)
        try:
            self.assertEqual(export.page_count(p), 1)
        finally:
            os.unlink(p)

    def test_flow_ids_are_stabilised(self):
        """Draw.io mints a fresh random keyframe id on every export.

        Both occurrences (the @keyframes definition and the animation:
        reference) must renumber together, or the animation stops resolving.
        """
        svg = (
            "<svg><style>@keyframes ge-flow-animation-AbC123xyz { to { } }</style>"
            "<path style=\"animation: 500ms linear ge-flow-animation-AbC123xyz;\"/></svg>"
        )
        fd, path = tempfile.mkstemp(suffix=".svg")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(svg)
        try:
            export._stabilise_flow_ids(path)
            with open(path, encoding="utf-8") as fh:
                out = fh.read()
        finally:
            os.unlink(path)
        self.assertNotIn("AbC123xyz", out)
        self.assertEqual(out.count("ge-flow-animation-1"), 2)

    def test_page_count_multi(self):
        multi = (
            "<mxfile>"
            '<diagram name="p1" id="a"><mxGraphModel><root><mxCell id="0"/></root></mxGraphModel></diagram>'
            '<diagram name="p2" id="b"><mxGraphModel><root><mxCell id="0"/></root></mxGraphModel></diagram>'
            "</mxfile>"
        )
        p = _write(multi)
        try:
            self.assertEqual(export.page_count(p), 2)
        finally:
            os.unlink(p)


if __name__ == "__main__":
    unittest.main(verbosity=2)
