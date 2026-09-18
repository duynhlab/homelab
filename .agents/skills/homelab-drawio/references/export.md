# Homelab Draw.io export

`scripts/export.py` wraps the Draw.io CLI with the flags this repo needs so an
export is reproducible whoever runs it.

```bash
python3 scripts/export.py docs/architecture/platform-overview.drawio          # SVG
python3 scripts/export.py docs/architecture/platform-overview.drawio --png    # SVG + PNG
python3 scripts/export.py <file> --out-dir docs/architecture/img --budget-kb 500
```

## What it does, and why

- **SVG is the default format.** It scales, stays sharp when zoomed, and is a
  fraction of a PNG's size. Add `--png` only for a source GitHub renders inline
  (GitHub's Markdown sanitizer strips the `<foreignObject>` Draw.io puts labels
  in, so a Draw.io SVG in a `README.md` shows a diagram with no text — that one
  file needs a PNG too).
- **`--embed-svg-fonts false`.** Draw.io embeds the full font as base64 by
  default (often >1 MB). The house font is web-safe Helvetica, resolved locally,
  so embedding buys nothing and blows the size budget.
- **Size budget (default 500 KB per SVG).** Exit is non-zero over budget —
  reduce embedded raster logos or their resolution. Logos are ~2–5 KB each at
  64px, so a normal diagram is far under.
- **`--page-index` is 1-based** in this CLI. A multi-page `.drawio` is looped
  `1..N` and written `<name>-<i>.svg`; a single-page file is `<name>.svg`.
  Exporting page `0` silently repeats page 1 — the loop starts at 1 for this
  reason.
- **Trailing newline.** Draw.io omits it; pre-commit's end-of-file-fixer would
  add one and leave the tree dirty by one byte per file, so `export.py` appends
  it, making the export idempotent.
- **Version printed.** A re-export on a different Draw.io build can perturb the
  SVG in ways that read as diff noise; the printed version lets a reviewer trace
  it. Pin the build if you need byte-stable exports across machines.

## After any diagram change

Re-export, because the exports are committed alongside the source — a source
edit without a re-run ships a stale picture. Commit the `.drawio` and its
export(s) in the same change.
