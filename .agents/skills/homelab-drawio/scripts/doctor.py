#!/usr/bin/env python3
"""doctor.py -- preflight for the homelab-drawio toolchain.

Reports which tools are present and their versions, so a diagram run does not
discover a missing binary halfway through an export. Exits non-zero when a
load-bearing tool is missing:

  drawio        required to export SVG/PNG (Draw.io Desktop CLI)
  rsvg-convert  required only when ADDING an icon (SVG -> PNG raster step)

magick/convert (ImageMagick) is advisory -- used to eyeball an icon at 24px.
"""
from __future__ import annotations

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
    print("homelab-drawio doctor\n")
    ok = True

    drawio = find_drawio()
    if drawio:
        print(f"  OK    drawio          {drawio}  [{_version([drawio, '--version'])}]")
    else:
        print("  MISS  drawio          install Draw.io Desktop: brew install --cask drawio")
        ok = False

    rsvg = shutil.which("rsvg-convert")
    if rsvg:
        print(f"  OK    rsvg-convert    {rsvg}  [{_version([rsvg, '--version'])}]")
    else:
        print("  MISS  rsvg-convert    needed only to add icons: brew install librsvg")
        ok = False

    magick = shutil.which("magick") or shutil.which("convert")
    if magick:
        print(f"  OK    imagemagick     {magick}  (advisory: eyeball icons at 24px)")
    else:
        print("  warn  imagemagick     optional: brew install imagemagick")

    print(f"  OK    python          {sys.version.split()[0]}")

    print("\nready" if ok else "\nmissing a required tool -- see MISS lines above")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
