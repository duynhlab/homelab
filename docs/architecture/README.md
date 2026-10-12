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
| security | [`security/tls-topology`](security/tls-topology.drawio) | **TLS topology** — which hops carry TLS today, who issues their certificates, and whether each is verified (`TLS verified` / `TLS unverified` / `PLAINTEXT` / `planned`), with the RFC-0020 slices drawn as planned. | [`secrets/cert-manager.md` § 12](../secrets/cert-manager.md#12-tls-topology--which-hops-are-encrypted-today) |
| workflows | [`workflows/temporal-keda`](workflows/temporal-keda.drawio) | **The Temporal work layer** — who starts each workflow, which queue and worker serve it, and which controllers own each worker's builds and replicas. | [`api/workflows.md`](../api/workflows.md) |
| workflows | [`workflows/temporal-worker-versions`](workflows/temporal-worker-versions.drawio) | **One worker release** — the builds, the Progressive rollout and the per-build KEDA scaling while order-fulfillment ramps from build A to build B. | [`api/workflows.md`](../api/workflows.md) · [`api/temporal.md` § Worker Deployment Versioning](../api/temporal.md#worker-deployment-versioning-as-built) |

## RFC-0011 previews

These views illustrate the provisional [mini-PC migration proposal](../proposals/rfc/RFC-0011/)
and [ADR-087](../proposals/adr/ADR-087-homelab-private-and-web-access/). They are
**proposed, not approved, and not deployed**. They do not replace the RFC's Mermaid views.

| View | Source | Preview | Question |
|------|--------|---------|----------|
| Physical infrastructure | [Draw.io](platform/rfc0011-infrastructure.drawio) · [IR](platform/rfc0011-infrastructure.ir.yaml) | [SVG](platform/rfc0011-infrastructure.svg) · [PNG](platform/img/rfc0011-infrastructure.png) | Which physical hosts and network links are being considered? |
| Layered homelab stack | [Draw.io](platform/rfc0011-platform-stack.drawio) · [IR](platform/rfc0011-platform-stack.ir.yaml) | [SVG](platform/rfc0011-platform-stack.svg) · [PNG](platform/img/rfc0011-platform-stack.png) | What runs above hardware, OS and Kubernetes? |
| Private and web access | [Draw.io](platform/rfc0011-access.drawio) · [IR](platform/rfc0011-access.ir.yaml) | [SVG](platform/rfc0011-access.svg) · [PNG](platform/img/rfc0011-access.png) | Which boundary admits administration, web access and LAN recovery? |
| Network / OSI layers | [Draw.io](platform/rfc0011-network-osi.drawio) · [IR](platform/rfc0011-network-osi.ir.yaml) | [SVG](platform/rfc0011-network-osi.svg) · [PNG](platform/img/rfc0011-network-osi.png) | Which networking functions belong to OSI L1–L7? |

The stack reads **bottom to top**: hardware → operating system → cluster
foundation → platform services → applications. Node 1 is Phase 1; nodes 2–3
are later expansion. Software cards describe a logical stack, not host placement
or installation order. The observability frame lists individual products.

<p align="center"><a href="platform/rfc0011-platform-stack.svg"><img src="platform/rfc0011-platform-stack.svg" alt="Proposed mini-PC stack from hardware at the bottom to applications at the top" width="960"></a></p>
<p align="center"><sub>Source <a href="platform/rfc0011-platform-stack.drawio"><code>platform/rfc0011-platform-stack.drawio</code></a> · <a href="platform/img/rfc0011-platform-stack.png">PNG</a></sub></p>

The access view separates private administration, selected private web routes
and independent LAN recovery. It does not select an Access identity provider or
imply that Tailscale's Kubernetes proxy provides host recovery.

<p align="center"><a href="platform/rfc0011-access.svg"><img src="platform/rfc0011-access.svg" alt="Proposed Tailscale administration, Cloudflare private web access and independent LAN recovery" width="960"></a></p>
<p align="center"><sub>Source <a href="platform/rfc0011-access.drawio"><code>platform/rfc0011-access.drawio</code></a> · <a href="platform/img/rfc0011-access.png">PNG</a></sub></p>

The network view maps the proposed components to **all seven OSI layers**.
These are protocol functions, distinct from the stack preview's five hosting
bands. A product can span layers: Tailscale's IP overlay is L3, its Kubernetes
API proxy is L7, and its encrypted traffic needs an underlying transport.

<p align="center"><a href="platform/rfc0011-network-osi.svg"><img src="platform/rfc0011-network-osi.svg" alt="Seven OSI layers mapping Ethernet, switching, routing, transports, TLS and application proxies in the proposed homelab" width="960"></a></p>
<p align="center"><sub>Source <a href="platform/rfc0011-network-osi.drawio"><code>platform/rfc0011-network-osi.drawio</code></a> · <a href="platform/img/rfc0011-network-osi.png">PNG</a></sub></p>

| OSI layer | Homelab interpretation |
|-----------|------------------------|
| L7 — Application | HTTP routing in Envoy, Access admission, the web Tunnel proxy, Kubernetes API proxy, OIDC and DNS |
| L6 — Presentation | TLS encryption and message encodings as conceptual analogies; modern protocols do not implement a separate OSI appliance |
| L5 — Session | Establishing, maintaining and resuming communication; no dedicated session appliance is proposed |
| L4 — Transport | TCP/UDP, ports and transport policy; Tunnel uses QUIC/UDP or HTTP/2/TCP on outbound port 7844 |
| L3 — Network | Home-router IP forwarding, Tailscale IP overlay/subnet routing and candidate Cilium networking; address plan remains open |
| L2 — Data link | Ethernet frames, MAC forwarding, switch ports and optional VLAN separation; VLAN plan remains open |
| L1 — Physical | Cabling, NIC PHYs, physical ports and link signalling; speed and hardware remain open |

See [ADR-087's deployment roles](../proposals/adr/ADR-087-homelab-private-and-web-access/#tailscale-homelab-deployment-roles)
for the difference between native clients, subnet routers and API proxies.
The OSI view classifies functions; the physical and access views above explain
connections and request paths.

Validation has no errors. The stack and OSI views intentionally have no packet arrows:
their unconnected-card warnings describe inventories and functional mappings. The access and physical
views retain the generator's dashed-legend warning because its visible caption
is a separate cell. Product icons identify technology, not adoption status.

### Network references

- [OSI network layers](https://developers.cloudflare.com/fundamentals/reference/network-layers/)
- [Tailscale homelab guide](https://tailscale.com/use-cases/homelab)
- [Tailscale and OSI](https://tailscale.com/docs/concepts/tailscale-osi)
- [Tailscale connection types](https://tailscale.com/docs/reference/connection-types)
- [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [Tailscale Operator architecture](https://tailscale.com/docs/kubernetes-operator/concepts/architecture)
- [Cloudflare Tunnel connectivity](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/troubleshoot-tunnels/connectivity-prechecks/)
- [Cilium policy](https://docs.cilium.io/en/stable/security/policy/intro/)

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
