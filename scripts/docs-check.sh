#!/usr/bin/env bash
# Check the Markdown pages a change touches before it is called done.
#
#   scripts/docs-check.sh [--no-mermaid] [file ...]
#
# With no files, checks the Markdown files changed against origin/main.
# Rules, one finding line each (<file>:<line> <rule> <message>):
#   link     relative link or #anchor does not resolve (scripts/docs-linkcheck.py)
#   fence    a fenced block has no language tag
#   mermaid  a mermaid block does not render with mmdc (skipped with --no-mermaid
#            or when mmdc is absent; CI passes --no-mermaid)
#   secret   a literal token or key pattern is in the page (the documented demo
#            login in AGENTS.md is a fixture, not a secret, and is not matched)
#   inbound  a new page under docs/ has no link from docs/README.md or its area README
# CHANGELOG.md is skipped: released sections are append-only history whose
# links pointed at files that existed at release time. Template files
# (docs/_templates/, *_template*.md) are checked, but their {placeholder}
# links are ignored and they need no inbound link.
# Exits 1 when any rule finds something. BSD and GNU tools both work here.
set -euo pipefail

cd "$(dirname "$0")/.."

mermaid=1
files=()
for arg in "$@"; do
  case "$arg" in
    --no-mermaid) mermaid=0 ;;
    *) files+=("$arg") ;;
  esac
done

if [ ${#files[@]} -eq 0 ]; then
  base=$(git merge-base HEAD origin/main 2>/dev/null || echo origin/main)
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(
    { git diff --name-only --diff-filter=AM "$base" -- '*.md'
      git ls-files --others --exclude-standard -- '*.md'; } | sort -u
  )
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "docs-check: no Markdown files to check"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
findings="$tmp/findings"
: > "$findings"

if command -v mmdc >/dev/null 2>&1; then have_mmdc=1; else have_mmdc=0; fi

# 1. links and anchors
link_files=()
for f in "${files[@]}"; do [ "$f" != "CHANGELOG.md" ] && link_files+=("$f"); done
[ ${#link_files[@]} -gt 0 ] && { python3 -I scripts/docs-linkcheck.py "${link_files[@]}" >> "$findings" || true; }

checked=()
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  [ "$f" = "CHANGELOG.md" ] && continue
  checked+=("$f")

  # 2. fence language tags; extract mermaid blocks for 3.
  awk -v file="$f" -v tmp="$tmp" '
    /^[[:space:]]*```/ {
      if (!open) {
        open = 1; start = NR
        lang = $0; sub(/^[[:space:]]*```/, "", lang); sub(/[[:space:]].*$/, "", lang)
        if (lang == "") print file ":" NR " fence no language tag"
        out = (lang == "mermaid") ? tmp "/" (++n) ".mmd" : ""
        if (out != "") { printf "" > out; print "MERMAID " start " " out }
        next
      }
      open = 0; if (out != "") close(out); out = ""
      next
    }
    open && out != "" { print >> out }
  ' "$f" > "$tmp/awk.out"

  while IFS= read -r line; do
    case "$line" in
      MERMAID*)
        [ "$mermaid" -eq 1 ] && [ "$have_mmdc" -eq 1 ] || continue
        set -- $line
        if ! mmdc -q -i "$3" -o "$3.svg" >/dev/null 2>"$3.err"; then
          echo "$f:$2 mermaid does not render: $(grep -m1 -v '^$' "$3.err" || true)" >> "$findings"
        fi
        ;;
      ?*) echo "$line" >> "$findings" ;;
    esac
  done < "$tmp/awk.out"

  # 4. secret patterns
  grep -nE 'Bearer ey[A-Za-z0-9]|-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}' "$f" 2>/dev/null \
    | while IFS= read -r hit; do echo "$f:${hit%%:*} secret literal token or key pattern" >> "$findings"; done || true

  # 5. inbound links for a new page under docs/
  case "$f" in
    docs/_templates/*|*_template*.md|*_TEMPLATE.md) ;;
    docs/*.md)
      git cat-file -e "origin/main:$f" 2>/dev/null && continue
      grep -qF "${f#docs/}" docs/README.md || echo "$f:1 inbound no link from docs/README.md" >> "$findings"
      area=$(dirname "$f")
      while [ "$area" != "docs" ] && [ "$area" != "." ]; do
        if [ -f "$area/README.md" ] && [ "$area/README.md" != "$f" ]; then
          grep -qF "$(basename "$f")" "$area/README.md" \
            || echo "$f:1 inbound no link from $area/README.md" >> "$findings"
          break
        fi
        area=$(dirname "$area")
      done
      ;;
  esac
done

sort -u "$findings" > "$findings.sorted"
count=$(grep -c . "$findings.sorted" || true)
cat "$findings.sorted"
[ "$mermaid" -eq 1 ] && [ "$have_mmdc" -eq 0 ] && echo "docs-check: mmdc not found, mermaid render skipped"
echo "docs-check: ${#checked[@]} file(s), $count finding(s)"
[ "$count" -eq 0 ]
