# Homelab Draw.io icon catalog

Curated logos for the deployed platform, embedded as PNG data URIs. The catalog
is [`../assets/icons/manifest.json`](../assets/icons/manifest.json); every entry
records its source URL, license, byte size, and SHA-256. Emit a ready style with
`icon_style.py`; do not hand-roll a data URI.

## Resolve an icon before writing the box

Stop at the first hit:

| # | Source | How |
|---|---|---|
| 1 | the catalog (`assets/icons/`) | `python3 ../scripts/icon_style.py style <name> --role <role>` |
| 2 | CNCF Artwork (a CNCF project not yet catalogued) | **list** `projects/<slug>/icon/color/` (filenames are not slugs — ESO ships `eso-icon-color.svg`), fetch the colour SVG, `rsvg-convert -w 64 -h 64`, add it |
| 3 | simple-icons (brand, CC0) | `https://cdn.simpleicons.org/<slug>` → rasterise, add |
| 4 | project brand repo | fetch the official mark, rasterise, add |
| 5 | none | a clean plain box — the honest fallback, only after 1–4 miss |

Reaching step 5 is fine; skipping to it without trying 1–4 is the failure to
avoid. `icon_style.py audit <dir>` lists product boxes rendering without a logo,
grouped by which source would supply it — advisory, not a gate.

## In the catalog

`edge`/`platform`/`data`/observability roles below are the *typical* role for
that product; pass whatever `--role` the box actually plays.

Kubernetes, Flux, Helm, OpenTelemetry, cert-manager, Kyverno, KEDA,
CloudNativePG, External Secrets Operator (CNCF Artwork, colour); Grafana,
Keycloak, Go, PostgreSQL, ClickHouse, Temporal, Envoy, VictoriaMetrics, OpenBao
(simple-icons). Run `icon_style.py list` for the exact names and aliases.

**Aliases:** `victorialogs` and `victoriatraces` → the VictoriaMetrics mark (one
company, one logo); `postgres`→`postgresql`, `eso`→`external-secrets`,
`otel`→`opentelemetry`, `k8s`→`kubernetes`.

## Deliberately plain (`none` — do not re-add)

- **Valkey** — a Redis fork with no own mark; a Redis logo would assert Redis is
  deployed, which it is not. Draw a plain `data` cylinder.
- **Vector** — no mark at any source probed.
- **PgDog**, **Sloth** — no logo located.

## Rules that keep the catalog honest

- **Look at every icon at 24px before naming it.** Marks that differ on a
  contact sheet can collapse to the same glyph at render size. Compare:
  ```bash
  magick icons/<a>.png -resize 24x24 -background white -flatten -resize 400% /tmp/a.png
  magick icons/<b>.png -resize 24x24 -background white -flatten -resize 400% /tmp/b.png
  magick montage /tmp/a.png /tmp/b.png -tile 2x -geometry +8+8 /tmp/cmp.png
  ```
- **PNG, comma-joined.** `image=data:image/png,<base64>` — a comma, never
  `;base64,` (truncates the mxCell style and drops every property after it). An
  SVG data URI exports as an empty box under headless Draw.io.
- **Icon the box's subject, not its prose.** A box titled *Leaf certificates*
  whose second line says "cert-manager-issued" gets no cert-manager logo.
- **Never on a grouping frame.** A logo on a frame labels the grouping, not a
  thing, and floats over the border. `validate_house.py` errors on this.
- **Adding one:** rasterise to PNG at 64px, drop it in `assets/icons/`, then
  regenerate its `manifest.json` entry (file, bytes, sha256, label, source,
  license) and eyeball it at 24px. Record a genuine miss as `none` so the next
  pass does not repeat the search.
