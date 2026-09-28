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
import subprocess
import sys
from functools import lru_cache

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(SKILL_DIR, "assets")
ICONS = os.path.join(ASSETS, "icons")
PRESET = os.path.join(ASSETS, "homelab.json")
MANIFEST = os.path.join(ICONS, "manifest.json")
SCHEMA = os.path.join(SKILL_DIR, "schema", "diagram-ir.schema.json")

# Helvetica advance widths per 1000 em (the Adobe core-14 metrics; Nimbus Sans
# and Liberation Sans share them, which is why the house font needs no per-OS
# variant). Used to size a generated box and to flag text that overflows one.
_HELV = {
    " ": 278, "!": 278, '"': 355, "#": 556, "$": 556, "%": 889, "&": 667, "'": 191,
    "(": 333, ")": 333, "*": 389, "+": 584, ",": 278, "-": 333, ".": 278, "/": 278,
    ":": 278, ";": 278, "<": 584, "=": 584, ">": 584, "?": 556, "@": 1015, "[": 278,
    "\\": 278, "]": 278, "^": 469, "_": 556, "`": 333, "{": 334, "|": 260, "}": 334,
    "~": 584, "·": 278, "—": 1000, "–": 556, "→": 1000, "×": 584,
    "A": 667, "B": 667, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778, "H": 722,
    "I": 278, "J": 500, "K": 667, "L": 556, "M": 833, "N": 722, "O": 778, "P": 667,
    "Q": 778, "R": 722, "S": 667, "T": 611, "U": 722, "V": 667, "W": 944, "X": 667,
    "Y": 667, "Z": 611,
    "a": 556, "b": 556, "c": 500, "d": 556, "e": 556, "f": 278, "g": 556, "h": 556,
    "i": 222, "j": 222, "k": 500, "l": 222, "m": 833, "n": 556, "o": 556, "p": 556,
    "q": 556, "r": 333, "s": 500, "t": 278, "u": 556, "v": 500, "w": 722, "x": 500,
    "y": 500, "z": 500,
}


def text_width(line: str, size: float, bold: bool = False) -> float:
    """Rendered width in px of one line of Helvetica at `size` px."""
    em = sum(_HELV.get(ch, 556) for ch in line) / 1000.0
    return em * size * (1.05 if bold else 1.0)

# Candidate locations for the Draw.io desktop CLI, in priority order: PATH
# first (the .deb, Homebrew and snap all put a `drawio` there), then the usual
# install directories on Linux and macOS for a shell whose PATH lacks them.
DRAWIO_CANDIDATES = (
    "drawio",
    "draw.io",
    "/opt/drawio/drawio",                                  # Linux .deb / .rpm
    "/snap/bin/drawio",                                    # Linux snap
    "/Applications/draw.io.app/Contents/MacOS/draw.io",    # macOS app bundle
    "/opt/homebrew/bin/drawio",                            # macOS Homebrew (arm64)
    "/usr/local/bin/drawio",                               # macOS Homebrew (x86_64) / manual
)

IS_MAC = sys.platform == "darwin"

# Install hints per platform, so a MISS line tells the reader something they
# can actually run on the machine in front of them.
INSTALL_HINTS = {
    "drawio": ("brew install --cask drawio" if IS_MAC else
               "download the .deb from github.com/jgraph/drawio-desktop/releases and "
               "`sudo apt install ./drawio-amd64-*.deb` (or `sudo snap install drawio`)"),
    "rsvg-convert": "brew install librsvg" if IS_MAC else "sudo apt install librsvg2-bin",
    "imagemagick": "brew install imagemagick" if IS_MAC else "sudo apt install imagemagick",
    "xvfb-run": "" if IS_MAC else "sudo apt install xvfb",
    "graphviz": "brew install graphviz" if IS_MAC else "sudo apt install graphviz",
}


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


def drawio_command(drawio: str) -> list[str]:
    """The argv prefix that runs the Draw.io CLI on this machine.

    Draw.io Desktop is Electron. On macOS and on a Linux desktop session it runs
    as-is. Two Linux cases need help, and both fail with an opaque Electron error
    rather than a useful one:
      - no display server (CI, ssh, a container): Electron cannot start at all,
        so wrap it in `xvfb-run -a` when that is installed;
      - running as root: Chromium refuses to start without `--no-sandbox`.
    """
    cmd = [drawio]
    if IS_MAC:
        return cmd
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        xvfb = shutil.which("xvfb-run")
        if xvfb:
            cmd = [xvfb, "-a", drawio]
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        cmd.append("--no-sandbox")
    return cmd


def font_fallback(family: str = "Helvetica") -> str | None:
    """What fontconfig actually renders `family` with, or None without fc-match.

    The house font is Helvetica. macOS ships it; Linux does not and substitutes a
    metric-compatible clone (Nimbus Sans, from the urw-base35 fonts), so labels
    keep their width and nothing in a diagram needs a per-OS font. Anything else
    (DejaVu Sans is the usual culprit) is wider and can overflow a box.
    """
    fc = shutil.which("fc-match")
    if not fc:
        return None
    out = subprocess.run([fc, "-f", "%{family}", family], capture_output=True, text=True)
    return out.stdout.strip() or None
