# Architecture diagrams

Draw.io (`.drawio`) diagram sources for the platform, plus their committed
exports. Draw.io is the **exception** here — [Mermaid is the default](../../AGENTS.md)
for diagrams in this repo; these files exist for the large, logo-bearing views
that earn an editable vector source. Each is **generated top-down from a YAML
model** (`<name>.ir.yaml`, the IR) by the
[`homelab-drawio`](../../.agents/skills/homelab-drawio/SKILL.md) skill, so the
IR is what you edit and the `.drawio` is its output.

| Fact | Value |
|------|-------|
| Layout | one directory per domain: `<domain>/<name>.ir.yaml` (the model you edit) → `<domain>/<name>.drawio` (generated, still editable in Draw.io) + `<domain>/<name>.svg`, PNG under `<domain>/img/` |
| Exports | pages embed the **SVG**: GitHub renders it with its labels, and the diagram's primary flow moves (`diagram.animate`). The PNG under `img/` is the static fallback the caption links |
| Style | homelab house style — palette mirrors the Mermaid `classDef` in [AGENTS.md](../../AGENTS.md); the outermost frame is the cluster |
| Regenerate | `S=.agents/skills/homelab-drawio/scripts; python3 $S/generate.py docs/architecture/<domain>/<name>.ir.yaml && python3 $S/export.py docs/architecture/<domain>/<name>.drawio --png --png-dir docs/architecture/<domain>/img` |
| Validate | `python3 .agents/skills/homelab-drawio/scripts/validate.py docs/architecture/<domain>/<name>.drawio --ir docs/architecture/<domain>/<name>.ir.yaml` — 0 errors to ship |

## Sources

| Domain | Source | Answers | Published in |
|--------|--------|---------|--------------|
| api | [`api/platform-api`](api/platform-api.drawio) | **Platform API topology** — the SPAs' routes through the gateway, every documented gRPC method between services, the order worker's activities and the payment ↔ mockpay loop. | [`api/api.md` § Platform API Topology](../api/api.md#platform-api-topology) |
| secrets | [`secrets/pipeline`](secrets/pipeline.drawio) | **Secrets, TLS and trust pipeline** — OpenBao (floci auto-unseal, bootstrap Job) → ESO → Kubernetes Secrets → consumers; notification rotation; edge certificate and CA bundle. | [`secrets/README.md` § Platform pipeline](../secrets/README.md#platform-pipeline) |
| platform | [`platform/topology`](platform/topology.drawio) | **Request path** — how a request travels once the platform is up: edge → apps → data, with the observability and secrets planes. | [`README.md` § Topology](../../README.md#topology) |
| observability | [`observability/signal-flow`](observability/signal-flow.drawio) | **Signal flow + retention** — which OTel Collector pipeline carries each signal, which backend stores it and for how long, and the paths that bypass the collector. | [`observability/README.md` § Architecture](../observability/README.md#architecture) |
| observability | [`observability/delivery`](observability/delivery.drawio) | **Delivery order** — how Flux delivers the observability stack and what releases each wave. | [`observability/README.md` § Deployment](../observability/README.md#deployment) |
| observability | [`observability/clickhouse-engine`](observability/clickhouse-engine.drawio) | **Inside one ClickHouse replica** — the engine layers (access, query processing, storage, orthogonal components) of one replica, its disks and RustFS cold tier, and the peer replicas and Keeper it replicates through. | [ClickHouse internals ch. 01 § Inside one replica](../observability/clickhouse/internals/01-architecture.md#inside-one-replica--the-engines-layers) |
| databases | [`databases/topology`](databases/topology.drawio) | **Connection and recovery paths** — which pooler or direct host each client uses, who manages the clusters, and how WAL and backups reach the DR replica. | [`databases/architecture.md` § Current topology](../databases/architecture.md#current-topology) |
| security | [`security/app-mesh`](security/app-mesh.drawio) | **Allowed app-mesh ingress** — which namespace may call which service over :8080 / :9090, caller → callee; the gateway's ten allows drawn as one arrow into the fenced frame. | [`security/network-policies.md` § 3](../security/network-policies.md#3-allowed-ingress-topology) |
| security | [`security/network-policies`](security/network-policies.drawio) | **Who may reach the data and identity tier** — NetworkPolicy allows by source namespace and port. | [`security/network-policies.md` § DB-tier allows](../security/network-policies.md#db-tier-allows) |
| workflows | [`workflows/temporal-keda`](workflows/temporal-keda.drawio) | **The Temporal work layer** — who starts each workflow, which queue and worker serve it, and how the Worker Controller and KEDA roll out and scale each build. | [`api/workflows.md`](../api/workflows.md) |

## Conventions

- **One question per file**, kebab-case name. Pick the question from
  [`references/diagram-types.md`](../../.agents/skills/homelab-drawio/references/diagram-types.md),
  which also carries the pre-export review checklist.
- **Accurate to deployed reality**; anything not deployed is drawn dashed and
  labelled `planned`.
- **Logos** come from the skill's curated catalog
  ([`assets/icons/manifest.json`](../../.agents/skills/homelab-drawio/assets/icons/manifest.json));
  a box gets a logo only for the product it is.
- **Edit the IR, never the generated `.drawio`.** `validate.py --ir` fails a
  file that no longer matches its IR, and the skill's tests check every IR in the
  repo against its committed `.drawio`.
- **Commit the IR, the `.drawio` and its exports together** — a source edit
  without a regenerate and re-export ships a stale picture.
- **Frames own their children** (`container=1`): moving a domain frame moves the
  boxes inside it, and it is what makes the "no logo on a grouping frame" check
  able to fire at all.
- Validate before exporting (the table above), then **open the render and
  look**, which is where a crowded corner or an ambiguous crossing is caught.

_Last updated: 2026-09-30 — `observability/clickhouse-engine` added (ClickHouse internals chapter 01). Earlier: 2026-09-28 — `api/platform-api` and `secrets/pipeline` added. Earlier the same day: `security/app-mesh` added (NetworkPolicy § 3). Earlier the same day: pages embed the SVG, whose primary flow moves (`diagram.animate`); the PNG is the linked fallback. Earlier the same day: split by domain (`platform/`, `observability/`, `databases/`, `security/`, `workflows/`) with three new sources: database paths, NetworkPolicy allows into the data tier, and the Temporal + KEDA work layer. Earlier the same day: every source now sits in a `Kind cluster · homelab` frame (only the browser stays outside); all three sources redrawn top-down from YAML IRs (`*.ir.yaml`) by the skill's generator, with routed edges and placed labels; PNGs quantized to 256 colours. Earlier the same day: `observability-signal-flow.drawio` added and the v2 soft-tint palette applied._
