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
