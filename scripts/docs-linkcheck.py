#!/usr/bin/env python3
"""Check relative Markdown links and #anchors in the given files.

Called by scripts/docs-check.sh. Prints one line per finding as
`<file>:<line> link <message>` and exits 1 when any link is broken.
Anchors follow the GitHub slug rules: lower-case, punctuation dropped, spaces
to hyphens. A link to a directory resolves to its README.md.
"""
import re
import sys
import unicodedata
from pathlib import Path

LINK = re.compile(r"\]\(([^)\s]+)\)")
HEADING = re.compile(r"^#{1,6} (.+)$")
_anchor_cache: dict[Path, set[str]] = {}


def slug(heading: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip())
    text = re.sub(r"[`*_]", "", text).lower()
    kept = [c for c in text if c.isalnum() or c in " -" or unicodedata.category(c).startswith("L")]
    return "".join(kept).replace(" ", "-")


def anchors(path: Path) -> set[str]:
    if path not in _anchor_cache:
        found: set[str] = set()
        in_fence = False
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            m = HEADING.match(line)
            if m:
                found.add(slug(m.group(1)))
        _anchor_cache[path] = found
    return _anchor_cache[path]


def check(file: str) -> int:
    path = Path(file)
    broken = 0
    in_fence = False
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for m in LINK.finditer(line):
            target = m.group(1)
            if target.startswith(("http://", "https://", "mailto:", "<")) or "{" in target:
                continue  # external, or a template placeholder such as {link}
            rel, _, anchor = target.partition("#")
            dest = (path.parent / rel).resolve() if rel else path.resolve()
            if not dest.exists():
                print(f"{file}:{lineno} link target missing: {target}")
                broken += 1
                continue
            if not anchor:
                continue
            page = dest / "README.md" if dest.is_dir() else dest
            if page.suffix != ".md" or not page.exists():
                continue
            if anchor not in anchors(page):
                print(f"{file}:{lineno} link anchor missing: {target}")
                broken += 1
    return broken


def main(files: list[str]) -> int:
    total = sum(check(f) for f in files if f.endswith(".md") and Path(f).is_file())
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
