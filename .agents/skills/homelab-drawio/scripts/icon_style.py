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
from collections import defaultdict

from _common import ICONS, load_manifest, load_preset, resolve_icon, role_style


def cmd_style(args: argparse.Namespace) -> int:
    path, default_label = resolve_icon(args.name)
    rs = role_style(args.role)
    font = load_preset()["font"]
    with open(path, "rb") as fh:
        payload = base64.b64encode(fh.read()).decode()
    style = load_preset()["label_style"].format(
        payload=payload,
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


def cmd_audit(args: argparse.Namespace) -> int:
    terms = _catalog_terms()
    none_set = {n.lower() for n in load_manifest().get("none", {})}
    missing: dict[str, list[str]] = defaultdict(list)
    misplaced: list[str] = []

    for path in sorted(glob.glob(os.path.join(args.dir, "*.drawio"))):
        doc = open(path, encoding="utf-8").read()
        diagram = os.path.basename(path)[:-7]
        for m in re.finditer(r'<mxCell\b[^>]*\bvalue="([^"]*)"[^>]*\bstyle="([^"]*)"[^>]*>', doc):
            value, style = m.group(1), m.group(2)
            first = re.sub(r"<[^>]+>", " ", value).strip().split("\n")[0].lower()
            has_icon = "image=data:image/png" in style
            is_container = "container=1" in style or "shape=label" not in style and "swimlane" in style
            if has_icon and is_container:
                misplaced.append(f"{diagram}: icon on a grouping frame -- {first[:48]!r}")
                continue
            if has_icon or not first:
                continue
            for term, tier in terms.items():
                if term in none_set:
                    continue
                if re.search(rf"\b{re.escape(term)}\b", first):
                    missing[tier].append(f"{diagram}: {first[:48]!r} -> {term}")
                    break

    if not missing and not misplaced:
        print("audit: every box that names a catalogued product already carries its logo.")
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
