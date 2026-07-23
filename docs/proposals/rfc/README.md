# RFCs — Requests for Comments

This directory is the **single home for proposing and tracking substantial changes**
to the duynhlab platform — infrastructure (this repo) *and* the microservice code.
Every substantial topic **reserves an RFC number first**, explores in **`research.md`**,
then writes the decision in **`README.md`**.

Overview and lifecycle diagram: [`docs/proposals/README.md`](../README.md). **Index and
backlog live in this file.**

> **Don't forget: every decision is a tradeoff.** A good RFC states what the choice
> *costs* (rejected alternatives + drawbacks + rollback), not just what it buys.

## When to write an RFC

Write an RFC for a **substantial** change — one that needs a design + review + a
diagram *before* anyone builds it. Examples:

- **API additions** — new kinds of resources, new relationships between existing APIs.
- **API breaking changes** — new required fields, field removals, response-shape changes.
- **Security-related changes** — Flux controller permissions, east-west mTLS, tenant
  isolation / impersonation, trust-boundary moves.
- **Impactful UX changes** — new required inputs to the bootstrap/onboarding process.
- **Dropping capabilities** — sunsetting an integration with an external service.
- **New platform capabilities/backends** — adopting a new datastore, mesh, or orchestrator.

**Don't** write an RFC for bug fixes, cleanups, or dependency bumps — ship in a focused PR.

## Process

| Artifact | File | Template | Question it answers |
|----------|------|----------|---------------------|
| **Template** | [`RFC-0000/`](RFC-0000/) | Copy source only — **never** a live proposal | — |
| **Research** | `RFC-NNNN/research.md` | [`RFC-0000/research.md`](RFC-0000/research.md) | What **real-world problem** are we solving, how does the tech work, and how does it compare to what we run? |
| **RFC** | `RFC-NNNN/README.md` | [`RFC-0000/README.md`](RFC-0000/README.md) | What do we decide, target architecture, rollout? |
| **Domain doc** (optional) | `docs/<area>/<topic>/README.md` | [`AGENTS.md`](../../../AGENTS.md) docs conventions | How does it work **in this platform**? |

**Flow:** real-world problem in `research.md` → [research review gate](RFC-0000/research.md#research-review-gate)
→ `README.md` → optional domain doc → implement → sync [`docs/api/`](../../api/README.md) when
API-touching → ADR(s) under [`adr/`](../adr/).

1. **Reserve number (owner OK required)** — propose the exact next slot (e.g. **RFC-0019**
   = `max(RFC-NNNN) + 1`; do not backfill gaps unless the owner asks). On approval, in
   the **same PR**: create `RFC-NNNN/`, copy [`RFC-0000/research.md`](RFC-0000/research.md)
   only, add an index row with Status **`researching`**. Do **not** copy `README.md` yet.
2. **Research phase** — iterate `research.md`; run Context7 audit; owner review loops
   until the review gate passes.
3. **RFC phase** — after owner **ready for RFC**, copy
   [`RFC-0000/README.md`](RFC-0000/README.md) → `RFC-NNNN/README.md`; fill from research;
   set Status **`provisional`** in this index (replaces `researching`).
4. **Optional domain doc** — owner picks `docs/<area>/<topic>/README.md`; distill from
   research; link both ways; register in [`docs/README.md`](../../README.md) and the area
   index. Follow [`AGENTS.md`](../../../AGENTS.md) docs conventions (house shape, English,
   **planned** vs **deployed**).
5. **Implement** → Status `implemented` → spawn ADR(s) under [`adr/`](../adr/).
6. **Sync `docs/api/` (API-touching)** — in the same PR or an immediate follow-up before
   or when Status becomes **`implemented`**:
   - Map the change → owning file(s) via [`docs/api/README.md` § Document Ownership](../../api/README.md#document-ownership).
   - Update **Design records** on service Identity tables; hub rollup and At a glance rows when deploy/transport changes.
   - Service files touched use [`_template-service.md`](../../api/_template-service.md) v2 (no full backfill of legacy v1 contracts required).
   - Reuse Mermaid from the RFC when helpful — label *As-built contract* vs *Target state*; tag **planned** behaviour accurately.
   - Link back from RFC **Related** and spawned ADR **Consequences**.
   Infra-only RFCs update platform docs instead; skip `docs/api/` unless app contracts change.

Keep diagrams/assets **inside the RFC folder** (or the chosen domain doc path). Mermaid
may repeat across artifacts — label each diagram's question (*Mechanism*, *Target state*,
*Homelab as-built*, *As-built contract*) and keep deployed facts in sync.

**Duplication with `docs/api/`:** operational contract (routes, RPCs, payloads, status)
lives in [`docs/api/`](../../api/README.md); tradeoffs and alternatives stay in the RFC.
Copying diagrams or prose into a service contract is OK when cross-linked — do not dedupe
for its own sake.

| Status | Meaning |
|--------|---------|
| **researching** | Number reserved; only `research.md` exists (title may be TBD) |
| **provisional** | `README.md` exists; decision under review |
| **implementable** | Design settled; ready to build |
| **implemented** | Shipped |
| **superseded** | Replaced by a later RFC or approach |
| **deferred** · **rejected** · **withdrawn** · **replaced** | See RFC body |
| **template** | Copy source only ([`RFC-0000/`](RFC-0000/)) |

## Index

> Index ordered by RFC number (stable registry). Sequencing is owner-driven — see each
> RFC's Status and linked README.

| RFC | Title | Scope | Priority | Status |
|-----|-------|-------|----------|--------|
| [RFC-0001](RFC-0001/) | Temporal for durable cross-service orchestration | platform-wide | done | implemented |
| [RFC-0002](RFC-0002/) | East-west mTLS for internal gRPC | platform-wide | P1 | superseded — in-process → **[RFC-0020](RFC-0020/)**, mesh → [RFC-0006](RFC-0006/) |
| [RFC-0003](RFC-0003/) | Inventory ownership and stock semantics | platform-wide | P2 | provisional |
| [RFC-0004](RFC-0004/) | Cross-service caching and invalidation | platform-wide | P2 | provisional |
| [RFC-0005](RFC-0005/) | supporting-shared-db: HA or split | infra | P2 | provisional — **superseded by [RFC-0018](RFC-0018/)** (platform-db merge) |
| [RFC-0006](RFC-0006/) | Service mesh evaluation (Istio Ambient vs Linkerd) — future mesh; in-process mTLS now in [RFC-0020](RFC-0020/) | infra | defer | provisional |
| [RFC-0007](RFC-0007/) | Disaster-recovery drills program | infra | P2 | provisional |
| [RFC-0008](RFC-0008/) | Production secrets hardening & local/prod parity | infra | P1 | provisional |
| [RFC-0009](RFC-0009/) | Production-grade API gateway: signed JWT + Kong edge auth | platform-wide | done | implemented |
| [RFC-0010](RFC-0010/) | Payment service: PaymentIntent, ledger & charge/refund saga step | platform-wide | done | implemented (P1–P6 landed) |
| [RFC-0011](RFC-0011/) | Homelab migration: Kind to bare-metal Talos (1 → 3 node HA) | infra | P2 | provisional |
| [RFC-0012](RFC-0012/) | Converge CNPG role & database management on declarative CRDs | infra | done | implemented (P0–P4 landed) |
| [RFC-0013](RFC-0013/) | App-metrics cardinality audit & streaming-aggregation scale playbook | platform-wide | — | superseded |
| [RFC-0014](RFC-0014/) | Full OpenTelemetry adoption: OTLP push for metrics, logs and traces | platform-wide | done | implemented (live-cluster drill pending) |
| [RFC-0015](RFC-0015/) | Checkout service: session state machine, price re-validation & order handoff | platform-wide | P0 | provisional |
| [RFC-0017](RFC-0017/) | Platform telemetry standard: per-layer signal ownership + fleet instrumentation | platform-wide | P1 | implementable |
| [RFC-0018](RFC-0018/) | Consolidate platform PostgreSQL: merge auth, shared, temporal into platform-db | infra | P1 | provisional |
| [RFC-0019](RFC-0019/) | ClickHouse for OTel logs/traces SQL (+ optional commerce analytics) | platform-wide | P2 | provisional |
| [RFC-0020](RFC-0020/) | Internal TLS everywhere on the `homelab-ca` root (DB, pooler, gRPC, OpenBAO) | platform-wide | P1 | provisional |

## Backlog — candidate RFCs

Substantial themes gathered from across the repo. Each **reserves the next RFC number**
when someone starts research (owner OK → `research.md` → index `researching`).

| Candidate | Scope | Source |
|-----------|-------|--------|
| **RFC-0016** — async payment confirmation via Temporal *(planned; no folder yet)* | platform-wide | [RFC-0015](RFC-0015/) |
| **Atlantis** PR-driven Terraform | infra | [`terraform/`](../../../terraform/) |
| **Alert delivery** (Slack via OpenBAO + PagerDuty) | infra | `docs/observability/alerting/` |
| **Authorization (RBAC/ABAC)** — claim population + enforcement | platform-wide | [RFC-0009](RFC-0009/) O1 |
| **Gateway improvements** — edge `proxy-cache` + dedicated per-env issuer domain | infra | [RFC-0009](RFC-0009/) O4/O6 |
| **Chaos / GameDay program** | infra | [`docs/databases/010-drp.md`](../../databases/010-drp.md), DR docs |
| **API v1→v2 versioning policy** | platform-wide | `docs/api/api.md#versioning-and-compatibility` |
| **Split OpenBAO bootstrap** (auth config vs secret seeding) | infra | secrets ESO review |
| **Secret rotation** (CronJob / push) — largely superseded by dynamic DB creds in [RFC-0008](RFC-0008/) | infra | secrets ESO review |
| **PushSecret for operator-generated secrets** (sync CNPG/Zalando creds back to OpenBAO) | infra | secrets ESO review |

> **Related RFCs:** production secrets hardening → [RFC-0008](RFC-0008/) (shipped OpenBAO
> HA and audit logging → [ADR-005](../adr/ADR-005-openbao-ha-raft/),
> [ADR-004](../adr/ADR-004-enable-openbao-audit-logging/)); Temporal durability/DR →
> [RFC-0001](RFC-0001/) (not a separate backlog row).

---
_Last updated: 2026-07-23_
