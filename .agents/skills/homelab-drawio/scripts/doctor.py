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
import os
import shutil
import subprocess
import sys

from _common import INSTALL_HINTS, IS_MAC, drawio_command, find_drawio, font_fallback


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
        cmd = drawio_command(drawio)
        wrapped = f"  (runs as: {' '.join(cmd)})" if len(cmd) > 1 else ""
        print(f"  OK    drawio          {drawio}  [{_version([*cmd, '--version'])}]{wrapped}")
        if not IS_MAC and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")) \
                and not shutil.which("xvfb-run"):
            print(f"  MISS  xvfb-run        no display server, so Electron cannot start: {INSTALL_HINTS['xvfb-run']}")
            ok = False
    else:
        print(f"  MISS  drawio          install Draw.io Desktop: {INSTALL_HINTS['drawio']}")
        ok = False

    for tool, probe, hint, why in (
        ("rsvg-convert", ["rsvg-convert"], INSTALL_HINTS["rsvg-convert"], "rasterise an SVG mark to PNG"),
        ("imagemagick", ["magick", "convert"], INSTALL_HINTS["imagemagick"], "eyeball a new icon at 24px"),
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

    # Helvetica is the house font. Linux renders it with a metric-compatible
    # clone; anything else changes label widths and can overflow boxes.
    fb = font_fallback("Helvetica")
    if fb is None:
        print("  info  font            fc-match not found; cannot check the Helvetica fallback")
    elif fb.lower() in ("helvetica", "nimbus sans", "nimbus sans l", "liberation sans", "arimo", "tex gyre heros"):
        print(f"  OK    font            Helvetica renders as {fb} (same metrics)")
    else:
        print(f"  warn  font            Helvetica renders as {fb}: labels may be wider than on macOS "
              f"-- install a metric-compatible clone ({'n/a' if IS_MAC else 'sudo apt install fonts-urw-base35'})")

    print("\nready" if ok else "\nmissing a required tool -- see MISS lines above")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
