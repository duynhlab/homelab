# RFCs — Requests for Comments

This directory is the **single home for proposing and tracking substantial changes**
to the duynhlab platform — infrastructure (this repo) *and* the microservice code.
In many cases a new feature or enhancement is proposed here first, discussed on a
pull request, and only then implemented.

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

| RFC | Title | Scope | Status |
|-----|-------|-------|--------|
| [RFC-0001](RFC-0001/) | Temporal for durable cross-service orchestration | platform-wide | implemented |
| [RFC-0002](RFC-0002/) | East-west mTLS for internal gRPC | platform-wide | provisional |
| [RFC-0003](RFC-0003/) | Inventory ownership and stock semantics | platform-wide | provisional |
| [RFC-0004](RFC-0004/) | Cross-service caching and invalidation | platform-wide | provisional |
| [RFC-0005](RFC-0005/) | supporting-shared-db: HA or split | infra | provisional |

## Backlog — candidate RFCs

Substantial themes gathered from across the repo (the place to manage them now lives
here). Each gets a number when someone writes it up.

| Candidate | Scope | Source |
|-----------|-------|--------|
| **DR drills program** (PITR/failover evidence; Barman plugin acceptance) | infra | `docs/databases/010*-*` |
| **Service mesh** decision (Istio Ambient / Linkerd) | infra | `TODO.md` |
| **Atlantis** PR-driven Terraform | infra | `TODO.md` |
| **Alert delivery** (Slack via OpenBAO + PagerDuty) | infra | `docs/observability/alerting/` |
| **Kong-JWT reconsideration** (gateway vs services) | platform-wide | `docs/platform/kong-gateway.md`, ADR-003 |
| **Talos bare-metal migration** | infra | `docs/platform/homelab-migration-plan.md` |
| **Chaos / GameDay program** | infra | `TODO.md`, DR docs |
| **API v1→v2 versioning policy** | platform-wide | `docs/api/api-naming-convention.md` |

> Temporal durability/DR (HA, Barman, GameDay) is tracked as **future work in
> [RFC-0001](RFC-0001/)**, not a separate backlog row.
