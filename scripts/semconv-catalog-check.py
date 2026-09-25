#!/usr/bin/env python3
"""Fail when the event catalog in docs/api/logs.md disagrees with the registry.

The registry (duynhlab/pkg semconv/) generates semconv/docs/event-catalog.md;
`make semconv-catalog-refresh` vendors that file here at a pinned pkg commit.
logs.md keeps the richer hand-written table (enum values, links); this check
holds the two to the same names, classes, attribute sets and owners so prose and
registry cannot drift apart (ADR-076).
"""
import re
import sys

LOGS = "docs/api/logs.md"
GENERATED = "docs/api/event-catalog.generated.md"


def rows(path, heading=None):
    """Yield the cells of every table row after `heading` (or the whole file)."""
    text = open(path, encoding="utf-8").read()
    if heading:
        text = text.split(heading, 1)[1]
        text = text.split("\n## ", 1)[0]
    for line in text.splitlines():
        if not line.startswith("|") or line.startswith("|--") or line.startswith("| Class"):
            continue
        # `\|` separates enum values inside a cell; it is not a column break.
        cells = [c.strip() for c in line.replace("\\|", "\x00").split("|")[1:-1]]
        yield [c.replace("\x00", "|") for c in cells]


def attrs(cell):
    """Attribute names: the backticked token that opens the cell or follows ', '.
    Enum values follow ': ' or '| ' and are skipped."""
    return frozenset(m.group(1) for m in re.finditer(r"(?:^|, )`([^`]+)`", cell))


def owner(cell):
    cell = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", cell)
    return cell.replace("`", "").strip()


def catalog(path, heading):
    out, last_class = {}, ""
    for cells in rows(path, heading):
        if len(cells) != 5:
            continue
        last_class = cells[0] or last_class
        out[cells[1].strip("`")] = (last_class, attrs(cells[3]), owner(cells[4]))
    return out


def main():
    docs = catalog(LOGS, "## Event catalog")
    gen = catalog(GENERATED, None)
    problems = []
    for name in sorted(set(docs) | set(gen)):
        if name not in gen:
            problems.append(f"{name}: in logs.md but not in the registry")
        elif name not in docs:
            problems.append(f"{name}: in the registry but not in logs.md")
        else:
            for label, a, b in zip(("class", "attributes", "owner"), docs[name], gen[name]):
                if a != b:
                    problems.append(f"{name}: {label} differs — logs.md {sorted(a) if isinstance(a, frozenset) else a!r}"
                                    f" vs registry {sorted(b) if isinstance(b, frozenset) else b!r}")
    if problems:
        print("semconv-catalog-check FAIL:")
        print("\n".join("  " + p for p in problems))
        return 1
    print(f"semconv-catalog-check OK: {len(gen)} events agree with the registry")
    return 0


if __name__ == "__main__":
    sys.exit(main())
