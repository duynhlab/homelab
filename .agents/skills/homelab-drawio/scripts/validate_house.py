#!/usr/bin/env python3
"""validate_house.py -- homelab house-style checks for a .drawio source.

Complements the generic drawio-skill validate.py (which checks structure). This
enforces the conventions that make a Draw.io diagram read as one system with the
repo's Mermaid diagrams, and catches the two silent embedding traps.

ERRORS (exit 1):
  * image=data: joined with ';base64,'  -- the semicolon truncates the style
  * image=data:image/svg...             -- headless export renders an empty box
  * a logo on a grouping frame          -- it labels the grouping, not a thing
  * a node styled planned (dashed + the planned stroke) whose label omits the
                                           word 'planned' (AGENTS.md step 5)

WARNINGS (exit 0, or 1 with --strict):
  * a label containing 'planned' on a node that is NOT dashed -- the other half
    of the same rule. A warning rather than an error because legends and prose
    ("planned migration") legitimately say the word; legend cells and text
    annotations are skipped outright.
  * a non-Helvetica font                 -- the house font
  * no legend cell                       -- an architecture diagram needs one
  * no title cell                        -- a reader must see what they opened
  * an unlabelled DASHED edge            -- AGENTS.md step 5: a dotted arrow
                                           means optional/indirect/planned/an
                                           exception, and must say which.
                                           Solid edges are left to the human
                                           review checklist: a graph whose every
                                           arrow means the same thing says so
                                           once in its legend, and 17 identical
                                           labels would be noise.

Usage: validate_house.py <file.drawio> [<file.drawio> ...] [--strict]
"""
from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET

from _common import is_frame, parent_ids

# The planned role's STROKE. Matched as an attribute, never as a bare substring:
# #64748B is also the `external` role's FILL, so a substring test flagged every
# dashed external box as a mislabelled planned one.
PLANNED_STROKE_RE = re.compile(r"strokeColor=#64748b\b", re.I)
TITLE_MIN_FONT = 14


def _cells(path: str):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if "<mxGraphModel" not in text:
        raise ValueError(
            "compressed or non-native .drawio (no <mxGraphModel>). Re-save uncompressed "
            "(Draw.io: Extras -> Edit Diagram, or author uncompressed XML)."
        )
    root = ET.fromstring(text)
    return [c for c in root.iter("mxCell")]


def _font_size(style: str) -> int:
    m = re.search(r"fontSize=(\d+)", style)
    return int(m.group(1)) if m else 0


def check_file(path: str) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    try:
        cells = _cells(path)
    except (ET.ParseError, ValueError) as exc:
        return [f"{path}: {exc}"], []

    parents = parent_ids(cells)
    # Cells that are, or live inside, a legend: the legend names every role it
    # explains, so it says "planned" without being planned.
    legend_ids = {
        c.get("id")
        for c in cells
        if "legend" in (c.get("value") or "").lower()
    }

    has_legend = bool(legend_ids)
    has_title = False

    for c in cells:
        style = c.get("style") or ""
        value = (c.get("value") or "").strip()
        low = value.lower()
        cid = c.get("id")
        is_edge = c.get("edge") == "1"
        is_annotation = style.startswith("text;")

        if is_annotation and _font_size(style) >= TITLE_MIN_FONT and value:
            has_title = True

        if "image=data:" in style:
            if ";base64," in style:
                errors.append(f"{path}#{cid}: image uses ';base64,' -- use a comma; the semicolon truncates the style")
            if "image=data:image/svg" in style:
                errors.append(f"{path}#{cid}: SVG data URI -- headless export renders an empty box; rasterise to PNG")

        has_png = "image=data:image/png" in style
        if has_png and is_frame(style, cid, parents):
            errors.append(f"{path}#{cid}: logo on a grouping frame -- it labels the grouping, not a thing")

        # Both halves of AGENTS.md step 5. A node drawn in the planned style must
        # say so (error -- the style is unambiguous). A node whose label says
        # 'planned' must be dashed (warning -- the word has innocent uses, so
        # legends and text annotations are exempt).
        is_planned_style = "dashed=1" in style and PLANNED_STROKE_RE.search(style)
        says_planned = "planned" in low
        exempt = is_annotation or cid in legend_ids or c.get("parent") in legend_ids

        if is_planned_style and value and not says_planned:
            errors.append(f"{path}#{cid}: styled planned (dashed + slate) but label omits 'planned'")
        if says_planned and "dashed=1" not in style and not exempt:
            warnings.append(f"{path}#{cid}: label says 'planned' but the cell is not dashed")

        if is_edge and not value and "dashed=1" in style:
            warnings.append(f"{path}#{cid}: unlabelled dashed edge -- say which it is (optional, indirect, planned, exception)")

        if "fontFamily=" in style:
            fam = style.split("fontFamily=", 1)[1].split(";", 1)[0]
            if fam and fam.lower() != "helvetica":
                warnings.append(f"{path}#{cid}: font '{fam}' is not the house font Helvetica")

    if not has_legend:
        warnings.append(f"{path}: no legend cell found -- an architecture diagram should carry its own legend")
    if not has_title:
        warnings.append(f"{path}: no title cell found -- name the diagram and its scope on the canvas")
    return errors, warnings


def main() -> int:
    p = argparse.ArgumentParser(description="homelab-drawio house-style validator")
    p.add_argument("files", nargs="+")
    p.add_argument("--strict", action="store_true", help="treat warnings as failures")
    args = p.parse_args()

    all_errors: list[str] = []
    all_warnings: list[str] = []
    for path in args.files:
        e, w = check_file(path)
        all_errors += e
        all_warnings += w

    for w in all_warnings:
        print(f"WARN  {w}")
    for e in all_errors:
        print(f"ERROR {e}", file=sys.stderr)

    if all_errors:
        print(f"\n{len(all_errors)} error(s), {len(all_warnings)} warning(s)", file=sys.stderr)
        return 1
    print(f"house-style OK ({len(all_warnings)} warning(s))")
    return 1 if (args.strict and all_warnings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
