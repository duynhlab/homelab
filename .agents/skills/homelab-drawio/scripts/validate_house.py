#!/usr/bin/env python3
"""validate_house.py -- homelab house-style checks for a .drawio source.

Complements the generic drawio-skill validate.py (which checks structure). This
enforces the conventions that make a Draw.io diagram read as one system with the
repo's Mermaid diagrams, and catches the two silent embedding traps.

ERRORS (exit 1):
  * image=data: joined with ';base64,'  -- the semicolon truncates the style
  * image=data:image/svg...             -- headless export renders an empty box
  * a logo on a grouping frame          -- it labels the grouping, not a thing
  * planned state not marked both ways   -- a planned node must say 'planned'
                                           AND be dashed (AGENTS.md step 5)

WARNINGS (exit 0, or 1 with --strict):
  * a non-Helvetica font                 -- the house font
  * no legend cell                       -- an architecture diagram needs one

Usage: validate_house.py <file.drawio> [<file.drawio> ...] [--strict]
"""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET

PLANNED_STROKE = "#64748b"


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


def check_file(path: str) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    try:
        cells = _cells(path)
    except (ET.ParseError, ValueError) as exc:
        return [f"{path}: {exc}"], []

    has_legend = False
    for c in cells:
        style = c.get("style") or ""
        value = (c.get("value") or "").strip()
        low = value.lower()
        if "legend" in low:
            has_legend = True

        if "image=data:" in style:
            if ";base64," in style:
                errors.append(f"{path}#{c.get('id')}: image uses ';base64,' -- use a comma; the semicolon truncates the style")
            if "image=data:image/svg" in style:
                errors.append(f"{path}#{c.get('id')}: SVG data URI -- headless export renders an empty box; rasterise to PNG")

        has_png = "image=data:image/png" in style
        is_frame = "container=1" in style or "swimlane" in style
        if has_png and is_frame:
            errors.append(f"{path}#{c.get('id')}: logo on a grouping frame -- it labels the grouping, not a thing")

        # A node drawn in the planned style (dashed + slate stroke) must say so,
        # per AGENTS.md step 5. The reverse (any label mentioning "planned" must
        # be dashed) is deliberately NOT enforced -- it false-positives on
        # legends and on prose like "planned migration" in an annotation.
        is_planned_style = "dashed=1" in style and PLANNED_STROKE in style.lower()
        says_planned = "planned" in low
        if is_planned_style and value and not says_planned:
            errors.append(f"{path}#{c.get('id')}: styled planned (dashed + slate) but label omits 'planned'")

        if "fontFamily=" in style:
            fam = style.split("fontFamily=", 1)[1].split(";", 1)[0]
            if fam and fam.lower() != "helvetica":
                warnings.append(f"{path}#{c.get('id')}: font '{fam}' is not the house font Helvetica")

    if not has_legend:
        warnings.append(f"{path}: no legend cell found -- an architecture diagram should carry its own legend")
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
