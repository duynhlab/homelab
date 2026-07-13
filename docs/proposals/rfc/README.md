# RFCs — Requests for Comments

This directory is the **single home for proposing and tracking substantial changes**
to the duynhlab platform — infrastructure (this repo) *and* the microservice code.
In many cases a new feature or enhancement is proposed here first, discussed on a
pull request, and only then implemented.

> **Don't forget: every decision is a tradeoff.** A good RFC states what the choice
> *costs* (rejected alternatives + drawbacks + rollback), not just what it buys.

> **▶ Current focus & sequencing.** RFC-0009 shipped (implemented — JWT + Kong
> edge auth). Highest-priority *active* proposal on the security track:
> **[RFC-0002](RFC-0002/)** (east-west mTLS), then **[RFC-0008](RFC-0008/)**
> (parallel) → **[RFC-0006](RFC-0006/)** (defer). The index below stays ordered by
> number (a stable registry) — read the **Priority** column for what to pick up next.

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

**Don't** write an RFC for bug fixes, cleanups, dependency bumps, or learning items —
those belong in the trackers below.

## RFC vs ADR vs TODO vs REVIEW

> **Planning ⊋ RFC.** An RFC is only the *substantial* subset of planning. Small
> planned work stays a TODO / finding / issue.

| Artifact | Purpose | Lives in | Lifecycle |
|----------|---------|----------|-----------|
| **RFC** | Propose a **substantial change** (design doc + diagram), discussed **before** building | `docs/proposals/rfc/RFC-NNNN/` | `provisional → implementable → implemented` (or `deferred`/`rejected`/`withdrawn`/`replaced`) |
| **ADR** | **Record a decision** already made + its rationale (Nygard) — often **spawned by** an RFC | [`docs/proposals/adr/`](../adr/) | `Proposed → Accepted → Superseded` |
| **TODO.md** | Personal **learning / skills** checklist | [repo root](../../../TODO.md) | checkboxes |
| **Findings tracker** | Open **code-review findings** (bugs, small improvements) | [GitHub issues](https://github.com/duynhlab/homelab/issues/373) | ticked when fixed |

**Flow:** an RFC is *accepted* → implementation begins → the concrete decisions it
made are recorded as one or more **ADRs**, and the RFC moves to `implemented`.

## How to submit an RFC

1. Copy [`RFC-0000/`](RFC-0000/) to `RFC-NNNN/` (next free number — assigned when you
   open the PR) and fill in [`RFC-0000/README.md`](RFC-0000/README.md).
2. Keep diagrams/assets **inside the RFC's directory**.
3. Open a PR. Discussion happens on the PR; merge it as `provisional` (or
   `implementable` once the design is settled).
4. Update **Status** to `implemented` when it ships; add the spawned ADR links under
   **Related**.

**Status values:** `provisional` · `implementable` · `implemented` · `deferred` ·
`rejected` · `withdrawn` · `replaced`.

## Index

> **Priority key:** **P0** active / highest · **P1** next · **P2** on-merit, unscheduled ·
> **defer** parked · **done** shipped.

| RFC | Title | Scope | Priority | Status |
|-----|-------|-------|----------|--------|
| [RFC-0001](RFC-0001/) | Temporal for durable cross-service orchestration | platform-wide | done | implemented |
| [RFC-0002](RFC-0002/) | East-west mTLS for internal gRPC | platform-wide | P1 | provisional |
| [RFC-0003](RFC-0003/) | Inventory ownership and stock semantics | platform-wide | P2 | provisional |
| [RFC-0004](RFC-0004/) | Cross-service caching and invalidation | platform-wide | P2 | provisional |
| [RFC-0005](RFC-0005/) | supporting-shared-db: HA or split | infra | P2 | provisional |
| [RFC-0006](RFC-0006/) | Service mesh evaluation (Istio Ambient vs Linkerd) | infra | defer | provisional |
| [RFC-0007](RFC-0007/) | Disaster-recovery drills program | infra | P2 | provisional |
| [RFC-0008](RFC-0008/) | Production secrets hardening & local/prod parity | infra | P1 | provisional |
| [RFC-0009](RFC-0009/) | Production-grade API gateway: signed JWT + Kong edge auth | platform-wide | done | implemented |
| [RFC-0010](RFC-0010/) | Payment service: PaymentIntent, ledger & charge/refund saga step | platform-wide | done | implemented (P1–P6 landed) |
| [RFC-0011](RFC-0011/) | Homelab migration: Kind to bare-metal Talos (1 → 3 node HA) | infra | P2 | provisional |
| [RFC-0012](RFC-0012/) | Converge CNPG role & database management on declarative CRDs | infra | done | implemented (P0–P4 landed) |
| [RFC-0013](RFC-0013/) | App-metrics cardinality audit & streaming-aggregation scale playbook | platform-wide | — | superseded |
| [RFC-0014](RFC-0014/) | Full OpenTelemetry adoption: OTLP push for metrics, logs and traces | platform-wide | done | implemented (live-cluster drill pending) |
| [RFC-0015](RFC-0015/) | Checkout service: session state machine, price re-validation & order handoff | platform-wide | P0 | provisional |

## Backlog — candidate RFCs

Substantial themes gathered from across the repo (the place to manage them now lives
here). Each gets a number when someone writes it up.

| Candidate | Scope | Source |
|-----------|-------|--------|
| **Atlantis** PR-driven Terraform | infra | `TODO.md` |
| **Alert delivery** (Slack via OpenBAO + PagerDuty) | infra | `docs/observability/alerting/` |
| **Authorization (RBAC/ABAC)** — claim population + enforcement | platform-wide | [RFC-0009](RFC-0009/) O1 |
| **Gateway improvements** — edge `proxy-cache` + dedicated per-env issuer domain | infra | [RFC-0009](RFC-0009/) O4/O6 |
| **Chaos / GameDay program** | infra | `TODO.md`, DR docs |
| **API v1→v2 versioning policy** | platform-wide | `docs/api/api-naming-convention.md` |
| **Split OpenBAO bootstrap** (auth config vs secret seeding) | infra | secrets ESO review |
| **Secret rotation** (CronJob / push) — largely superseded by dynamic DB creds in [RFC-0008](RFC-0008/) | infra | secrets ESO review |
| **PushSecret for operator-generated secrets** (sync CNPG/Zalando creds back to OpenBAO) | infra | secrets ESO review |

> The broader secrets production hardening (KMS auto-unseal, TLS, dynamic DB creds,
> OIDC, remove committed dev creds) + a local-vs-prod parity/testing matrix is its
> own RFC — [RFC-0008](RFC-0008/). Decisions already shipped
> (OpenBAO HA, audit logging) are recorded in [ADR-005](../adr/ADR-005-openbao-ha-raft/)
> and [ADR-004](../adr/ADR-004-enable-openbao-audit-logging/).

> Temporal durability/DR (HA, Barman, GameDay) is tracked as **future work in
> [RFC-0001](RFC-0001/)**, not a separate backlog row.

---
_Last updated: 2026-07-11_
