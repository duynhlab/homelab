#!/usr/bin/env python3
"""export.py -- reproducible SVG/PNG export for a homelab .drawio source.

Wraps the Draw.io CLI with the flags this repo needs, so an export is the same
whoever runs it:

  * --embed-svg-fonts false  -- Draw.io embeds the full font as base64 by
    default (>1 MB); the house font is web-safe Helvetica, so nothing is lost
  * -b 10 border, and a per-SVG size budget (default 500 KB)
  * --page-index is 1-BASED in this CLI: a multi-page file is looped 1..N, and
    exporting 0 silently repeats page 1
  * a trailing newline is appended to each SVG (Draw.io omits it; pre-commit
    end-of-file-fixer would otherwise dirty the tree by one byte)

Prints the Draw.io version so a diff that looks like noise can be traced to a
different build. SVG is the default; add --png for the one raster GitHub needs.

Usage: export.py <src.drawio> [--out-dir DIR] [--png] [--budget-kb 500]
"""
from __future__ import annotations

import argparse
import os
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
    p.add_argument("--png", action="store_true", help="also export page 1 to PNG (-s 2)")
    p.add_argument("--budget-kb", type=int, default=500, help="per-SVG size budget in KB (default 500)")
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
        _append_newline(out)
        produced.append(out)
    else:
        for i in range(1, pages + 1):  # 1-based
            out = os.path.join(out_dir, f"{name}-{i}.svg")
            _run(drawio, [*SVG_OPTS, "--page-index", str(i), "-o", out, src])
            _append_newline(out)
            produced.append(out)

    if args.png:
        png = os.path.join(out_dir, f"{name}.png")
        _run(drawio, ["-x", "-f", "png", "-s", "2", "-b", "10", "-o", png, src])
        produced.append(png)

    print(f"\nexported {len(produced)} file(s) to {out_dir}:")
    over = []
    budget = args.budget_kb * 1024
    for f in produced:
        kb = os.path.getsize(f) / 1024
        flag = ""
        if f.endswith(".svg") and os.path.getsize(f) > budget:
            flag = "  OVER BUDGET"
            over.append(f)
        print(f"  {kb:8.1f} KB  {os.path.basename(f)}{flag}")

    if over:
        print(f"\n{len(over)} SVG(s) over the {args.budget_kb} KB budget -- reduce embedded raster logos or their resolution.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
