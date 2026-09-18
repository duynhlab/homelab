#!/usr/bin/env python3
"""doctor.py -- preflight for the homelab-drawio toolchain.

Reports which tools are present and their versions, so a diagram run does not
discover a missing binary halfway through an export. Exits non-zero when a
load-bearing tool is missing:

  drawio        required to export SVG/PNG (Draw.io Desktop CLI)
  rsvg-convert  required only when ADDING an icon (SVG -> PNG raster step), so
                it is a warning by default and a failure under --adding-icon
  magick        ImageMagick, to eyeball a new icon at 24px -- same treatment

Authoring a diagram from the existing catalog needs `drawio` and nothing else;
failing that run on a missing librsvg would block work it cannot affect.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys

from _common import find_drawio


def _version(cmd: list[str]) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        line = (out.stdout or out.stderr).strip().splitlines()
        return line[0] if line else "(no version output)"
    except Exception as exc:  # noqa: BLE001 - report, don't crash the preflight
        return f"(error: {exc})"


def main() -> int:
    p = argparse.ArgumentParser(description="homelab-drawio preflight")
    p.add_argument("--adding-icon", action="store_true",
                   help="also require the icon-rasterising tools (rsvg-convert, ImageMagick)")
    args = p.parse_args()

    print("homelab-drawio doctor\n")
    ok = True

    drawio = find_drawio()
    if drawio:
        print(f"  OK    drawio          {drawio}  [{_version([drawio, '--version'])}]")
    else:
        print("  MISS  drawio          install Draw.io Desktop: brew install --cask drawio")
        ok = False

    for tool, probe, hint, why in (
        ("rsvg-convert", ["rsvg-convert"], "brew install librsvg", "rasterise an SVG mark to PNG"),
        ("imagemagick", ["magick", "convert"], "brew install imagemagick", "eyeball a new icon at 24px"),
    ):
        found = next((w for w in (shutil.which(c) for c in probe) if w), None)
        if found:
            print(f"  OK    {tool:15} {found}")
        elif args.adding_icon:
            print(f"  MISS  {tool:15} needed to {why}: {hint}")
            ok = False
        else:
            print(f"  warn  {tool:15} only needed to {why}: {hint}")

    print(f"  OK    python          {sys.version.split()[0]}")

    print("\nready" if ok else "\nmissing a required tool -- see MISS lines above")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
