# ADR-069: Serve Commerce Analytics through a Read-Only Service

> **Decision summary:** We will expose Backoffice commerce analytics through a
> thin read-only `analytics-service` because the browser needs one governed
> cross-domain result without ClickHouse credentials or metric logic. We accept
> one new service and protected route in exchange for keeping commands on their
> owning services and analytical storage behind a stable trust boundary.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-09-09 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The serving boundary between ClickHouse commerce views and the Backoffice Admin Portal |
| **Affected components** | New `analytics-service` repository and deployment; ClickHouse read identity; Envoy Gateway protected route; Admin Portal analytics page; API contracts and observability |
| **Related RFC** | [RFC-0030](../../rfc/RFC-0030/) |
| **Related research** | [research.md](../../rfc/RFC-0030/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | [#1331](https://github.com/duynhlab/homelab/issues/1331) — native Task sub-issues and tradeoff log |
| **Adoption** | Partial — service, route and Admin page read real CDC data on Kind (2026-10-23); the admin default-window fix runs as `sha-e97325a` until the v0.5.2 release passes the full E2E audit (#1334); the 90-day funnel over the 500 ms bar is an owner-accepted known limit ([analytics-service#4](https://github.com/duynhlab/analytics-service/issues/4)) |

## Context

ADR-048 deliberately kept the Admin Portal as a static SPA that calls owning
services directly. It named a read-only aggregator as the escape hatch when a
screen genuinely requires cross-domain joins. Commerce analytics now needs one
answer derived from order, checkout, and payment facts, so three direct browser
queries cannot produce authoritative metrics or one freshness decision.

ClickHouse is an internal analytical store. Giving its credential or arbitrary
SQL to a browser would expose raw storage, couple the UI to physical schemas,
and move money/funnel semantics into presentation code. Adding analytics reads
to a transactional service would assign cross-domain data and availability to
a component that does not own them.

## Scope

### In scope

- The read-only aggregation service and its trust, data, and failure boundaries.
- One bounded protected commerce-overview operation.
- The relationship to ADR-048 and direct command routing.

### Out of scope

- Any command, mutation, business invariant, or transactional write.
- Generic SQL, report builders, exports, or arbitrary dimensions.
- PeerDB control APIs and ClickHouse raw-table access.
- The Admin page's visual implementation details.

## Telemetry decision (implemented)

The service owns a 30-second background freshness sampler with a 2-second
query budget, immediate startup sampling and no overlapping queries. Observable
gauges read an atomic in-memory snapshot; they never query ClickHouse during
collection. A snapshot older than 65 seconds or an invalid/failed batch produces
`unknown`, with lag omitted. All four states are emitted as 0/1 per source.
Response freshness remains independently checked on every request.

The analytics namespace is registered in `pkg/semconv` before first release.
`analytics.source.lag` becomes a seconds gauge, `analytics.source.state` a
unit-1 one-hot gauge, and `analytics.freshness.last_success.time` a seconds Unix
timestamp. Request-driven observation counters are removed. The existing
ClickHouse adapter owns standard `db.client.operation.duration` and one client
span per query, using shared DB buckets and bounded query summaries.

`analytics.overview` carries a bounded unavailable reason. Shared HTTP middleware
remains the sole owner of access logs and HTTP metrics; its 503 record links to
the operation span by trace ID. Cancellation is distinguished from timeout;
raw driver errors, SQL and parameters are never attached. See the
[telemetry contract, candidates and Linux gates](../../../observability/analytics/)
for exact boundaries, cardinality budget, alert recovery and sampler lifecycle.
T1 (transport flag separation / ClickHouse TLS) remains a separate follow-up.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Preserve business ownership | Analytics must never become a second command or transactional write path |
| 2 | Protect analytical storage | Browsers must not receive ClickHouse credentials or arbitrary query capability |
| 3 | One metric and freshness authority | Money, funnel, tombstone, and staleness semantics must not be reimplemented in the UI |
| 4 | Bounded interface | One reviewed operation is easier to secure and operate than a generic analytics API |
| 5 | Independent failure | Analytics outages must not enter checkout, order, or payment error budgets |

## Decision

We will add a thin, read-only `analytics-service` as the aggregation escape
hatch anticipated by ADR-048. It will own no business data and will query only
reviewed ClickHouse serving objects through a read-only identity. It receives no
source, catalog, staging, PeerDB-control, or ClickHouse-write credential.

Its initial public surface is one bounded operation:

```text
GET /analytics/v1/protected/commerce/overview?currency=USD&from=YYYY-MM-DD&to=YYYY-MM-DD
```

The service will enforce the staff issuer and `backoffice_admin`, reject
unbounded intervals and arbitrary SQL/columns, and return metric values with
`generated_at`, `data_through`, `stale`, and source-level health. Two-to-five
minutes of lag is explicitly stale; more than five minutes or unknown freshness
returns `503` rather than a plausible zero.

Admin commands continue directly through the edge to their owning services.
The protected analytics route and portal navigation stayed absent until the
service passed the dark-launch correctness, authorization, freshness, and
failure gates; both were added once those gates passed (Kind rows K4.13 and
K4.14, 2026-10-23).

The [contract](../../../api/analytics.md) selects USD-only v1, decimal integer
JSON strings for money, ledger event-date totals, and checkout-created cohorts
with current observed stages. The service (`v0.1.0`), the
`api-analytics-protected` route under `jwt-edge-staff`, and the Backoffice
`/analytics` page are deployed in local-stack and on Kind on a **fixture-backed
serving layer** (PeerDB's table shape, CDC not yet deployed); the Linux
evidence is on [#1332](https://github.com/duynhlab/homelab/issues/1332),
[#1334](https://github.com/duynhlab/homelab/issues/1334) and
[#1335](https://github.com/duynhlab/homelab/issues/1335). The first
one-million-fact run failed the performance bar because the serving views
recomputed `argMax` over every row per call and the reader joined on string
keys. The views now read `FINAL` over `ReplacingMergeTree(_peerdb_version)`
([homelab#1366](https://github.com/duynhlab/homelab/pull/1366)) and the reader
joins on typed keys
([analytics-service#5](https://github.com/duynhlab/analytics-service/pull/5)).
Adoption stays **Partial**: the serving data is a fixture, and the 90-day
funnel query (0.55 s median) remains over the 500 ms bar, which the owner
accepted as a known limit on 2026-10-23
([analytics-service#4](https://github.com/duynhlab/analytics-service/issues/4)).

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | `analytics-service` owns query composition and response semantics, but no business state or invariant |
| **Write path** | No business mutation, command proxy, source write, or ClickHouse write is permitted |
| **Read path** | The service reads only reviewed serving objects with a dedicated read-only ClickHouse identity |
| **Consumer trust** | Browser access goes through the protected edge route with staff issuer and `backoffice_admin`; no database credentials reach the browser |
| **Failure behavior** | Stale and unknown data are explicit; the service never fabricates freshness or converts an unavailable pipeline into zero |
| **Compatibility** | Commands remain direct under ADR-048; exact payload becomes authoritative in `docs/api/analytics.md` only after implementation |

The read-only database identity is `analytics_reader`, with SELECT on reviewed
`analytics.*_live` views only. Resource names follow the
[RFC-0030 naming contract](../../rfc/RFC-0030/README.md#resource-naming); the
`/analytics/v1/protected/commerce/overview` API route is unchanged.

### Decision view

```mermaid
flowchart LR
    A["Admin Portal<br/>staff token"] -->|"bounded protected GET"| E["Envoy Gateway"]
    E --> S["analytics-service<br/>read only"]
    S -->|"serving queries"| CH[("ClickHouse<br/>analytics serving views")]
    A -->|"commands go to the owners"| E
    E -->|"protected routes"| OWN["Owning services"]
    S -.->|"must not proxy writes"| OWN

    classDef edge fill:#dbeafe,color:#1e3a8a,stroke:#2563eb;
    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
    class E edge;
    class A,S,OWN service;
    class CH data;
```

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Thin read-only analytics service** | One governed contract, server-side semantics, no browser DB credential | New service, route, deployment, SLO, and on-call surface | Selected |
| **B — Browser queries ClickHouse directly** | No API service | Exposes credentials and physical schemas; arbitrary queries; metric logic in UI | Rejected |
| **C — Grafana as the product surface** | Existing ClickHouse integration and charts | Dashboard access is not an application contract or Backoffice UX boundary | Rejected |
| **D — Extend transactional services** | No new repository | Splits cross-domain semantics and couples OLAP availability to domain services | Rejected |
| **E — Generic admin BFF or GraphQL gateway** | Flexible future composition | Larger read/write surface, schema governance, and pressure to proxy commands | Rejected |

### Why the selected option won

It activates the smallest exception already anticipated by ADR-048: a service
that aggregates reads only. One operation centralizes money, funnel, tombstone,
and freshness rules while leaving every transactional command and invariant at
its existing owner.

### Why the closest alternative lost

Direct browser-to-ClickHouse access removes one deployment but transfers the
database security boundary, SQL shape, query cost, and metric interpretation to
an untrusted client. That is not fewer responsibilities; it only moves them to
the least controllable tier.

## Consequences

### Positive consequences

- The browser receives one bounded, authenticated analytics contract.
- ClickHouse credentials and physical schemas remain internal.
- Money and freshness semantics have one testable owner.
- Analytics can fail or roll back without blocking transactions.
- ADR-048's direct command topology remains intact.

### Negative consequences and accepted trade-offs

- A new Go service, repository, image, deployment, route, alerts, and runbook must be owned.
- The service must defend ClickHouse from unbounded date ranges and query cost.
- API and serving-schema evolution must be coordinated.
- Operators see eventual consistency rather than transactional truth.

### Neutral consequences

- The Admin Portal gains one additional API client and lazy route.
- This service is a read model boundary, not a new business domain.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Implement the bounded service contract and validation | `analytics-service` | [#1332](https://github.com/duynhlab/homelab/issues/1332) | Contract, unit, integration, and negative authorization tests pass |
| Provision read-only serving access and network path | Platform / ClickHouse | [#1333](https://github.com/duynhlab/homelab/issues/1333) | Identity cannot read raw objects or perform writes |
| Add deployment, protected route, and observability | Platform / Observability | [#1334](https://github.com/duynhlab/homelab/issues/1334) | Resources, probes, policies, RED metrics, alerts, and runbook pass validation |
| Add the Admin analytics page after dark-launch gates | `admin-service` | [#1335](https://github.com/duynhlab/homelab/issues/1335) | Loading, empty, stale, unavailable, keyboard, and responsive states pass |
| Publish the as-built contract and topology | Platform docs | [#1336](https://github.com/duynhlab/homelab/issues/1336) | `docs/api/analytics.md`, rollup, Admin index, ownership map, and call graph match deployment |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Read-only boundary | Negative source, catalog, staging, raw-table, ClickHouse-write, and command-proxy tests |
| Authorization | Customer issuer, missing role, expired token, and direct-backend attempts fail; authorized staff succeeds |
| Bounded query | Invalid currency/range, empty interval, over-90-day interval, and arbitrary parameter tests fail closed |
| Freshness contract | Fresh returns `200`; 2–5 minute lag returns `200 stale=true`; over 5 minutes or unknown returns `503` |
| Correctness and performance | One-million-fact 7/30/90-day checksums match; ClickHouse query p95 ≤500 ms and peak memory ≤512 MiB. **Accepted deviation (owner, 2026-10-23):** the 90-day funnel query measures ~0.55 s median on one million facts with two threads (daily 0.23 s, captured 0.25 s, products 0.38 s meet the bar); the daily-rollup remedy is deferred ([analytics-service#4](https://github.com/duynhlab/analytics-service/issues/4)) |
| Isolation | Stop analytics dependencies and prove checkout, order, and payment continue without changed error budgets |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A required analytics operation must execute a business command or enforce a transactional invariant.
- Multiple consumers require a broader, versioned analytics product boundary.
- Query diversity cannot remain bounded without an asynchronous report/export model.
- ClickHouse serving latency or availability cannot meet the operator contract.
- The service begins accumulating domain-specific write logic or generic BFF behavior.

A changed decision requires a new ADR that supersedes this one.

## References

- [RFC-0030](../../rfc/RFC-0030/)
- [RFC-0030 research](../../rfc/RFC-0030/research.md)
- [ADR-048 — Call owning services directly from the Admin Portal](../ADR-048-admin-portal-no-bff/)
- [Admin consumer contract](../../../api/admin.md)
- [Shared API conventions](../../../api/api.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-09-09 | Proposed / Not started | Initial decision drafted during RFC-0030 architecture review |
| 2026-09-09 | Accepted / Not started | Owner accepted the architecture; qualification remains Phase 0 of implementation |
| 2026-10-23 | Accepted / Partial | Service, edge route and Admin page deployed on a fixture-backed serving layer; compose A25/B11/C23 and Kind K3.12, K4.12–K4.14, K5.11 pass (homelab#1361, #1360); the one-million-fact performance bar fails (analytics-service#4) and holds the first tag |
| 2026-10-23 | Accepted / Partial | Serving views read `FINAL` over `ReplacingMergeTree(_peerdb_version)` (homelab#1366) and the reader joins on typed keys (analytics-service#5); 90-day medians 0.23/0.25/0.38/0.55 s (daily/captured/products/funnel) on one million facts; owner accepted the funnel's miss of the 500 ms bar as a known limit and deferred the daily rollup (analytics-service#4) |
| 2026-10-23 | Accepted / Partial | The serving layer now reads real CDC (RFC-0030 phases 1–7 complete); analytics freshness alerts load (#1373); a cold bring-up reaches a ready analytics-service with no manual step (#1378). Remaining: admin-service v0.5.2 |
