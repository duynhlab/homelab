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
→ `README.md` → architecture review → ADR(s) at **`Proposed`** → **`Accepted`** →
implement → sync [`docs/api/`](../../api/README.md) → runbooks (when ops-relevant).
Full ADR process: [`adr/README.md`](../adr/README.md).

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
5. **Architecture review** — identify independent decisions; create ADR(s) under
   [`adr/`](../adr/) at **`Proposed`** (copy [`ADR-0000-template/`](../adr/ADR-0000-template/));
   fill RFC [**Resulting decisions**](RFC-0000/README.md#resulting-decisions) table.
6. **On approval** — RFC → **`Accepted`**; linked ADR(s) → **`Accepted`**; ADR
   **Adoption** → **`Not started`**. Legacy index rows labelled **`implementable`** mean
   the same as **`Accepted`**.
7. **Implement** → RFC Status **`implemented`**; ADR **Adoption** → Partial/Complete;
   append **Implementation History** and PR links.
8. **Sync `docs/api/` (API-touching)** — when Adoption is **Complete** / RFC is
   **`implemented`**:
   - Map the change → owning file(s) via [`docs/api/README.md` § Document Ownership](../../api/README.md#document-ownership).
   - Update **Design records** on service Identity tables; hub rollup and At a glance rows when deploy/transport changes.
   - Service files touched use [`_template-service.md`](../../api/_template-service.md) v2 (no full backfill of legacy v1 contracts required).
   - Reuse Mermaid from the RFC when helpful — label *As-built contract* vs *Target state*; tag **planned** behaviour accurately.
   - Link back from RFC **Related** and spawned ADR **References**.
   Infra-only RFCs update platform docs instead; skip `docs/api/` unless app contracts change.
9. **Runbooks** — add or update area runbooks when the change introduces meaningful
   operational failure modes (topic-dependent paths under `docs/observability/runbooks/`,
   `docs/databases/runbooks/`, …).

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
| **provisional** | `README.md` exists; under architecture review |
| **Accepted** | Review passed; linked ADR(s) Accepted; ready to implement |
| **implemented** | Shipped; track in Implementation History |
| **superseded** | Replaced by a later RFC or approach |
| **deferred** · **rejected** · **withdrawn** · **replaced** | See RFC body |
| **template** | Copy source only ([`RFC-0000/`](RFC-0000/)) |

> **Legacy index label:** some rows still say **`implementable`** — equivalent to
> **`Accepted`**. Do not bulk-rename live RFC folders in drive-by PRs.

## Index

> Index ordered by RFC number (stable registry). Sequencing is owner-driven — see each
> RFC's Status and linked README.

| RFC | Title | Scope | Priority | Status |
|-----|-------|-------|----------|--------|
| [RFC-0001](RFC-0001/) | Temporal for durable cross-service orchestration | platform-wide | done | implemented |
| [RFC-0002](RFC-0002/) | East-west mTLS for internal gRPC | platform-wide | P1 | superseded — in-process → **[RFC-0020](RFC-0020/)**, mesh → [RFC-0006](RFC-0006/) |
| [RFC-0003](RFC-0003/) | Inventory ownership and stock semantics | platform-wide | — | superseded — **[RFC-0021](RFC-0021/)** (inventory extraction) |
| [RFC-0004](RFC-0004/) | Cross-service caching and invalidation | platform-wide | P2 | provisional |
| [RFC-0005](RFC-0005/) | supporting-shared-db: HA or split | infra | P2 | provisional — **superseded by [RFC-0018](RFC-0018/)** (platform-db merge) |
| [RFC-0006](RFC-0006/) | Service mesh evaluation (Istio Ambient vs Linkerd) — future mesh; in-process mTLS now in [RFC-0020](RFC-0020/) | infra | defer | provisional |
| [RFC-0007](RFC-0007/) | Disaster-recovery drills program | infra | done | implemented — program documented and Drill A recorded (`DR-2026-08-A`, Barman gate closed); the recurring cadence and Drills C/D activate with durable hardware ([RFC-0011](RFC-0011/)) |
| [RFC-0008](RFC-0008/) | Production secrets hardening & local/prod parity | infra | P1 | implementable — Slice 1 (awskms auto-unseal, [ADR-024](../adr/ADR-024-floci-kms-emulator-auto-unseal/)) landed; cloud-bound items remain proposal-only |
| [RFC-0009](RFC-0009/) | Production-grade API gateway: signed JWT + Kong edge auth | platform-wide | done | implemented |
| [RFC-0010](RFC-0010/) | Payment service: PaymentIntent, ledger & charge/refund saga step | platform-wide | done | implemented (P1–P6 landed) |
| [RFC-0011](RFC-0011/) | Homelab migration: Kind to bare-metal Talos (1 → 3 node HA) | infra | P2 | provisional |
| [RFC-0012](RFC-0012/) | Converge CNPG role & database management on declarative CRDs | infra | done | implemented (P0–P4 landed) |
| [RFC-0013](RFC-0013/) | App-metrics cardinality audit & streaming-aggregation scale playbook | platform-wide | — | superseded |
| [RFC-0014](RFC-0014/) | Full OpenTelemetry adoption: OTLP push for metrics, logs and traces | platform-wide | done | implemented (live-cluster drill pending) |
| [RFC-0015](RFC-0015/) | Checkout service: session state machine, price re-validation & order handoff | platform-wide | done | implemented — P1–P5 shipped by this RFC; the P6 legacy-path removal shipped via [RFC-0021](RFC-0021/) P5 (order 1.11.0 removed `POST /orders` + the order→cart pricing read) |
| [RFC-0017](RFC-0017/) | Platform telemetry standard: per-layer signal ownership + fleet instrumentation | platform-wide | done | implemented — W0/W1 landed fleet-wide; business-metric alerts/SLOs + ~16 catalog rows stay backlog |
| [RFC-0018](RFC-0018/) | Consolidate platform PostgreSQL: merge auth, shared, temporal into platform-db | infra | done | implemented — every platform database runs on CNPG `platform-db`/`product-db` (#496, #543/#544; Kind audit green); the P4 DR drills stay on the RFC-0007 calendar |
| [RFC-0019](RFC-0019/) | ClickHouse for OTel logs/traces SQL (+ optional commerce analytics) | platform-wide | done | implemented (Phase B) — OLAP for OTel logs+traces deployed in local-stack + cluster (#560, [ADR-023](../adr/ADR-023-clickhouse-observability-olap/)); Phase A commerce facts stays out of scope |
| [RFC-0020](RFC-0020/) | Internal TLS everywhere on the `homelab-ca` root (DB, pooler, gRPC, OpenBAO) | platform-wide | P1 | provisional |
| [RFC-0021](RFC-0021/) | Platform overhaul: inventory extraction, order aggregate, payment hardening (supersedes [RFC-0003](RFC-0003/)) | platform-wide | done | **implemented (P0–P7 landed)** — inventory is the sole stock authority; product's stock RPCs, read fields and schema are removed; the order aggregate ([ADR-033](../adr/ADR-033-order-status-cancellation/)) and payment ambiguity ([ADR-034](../adr/ADR-034-provider-outcome-ambiguity/)…[ADR-037](../adr/ADR-037-per-request-refund-identity/)) shipped; migration flags gone and the first [GameDay run](RFC-0021/gameday.md) recorded (5 faults, 2 claims falsified). Deferred items are listed in the RFC's Implementation History, not dropped |
| [RFC-0022](RFC-0022/) | Adopt Keycloak as the platform identity provider; retire auth-service (supersedes the custom-issuer portions of [RFC-0009](RFC-0009/)) | platform-wide | P1 | Accepted — **implementation absorbed into [RFC-0024](RFC-0024/)** (design record stands) |
| [RFC-0023](RFC-0023/) | Basic Backoffice portal (React + TanStack) and the first `protected` business APIs (depends on [RFC-0022](RFC-0022/)) | platform-wide | P2 | Accepted |
| [RFC-0024](RFC-0024/) | Replatform edge and identity: Envoy Gateway + Keycloak, one greenfield cutover (executes [RFC-0022](RFC-0022/); supersedes the Kong vehicle of [RFC-0009](RFC-0009/)/[ADR-006](../adr/ADR-006-rs256-jwt-kong-edge-auth/)) | platform-wide | P1 | Accepted |

## Backlog — candidate RFCs

Substantial themes gathered from across the repo. Each **reserves the next RFC number**
when someone starts research (owner OK → `research.md` → index `researching`).

| Candidate | Scope | Source |
|-----------|-------|--------|
| **RFC-0016** — async payment confirmation via Temporal *(reserved; absorbed into [RFC-0021](RFC-0021/) phase 6 — number retired, do not backfill)* | platform-wide | [RFC-0015](RFC-0015/) |
| **Atlantis** PR-driven Terraform | infra | [`terraform/`](../../../terraform/) |
| **Alert delivery** (Slack via OpenBAO + PagerDuty) | infra | `docs/observability/alerting/` |
| **Authorization (RBAC/ABAC)** — claim population + enforcement; claim population moves to Keycloak roles under [RFC-0022](RFC-0022/); the first enforcement (role gate + `protected` routes) ships with [RFC-0023](RFC-0023/); fine-grained roles remain here | platform-wide | [RFC-0009](RFC-0009/) O1 |
| **Gateway improvements** — edge `proxy-cache` + dedicated per-env issuer domain; the issuer-domain question is reshaped by the Keycloak realm issuer in [RFC-0022](RFC-0022/) | infra | [RFC-0009](RFC-0009/) O4/O6 |
| ~~**Gateway strategy post-Kong-OSS**~~ — **promoted to [RFC-0024](RFC-0024/)** (owner activated the exit trigger proactively, 2026-08-10) | infra | RFC-0022 § Gateway distribution risk |
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
_Last updated: 2026-08-13 — RFC-0023 Accepted (Backoffice portal + first `protected` APIs); ADR-047..049 created at Accepted._
