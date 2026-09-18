"""Shared helpers for the homelab-drawio skill scripts.

Single source of truth for: where the style preset and icon catalog live, how to
resolve the Draw.io binary, and how the semantic palette maps a role to its
fill/stroke/font. The palette itself lives in assets/homelab.json, which mirrors
the Mermaid classDef in AGENTS.md -- edit them together.
"""
from __future__ import annotations

import json
import os
import shutil
from functools import lru_cache

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(SKILL_DIR, "assets")
ICONS = os.path.join(ASSETS, "icons")
PRESET = os.path.join(ASSETS, "homelab.json")
MANIFEST = os.path.join(ICONS, "manifest.json")

# Candidate locations for the Draw.io desktop CLI, in priority order.
DRAWIO_CANDIDATES = (
    "drawio",
    "draw.io",
    "/Applications/draw.io.app/Contents/MacOS/draw.io",
    "/opt/homebrew/bin/drawio",
    "/usr/local/bin/drawio",
)


@lru_cache(maxsize=1)
def load_preset() -> dict:
    with open(PRESET, encoding="utf-8") as fh:
        return json.load(fh)


@lru_cache(maxsize=1)
def load_manifest() -> dict:
    with open(MANIFEST, encoding="utf-8") as fh:
        return json.load(fh)


def role_style(role: str) -> dict:
    """Return the fill/stroke/font dict for a semantic role, or raise."""
    roles = load_preset()["roles"]
    if role not in roles:
        known = ", ".join(sorted(roles))
        raise KeyError(f"unknown role '{role}'. Known roles: {known}")
    return roles[role]


def role_dashed(role: str) -> str:
    """'dashed=1;' when the role is drawn dashed (planned), else ''.

    The palette marks `planned` dashed in assets/homelab.json; emitting it here
    is what keeps "planned = dashed + the word planned" true for every style the
    scripts hand out, rather than only for the ones an author remembers.
    """
    return "dashed=1;" if role_style(role).get("dashed") else ""


def parent_ids(cells) -> set:
    """Ids that some other cell names as its `parent` -- i.e. cells owning children."""
    return {c.get("parent") for c in cells if c.get("parent")}


def is_frame(style: str, cell_id, parents: set) -> bool:
    """True when a cell is a grouping frame rather than a thing.

    Structural first: a cell that owns children IS a frame, whatever its style.
    That matters because the house `shapes.container` is a styled rectangle --
    keying only on `container=1`/`swimlane` made this check unfireable. The
    declared forms are still honoured for hand-authored cells, and the two
    unstyled layer cells (`0`, `1`) are excluded: they parent everything but are
    not drawn.
    """
    if not style:
        return False
    if "container=1" in style or "swimlane" in style or style.startswith("group;"):
        return True
    return bool(cell_id) and cell_id in parents


def resolve_icon(name: str) -> tuple[str, str]:
    """Map a catalogue name (following aliases) to (png_path, label)."""
    m = load_manifest()
    name = m.get("aliases", {}).get(name, name)
    entry = m.get("icons", {}).get(name)
    if not entry:
        known = ", ".join(sorted(list(m.get("icons", {})) + list(m.get("aliases", {}))))
        raise KeyError(f"unknown icon '{name}'. Available: {known}")
    return os.path.join(ICONS, entry["file"]), entry.get("label", name)


def find_drawio() -> str | None:
    """Locate the Draw.io CLI binary, or None if not installed."""
    for cand in DRAWIO_CANDIDATES:
        if os.path.sep in cand:
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                return cand
        else:
            found = shutil.which(cand)
            if found:
                return found
    return None
