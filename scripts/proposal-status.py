#!/usr/bin/env python3
"""Inventory proposal metadata and detect index drift without changing records."""

import argparse
import json
import re
from pathlib import Path


def cells(line):
    return [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def plain(value):
    return value.replace("**", "").replace("`", "").strip()


def state(value):
    match = re.match(r"[A-Za-z]+(?:\s+started)?", plain(value))
    word = match.group().lower() if match else "unknown"
    return {"implementable": "accepted"}.get(word, word)


def metadata(text):
    """Read the opening metadata table in both historical and current formats."""
    lines = text.split("\n## ", 1)[0].splitlines()
    result = {}
    for i, line in enumerate(lines):
        if not line.startswith("|"):
            continue
        row = cells(line)
        key = plain(row[0]).lower()
        if key not in ("status", "adoption", "implementation tracking"):
            continue
        if i + 2 < len(lines) and re.match(r"^\|[\s:|-]+$", lines[i + 1]):
            result.update(zip((plain(x).lower() for x in row), cells(lines[i + 2])))
        elif len(row) >= 2:
            result[key] = row[1]
    return result


def inventory(root):
    records, problems = [], []
    for kind, pattern in (("adr", r"ADR-\d{3}"), ("rfc", r"RFC-\d{4}")):
        directory = root / "docs/proposals" / kind
        index = {}
        for line in (directory / "README.md").read_text().splitlines():
            match = re.match(r"\| \[(" + pattern + r")\]", line)
            if match:
                index[match.group(1)] = cells(line)
        seen = set()
        for folder in sorted(directory.glob(kind.upper() + "-*")):
            if not folder.is_dir() or folder.name.startswith(kind.upper() + "-0000"):
                continue
            record_id = re.match(pattern, folder.name).group()
            seen.add(record_id)
            path = folder / "README.md"
            research_only = not path.exists()
            if research_only:
                path = folder / "research.md"
            text = path.read_text()
            data = metadata(text)
            row = index.get(record_id)
            if row is None:
                problems.append(f"{record_id}: missing index entry")
            index_status = row[2 if kind == "adr" else 4] if row else "unknown"
            current = data.get("status", "researching" if research_only else "unknown")
            if state(current) != state(index_status):
                problems.append(f"{record_id}: status {state(current)}; index {state(index_status)}")
            adoption = data.get("adoption", row[3] if row and kind == "adr" else "")
            if kind == "adr" and "adoption" in data and row:
                # Superseded/withdrawn rows can summarize disposition instead of adoption.
                if state(current) not in ("superseded", "withdrawn", "deprecated"):
                    if state(adoption) != state(row[3]):
                        problems.append(f"{record_id}: adoption {state(adoption)}; index {state(row[3])}")
            records.append({
                "id": record_id, "path": str(path.relative_to(root)),
                "title": text.splitlines()[0].lstrip("# "),
                "status": plain(current), "adoption": plain(adoption),
                "adoption_source": "record" if "adoption" in data else "legacy index" if kind == "adr" else "n/a",
                "tracking": data.get("implementation tracking", ""),
            })
        for record_id in sorted(index.keys() - seen):
            if record_id not in ("ADR-000", "RFC-0000"):
                problems.append(f"{record_id}: index points to a missing record")
    return records, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print inventory and discrepancies as JSON")
    args = parser.parse_args()
    records, problems = inventory(Path(__file__).resolve().parents[1])
    if args.json:
        print(json.dumps({"records": records, "discrepancies": problems}, indent=2))
    else:
        print(f"{len(records)} records; {len(problems)} index discrepancies")
        for problem in problems:
            print(problem)
    return bool(problems)


if __name__ == "__main__":
    raise SystemExit(main())
