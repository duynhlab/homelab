#!/usr/bin/env python3
"""doctor.py -- preflight for the homelab-drawio toolchain.

Reports which tools are present and their versions, so a diagram run does not
discover a missing binary halfway through an export. Exits non-zero when a
load-bearing tool is missing:

  drawio        required to export SVG/PNG (Draw.io Desktop CLI)
  rsvg-convert  required only when ADDING an icon (SVG -> PNG raster step), so
                it is a warning by default and a failure under --adding-icon
  magick        ImageMagick, to eyeball a new icon at 24px -- same treatment
  dot           Graphviz, required by generate.py to lay an IR out top-down
  yaml, jsonschema  Python modules generate.py/validate.py read and check the IR with
  Pillow        optional: export.py quantizes the PNG with it (else ImageMagick)

Hand-editing an existing .drawio needs `drawio` alone; generating one from an
IR also needs dot + PyYAML + jsonschema. Failing a run on a missing librsvg
would block work it cannot affect, so the icon tools stay warnings.
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

    dot = shutil.which("dot")
    if dot:
        print(f"  OK    dot             {dot}  [{_version([dot, '-V'])}]")
    else:
        print(f"  MISS  dot             generate.py lays the IR out with Graphviz: {INSTALL_HINTS['graphviz']}")
        ok = False
    for mod, hint in (("yaml", "python3-yaml"), ("jsonschema", "python3-jsonschema")):
        try:
            __import__(mod)
            print(f"  OK    {mod:15} python module")
        except ImportError:
            print(f"  MISS  {mod:15} generate.py/validate.py need it: "
                  f"{'pip install ' + mod if IS_MAC else 'sudo apt install ' + hint}")
            ok = False
    try:
        __import__("PIL")
        print("  OK    pillow          export.py quantizes the PNG with it")
    except ImportError:
        print("  warn  pillow          optional -- export.py falls back to ImageMagick to quantize the PNG")

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
