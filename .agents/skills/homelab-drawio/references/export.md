# Homelab Draw.io export

`scripts/export.py` wraps the Draw.io CLI with the flags this repo needs so an
export is reproducible whoever runs it.

Paths are resolved from wherever you run it, so give them relative to the repo
root and run from the repo root:

```bash
python3 .agents/skills/homelab-drawio/scripts/export.py docs/architecture/topology.drawio
# SVG beside the source; add the PNG under img/ in the same run:
python3 .agents/skills/homelab-drawio/scripts/export.py docs/architecture/topology.drawio \
        --png --png-dir docs/architecture/img
```

`--png-dir` exists because the repo keeps the SVG beside its source and the PNG
under `img/`. `--out-dir` moves **both**, so using it alone for the PNG quietly
puts a second copy of the SVG in `img/` too.

## What it does, and why

- **SVG is the default format.** It scales, stays sharp when zoomed, and is a
  fraction of a PNG's size. Add `--png` only for a source GitHub renders inline
  (GitHub's Markdown sanitizer strips the `<foreignObject>` Draw.io puts labels
  in, so a Draw.io SVG in a `README.md` shows a diagram with no text — that one
  file needs a PNG too).
- **`--embed-svg-fonts false`.** Draw.io embeds the full font as base64 by
  default (often >1 MB). The house font is web-safe Helvetica, resolved locally,
  so embedding buys nothing and blows the size budget.
- **Size budgets: 500 KB per SVG, 400 KB per PNG.** Exit is non-zero over
  either — reduce embedded raster logos or their resolution, or lower
  `--png-width`. Logos are ~2–5 KB each at 64px, so the SVG is far under; the
  **PNG** is the one to watch, because it is what GitHub downloads on every view
  of the README that embeds it.
- **PNG width, not scale (`--png-width`, default 1536).** `-s 2` scales relative
  to the page, so a diagram that grows silently grows its PNG. An absolute width
  is a budget you can reason about: 1536 px is ~1.7× the 920 px the README
  displays — sharp on a retina screen, and the widest that keeps a
  full-platform diagram inside 400 KB.
- **`--page-index` is 1-based** in this CLI. A multi-page `.drawio` is looped
  `1..N` and written `<name>-<i>.svg`; a single-page file is `<name>.svg`.
  Exporting page `0` silently repeats page 1 — the loop starts at 1 for this
  reason.
- **Trailing newline.** Draw.io omits it, so `export.py` appends one.
- **Stable `flowAnimation` keyframe ids.** Draw.io mints a *random* CSS keyframe
  name per export (`ge-flow-animation-IwqhiStrplj6VKUFyiaf`), so a diagram with
  one animated edge produced a different SVG every single run — a permanent diff
  nobody could make go away. `export.py` renumbers them by order of appearance
  (`ge-flow-animation-1`, …), which keeps the animation working and makes the
  export byte-identical when nothing changed. Verify with two exports in a row
  and `md5`.
- **Version printed.** A re-export on a different Draw.io build can perturb the
  SVG in ways that read as diff noise; the printed version lets a reviewer trace
  it. Pin the build if you need byte-stable exports across machines.

## After any diagram change

Re-export, because the exports are committed alongside the source — a source
edit without a re-run ships a stale picture. Commit the `.drawio` and its
export(s) in the same change.
