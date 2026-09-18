#!/usr/bin/env python3
"""export.py -- reproducible SVG/PNG export for a homelab .drawio source.

Wraps the Draw.io CLI with the flags this repo needs, so an export is the same
whoever runs it:

  * --embed-svg-fonts false  -- Draw.io embeds the full font as base64 by
    default (>1 MB); the house font is web-safe Helvetica, so nothing is lost
  * -b 10 border, and a size budget per SVG (500 KB) and per PNG (400 KB) --
    the PNG is the file GitHub actually downloads on every README view, so it
    is the one worth keeping honest
  * --page-index is 1-BASED in this CLI: a multi-page file is looped 1..N, and
    exporting 0 silently repeats page 1
  * a trailing newline is appended to each SVG (Draw.io omits it)
  * flowAnimation keyframe ids are normalised: Draw.io mints a fresh random one
    on every export, so an animated diagram produced a different SVG every run

Prints the Draw.io version so a diff that looks like noise can be traced to a
different build. SVG is the default; add --png for the one raster GitHub needs.

Usage: export.py <src.drawio> [--out-dir DIR] [--png] [--budget-kb 500]
                  [--png-budget-kb 400] [--png-width 1536] [--png-dir DIR]
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from _common import find_drawio

SVG_OPTS = ["-x", "-f", "svg", "-b", "10", "--embed-svg-fonts", "false"]


def page_count(src: str) -> int:
    try:
        with open(src, encoding="utf-8") as fh:
            root = ET.fromstring(fh.read())
    except (OSError, ET.ParseError):
        return 1
    n = len(root.findall("diagram"))
    return n if n else 1


# Draw.io mints a random keyframe id per export for flowAnimation edges, e.g.
# `ge-flow-animation-IwqhiStrplj6VKUFyiaf`. It appears twice -- the @keyframes
# definition and the animation: reference -- and changes every run, so the SVG
# of any animated diagram never matched its committed copy. Renumbering by order
# of appearance keeps the animation working and the export reproducible.
_FLOW_ID = re.compile(r"ge-flow-animation-[A-Za-z0-9_-]+")


def _stabilise_flow_ids(path: str) -> None:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    seen: dict[str, str] = {}

    def repl(m: "re.Match[str]") -> str:
        return seen.setdefault(m.group(0), f"ge-flow-animation-{len(seen) + 1}")

    new = _FLOW_ID.sub(repl, text)
    if new != text:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)


def _append_newline(path: str) -> None:
    if not os.path.exists(path):
        return
    with open(path, "rb") as fh:
        data = fh.read()
    if data and not data.endswith(b"\n"):
        with open(path, "ab") as fh:
            fh.write(b"\n")


def _run(drawio: str, args: list[str]) -> None:
    proc = subprocess.run([drawio, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit(f"drawio export failed ({' '.join(args)})")


def main() -> int:
    p = argparse.ArgumentParser(description="homelab-drawio export")
    p.add_argument("src")
    p.add_argument("--out-dir", default=None, help="output directory (default: alongside src)")
    p.add_argument("--png", action="store_true", help="also export page 1 to PNG")
    p.add_argument("--budget-kb", type=int, default=500, help="per-SVG size budget in KB (default 500)")
    p.add_argument("--png-budget-kb", type=int, default=400, help="per-PNG size budget in KB (default 400)")
    p.add_argument("--png-dir", default=None,
                   help="directory for the PNG (default: same as --out-dir). The repo convention "
                        "is the SVG beside the source and the PNG under img/, which needs both")
    p.add_argument("--png-width", type=int, default=1536,
                   help="PNG width in px (default 1536: ~1.7x the 920px README display width, and "
                        "the widest that fits the 400 KB budget for a full-platform diagram). "
                        "--width beats -s because it is absolute -- a scale factor makes the "
                        "output depend on the page size, so a bigger canvas silently means a bigger file")
    args = p.parse_args()

    drawio = find_drawio()
    if not drawio:
        raise SystemExit("drawio not found -- run doctor.py; brew install --cask drawio")

    src = os.path.abspath(args.src)
    if not os.path.isfile(src):
        raise SystemExit(f"no such file: {src}")
    out_dir = os.path.abspath(args.out_dir) if args.out_dir else os.path.dirname(src)
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.basename(src)[:-7] if src.endswith(".drawio") else os.path.basename(src)

    ver = subprocess.run([drawio, "--version"], capture_output=True, text=True)
    print(f"drawio {ver.stdout.strip() or ver.stderr.strip() or '(unknown version)'}")

    pages = page_count(src)
    produced: list[str] = []
    if pages == 1:
        out = os.path.join(out_dir, f"{name}.svg")
        _run(drawio, [*SVG_OPTS, "-o", out, src])
        _stabilise_flow_ids(out)
        _append_newline(out)
        produced.append(out)
    else:
        for i in range(1, pages + 1):  # 1-based
            out = os.path.join(out_dir, f"{name}-{i}.svg")
            _run(drawio, [*SVG_OPTS, "--page-index", str(i), "-o", out, src])
            _stabilise_flow_ids(out)
            _append_newline(out)
            produced.append(out)

    if args.png:
        png_dir = os.path.abspath(args.png_dir) if args.png_dir else out_dir
        os.makedirs(png_dir, exist_ok=True)
        png = os.path.join(png_dir, f"{name}.png")
        _run(drawio, ["-x", "-f", "png", "--width", str(args.png_width), "-b", "10", "-o", png, src])
        produced.append(png)

    print(f"\nexported {len(produced)} file(s):")
    over = []
    budgets = {".svg": args.budget_kb * 1024, ".png": args.png_budget_kb * 1024}
    for f in produced:
        size = os.path.getsize(f)
        budget = budgets.get(os.path.splitext(f)[1])
        flag = ""
        if budget is not None and size > budget:
            flag = f"  OVER BUDGET ({budget // 1024} KB)"
            over.append(f)
        print(f"  {size / 1024:8.1f} KB  {os.path.relpath(f)}{flag}")

    if over:
        print(
            f"\n{len(over)} file(s) over budget -- reduce embedded raster logos or their "
            f"resolution, or lower --png-width.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
