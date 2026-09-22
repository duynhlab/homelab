#!/usr/bin/env python3
"""icon_style.py -- the icon library behind homelab-drawio diagrams.

Three jobs over one catalogue (assets/icons/manifest.json):

  style <name> --role <role>   emit a paste-ready label style with the logo
                               embedded and the semantic palette applied
  list                         show the catalogue: icons, aliases, and the
                               'none' decisions (products that stay plain)
  audit <dir>                  advisory -- list boxes that name a catalogued
                               product yet render without its logo, plus icons
                               sitting on a grouping frame (MISPLACED)

PNG, not SVG, throughout: headless Draw.io export does not render SVG data URIs.
The payload is joined with a comma (data:image/png,<b64>), never ';base64,' --
the semicolon terminates the mxCell style value and silently drops the image.
"""
from __future__ import annotations

import argparse
import base64
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

from _common import (
    ICONS,
    is_frame,
    load_manifest,
    load_preset,
    parent_ids,
    resolve_icon,
    role_dashed,
    role_style,
)


def cmd_style(args: argparse.Namespace) -> int:
    path, default_label = resolve_icon(args.name)
    rs = role_style(args.role)
    font = load_preset()["font"]
    with open(path, "rb") as fh:
        payload = base64.b64encode(fh.read()).decode()
    style = load_preset()["label_style"].format(
        payload=payload,
        dashed=role_dashed(args.role),
        fillColor=rs["fillColor"],
        strokeColor=rs["strokeColor"],
        fontColor=rs["fontColor"],
        fontFamily=font["fontFamily"],
        fontSize=font["fontSize"],
    )
    label = args.label or default_label
    print(f"# {label}  (role={args.role})")
    print(style)
    return 0


def cmd_list(_args: argparse.Namespace) -> int:
    m = load_manifest()
    print("icons (name -> file, label):")
    for name in sorted(m.get("icons", {})):
        e = m["icons"][name]
        print(f"  {name:20} {e['file']:24} {e.get('label', '')}")
    if m.get("aliases"):
        print("\naliases (name -> target):")
        for a in sorted(m["aliases"]):
            print(f"  {a:20} -> {m['aliases'][a]}")
    if m.get("none"):
        print("\nnone (deliberately plain -- do not re-add):")
        for n in sorted(m["none"]):
            print(f"  {n:20} {m['none'][n]}")
    if m.get("follow_up"):
        print("\nfollow_up (not yet in the catalogue; source to fetch from):")
        for n in sorted(m["follow_up"]):
            print(f"  {n:20} {m['follow_up'][n]}")
    return 0


def _catalog_terms() -> dict[str, str]:
    """name -> availability tier ('local' present, else follow_up source)."""
    m = load_manifest()
    terms: dict[str, str] = {}
    for name in m.get("icons", {}):
        terms[name.lower()] = "local"
    for name in m.get("follow_up", {}):
        terms[name.lower()] = "follow_up"
    return terms


def _first_line(value: str) -> str:
    """The box's first label line, lowercased.

    Split on the line breaks Draw.io actually writes (`<br>` and `&#10;`) BEFORE
    stripping tags -- stripping first collapses every line into one, which is
    what silently broke the "icon the box's subject, not its prose" rule: a
    product named on line 2 was matched as if it were the subject.
    """
    head = re.split(r"<br\s*/?>|&#10;|\n", value, maxsplit=1)[0]
    return re.sub(r"<[^>]+>", " ", head).strip().lower()


def cmd_audit(args: argparse.Namespace) -> int:
    terms = _catalog_terms()
    none_set = {n.lower() for n in load_manifest().get("none", {})}
    missing: dict[str, list[str]] = defaultdict(list)
    misplaced: list[str] = []

    # Recursive: a non-recursive glob made `audit docs/` report every diagram
    # clean while the diagrams sat one level down. A false clean is worse than
    # no check.
    paths = sorted(glob.glob(os.path.join(args.dir, "**", "*.drawio"), recursive=True))
    if not paths:
        print(f"audit: no .drawio files under {args.dir}", file=sys.stderr)
        return 1

    for path in paths:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        diagram = os.path.basename(path)[:-7]
        try:
            cells = list(ET.fromstring(text).iter("mxCell"))
        except ET.ParseError as exc:
            print(f"audit: {diagram}: unparseable ({exc})", file=sys.stderr)
            continue
        parents = parent_ids(cells)
        # A title, a caption and a legend row all NAME products without being one.
        # Auditing them turns the advisory into noise, so they are exempt the same
        # way validate_house.py exempts them.
        legend_ids = {
            c.get("id") for c in cells if "legend" in (c.get("value") or "").lower()
        }
        for c in cells:
            style = c.get("style") or ""
            first = _first_line(c.get("value") or "")
            has_icon = "image=data:image/png" in style
            if has_icon and is_frame(style, c.get("id"), parents):
                misplaced.append(f"{diagram}: icon on a grouping frame -- {first[:48]!r}")
                continue
            if has_icon or not first:
                continue
            if style.startswith("text;") or c.get("parent") in legend_ids:
                continue
            for term, tier in terms.items():
                if term in none_set:
                    continue
                if re.search(rf"\b{re.escape(term)}\b", first):
                    missing[tier].append(f"{diagram}: {first[:48]!r} -> {term}")
                    break

    print(f"audit: {len(paths)} diagram(s) under {args.dir}")
    if not missing and not misplaced:
        print("every box that names a catalogued product already carries its logo.")
        return 0

    for tier, how in (
        ("local", "icon_style.py style <name> --role <role>  (already in assets/icons/)"),
        ("follow_up", "fetch from the source in manifest.json 'follow_up', rasterise, add"),
    ):
        if missing.get(tier):
            print(f"\nMISSING [{tier}] -- {how}")
            for row in missing[tier]:
                print(f"  {row}")
    if misplaced:
        print("\nMISPLACED -- an icon on a grouping frame labels the grouping, not a thing.")
        for row in misplaced:
            print(f"  {row}")
    print("\nAdvisory, not a gate: whether a box wants a logo is a judgment call.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="homelab-drawio icon library")
    sub = p.add_subparsers(dest="cmd", required=True)

    ps = sub.add_parser("style", help="emit a paste-ready label style with the logo")
    ps.add_argument("name")
    ps.add_argument("--role", default="service", help="semantic palette role (default: service)")
    ps.add_argument("--label", default=None, help="override the box label")
    ps.set_defaults(func=cmd_style)

    pl = sub.add_parser("list", help="show the catalogue")
    pl.set_defaults(func=cmd_list)

    pa = sub.add_parser("audit", help="list product boxes rendering without a logo")
    pa.add_argument("dir", help="directory of .drawio sources")
    pa.set_defaults(func=cmd_audit)

    args = p.parse_args()
    try:
        return args.func(args)
    except KeyError as exc:
        print(str(exc).strip('"'), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
