# ADR-073: Bound Application Metrics by Instrument, Cardinality and Replay Rules

> **Decision summary:** We will keep the OTel Meter API through the shared provider
> and VictoriaMetrics as the only metrics store, and we will bind every application
> metric to an instrument-selection rule, a fixed fleet bucket set, a cardinality
> allowlist with a series budget, and explicit Temporal replay semantics. We accept
> that a new histogram must declare its boundaries and that no identifier may ever be
> a label, in exchange for quantiles that compare across services and a series count
> that stays inside what the store can ingest.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-09-17 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Application-emitted metrics from every Go service and worker: instrument choice, boundaries, attributes, replay semantics and the fleet series budget |
| **Affected components** | `pkg/obsx` Views and helpers; `pkg/httpmw`, `pkg/grpcx` instruments; business metrics in every service; the Collector span-metrics connector's dimensions (via ADR-057); `docs/api/metrics.md` |
| **Related RFC** | [RFC-0031](../../rfc/RFC-0031/) |
| **Related research** | [research.md](../../rfc/RFC-0031/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0031 delivery plan Tasks 1.3, 4.2, 4.4 |
| **Adoption** | Complete — the fleet seconds View (obsx v0.42.0+), a UCUM unit on every business instrument (train #2, names unchanged 77 = 77), no identifier labels; registry declares 66 business instruments with unit and attributes |

## Context

Metrics already flow through the OTel Meter API and OTLP to VictoriaMetrics, and the
shared package pins one 13-bucket set for the HTTP and gRPC duration histograms via
an SDK View. The gaps are at the edges of that: a business histogram that matches no
View falls back to the SDK's millisecond-shaped defaults, so a sub-second operation
lands entirely in the first bucket and every quantile reads as zero while the
dashboard looks plausible — the state of two known seconds histograms today. Nothing
states which of the seven instrument types to use, an Observable Counter callback
that reports increments instead of totals silently corrupts every `rate()`, and
identifiers are kept out of labels by review rather than by test.

At fleet scale the binding constraint is total active series. Ten services emit
roughly 2,800 today, dominated by the bucketed histograms multiplied by route and
method; a thousand services with no budget is an ingest incident. The span-metrics
connector adds a further wrinkle: it declares `http.method`, a key the pinned
conventions have replaced, so its method dimension is empty for service spans.

## Scope

### In scope

- Instrument ownership by family and the two-question selection rule.
- The fixed fleet bucket set and the requirement that new seconds histograms declare
  boundaries.
- The attribute denylist, the per-service and fleet series budgets, and the
  no-exemplar statement.
- Temporal attempt-versus-outcome semantics and the replay rule.

### Out of scope

- The metrics store, scrape path or retention — unchanged.
- Span-derived RED dimensions — an amendment to ADR-057, tracked by RFC-0031 Task 4.4.
- Metric names as a registry — ADR-076.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Comparable quantiles | `histogram_quantile()` across services is only meaningful on identical boundaries |
| 2 | No silent failure | A wrong bucket set or a wrong callback produces a plausible dashboard; the rule must be checkable, not trusted |
| 3 | Series budget | Cardinality is a capacity problem before it is a cost problem |
| 4 | Replay safety | A Temporal replay that increments a counter double-counts a durable outcome |
| 5 | One automatic source per family | A handler that wraps an already-instrumented operation creates a second, disagreeing metric |

## Decision

We will keep automatic instrumentation as the only source for HTTP, gRPC, runtime,
database and cache metrics, and allow business metrics only for signals automatic
instrumentation cannot see, each recorded with question, owner, canonical dotted
name, instrument type, UCUM unit, bounded attribute allowlist, replay semantics,
consumer and removal plan. Instrument selection asks two questions in order —
additive? monotonic? — then sync versus async. The fleet bucket set
`0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5, 10` is pinned by the
shared View, which applies it to every histogram whose declared UCUM unit is `s` —
the named HTTP and gRPC instruments and any new one alike (amended 2026-09-23, see
History); non-time histograms choose a scale from an SLO or a
measured distribution and prove it with p50/p95/p99 queries.

Attributes are low-cardinality enums or normalised operation classes. The budget is
a per-service series ceiling set from the current measurement, a fleet ceiling equal
to the store's tested ingest capacity, and the SDK attribute-set limit as backstop.
Temporal metrics state attempts versus unique outcomes; workflow replay increments
nothing; durable business counters emit at the idempotent commit boundary. The
platform does not promise exemplars.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Shared middleware owns HTTP and gRPC RED, the runtime package owns runtime, shared adapters own DB and cache; a service adds no counter or histogram for an operation those already measure |
| **Selection** | Additive and monotonic → Counter; additive, non-monotonic → UpDownCounter; distribution → Histogram; last value → Gauge; known at decision → sync, sampled → Observable |
| **Async counters report totals** | An Observable Counter callback reports the cumulative value; reporting increments is a defect reviewed on every async counter |
| **Boundaries** | Every histogram declared with unit `s` receives the fleet set from the shared View, whatever its name; a histogram in another unit chooses a scale from an SLO or a measured distribution and proves it with p50/p95/p99 queries |
| **Names** | Application code declares the dotted OTel name and UCUM unit only; `_total`, `_bucket`, `_seconds` are ingest renderings |
| **Attributes** | No user, request, trace, span, workflow, run, order, cart, session, payment, SKU, promo, IP, raw URL, image SHA, pod UID, email or error text as a label |
| **Budget** | A new service is admitted with a series number; a dashboard shows fleet total against the ceiling |
| **Replay** | Workflow code increments no application metric; activities record attempts only when the name says attempt |
| **Temporality** | Cumulative at the SDK; the Collector's delta-to-cumulative processor is a defensive boundary, not the design |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — OTel Meter API through the shared provider, fixed fleet bucket set, allowlist and budget, explicit replay semantics** | Comparable quantiles; testable cardinality; one automatic source per family | New histograms must declare boundaries; budget needs a dashboard | Selected |
| **B — Preserve VictoriaMetrics as the only store with stricter contracts** | No backend change | None beyond A; stated for scope | Selected with A |
| **C — Prometheus `client_golang` directly in services** | Familiar | Second metrics API beside OTel; breaks the shared-package rule | Rejected |
| **D — Per-service bucket boundaries** | Local tuning | Cross-service quantiles meaningless; SLO precision varies per service | Rejected |
| **E — Move metrics into ClickHouse** | One analytical store | Out of RFC scope; PromQL consumers and Sloth SLOs depend on the TSDB | Rejected |

### Why the selected option won

It changes no backend and adds only rules that make the existing path checkable:
one bucket set, one selection rule, one denylist with a number attached.

### Why the closest alternative lost

Per-service boundaries are the current accidental state for business histograms, and
it is exactly what produces zero-valued quantiles on a plausible dashboard.

## Consequences

### Positive consequences

- Quantiles compare across every service; SLO recording rules share one shape.
- A cardinality violation fails a test, not a postmortem.
- Temporal counters mean what their names say.

### Negative consequences and accepted trade-offs

- Two known seconds histograms must be re-bucketed; their recording rules and SLOs
  re-baseline in the same release.
- Business metrics need a written record before they are emitted.
- No exemplars: metric-to-trace correlation stays metric → time window → logs →
  `trace_id`.

### Neutral consequences

- Ingest renderings of names are unchanged; dashboards keep querying rendered names.
- The span-metrics connector's dimension fix is tracked as an ADR-057 amendment.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Re-bucket the two known seconds histograms and re-baseline their SLOs | Owning services, Observability | RFC-0031 Task 1.3 | p50/p95/p99 queries return non-zero, plausible values |
| ~~Add the `forbidigo` rule for unbounded seconds histograms to the fleet policy~~ — replaced by the unit View (obsx v0.42.0) | `duynhlab/pkg` | RFC-0031 Task 1.3 | A histogram with an unfamiliar name and unit `s` gets the thirteen fleet boundaries in a reader test |
| Add cardinality allowlist tests to the shared package and services | `duynhlab/pkg`, service repositories | RFC-0031 Task 1.3 | Every forbidden identifier fails the test |
| Measure the per-service baseline and publish the budget dashboard | Observability | RFC-0031 Task 4.2 | Fleet total and ceiling visible in Grafana |
| Publish the as-built metrics contract | Platform docs | RFC-0031 Task 4.3 | `docs/api/metrics.md` matches deployment |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Bucket set | Metric-reader test asserts the fleet boundaries on HTTP, gRPC and every seconds histogram |
| Async totals | Table test feeds an Observable Counter two collections and asserts a non-negative delta |
| Cardinality | Allowlist test; a VictoriaMetrics query for any forbidden label returns no series |
| Replay | Temporal replay test proves no metric side effect; activity attempt metrics are named `attempt` |
| Budget | Series count per service ≤ ceiling in the Kind gate |
| Ownership | A handler-level duplicate RED metric fails review via the shared-package rule |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- VictoriaMetrics gains a supported exemplar workflow the platform wants to promise.
- The measured fleet series total approaches the store's tested ingest ceiling.
- An SLO demonstrably needs a boundary the fleet set cannot express.
- The registry in ADR-076 becomes the source of metric names and units.

A changed decision requires a new ADR that supersedes this one.

## References

- [RFC-0031](../../rfc/RFC-0031/) — § Metrics contract, § Fleet scale, § Observability & SLO impact
- [RFC-0031 research](../../rfc/RFC-0031/research.md)
- [ADR-057 — Span metrics in the Collector](../ADR-057-span-metrics-in-collector/)
- [ADR-063 — Temporal OTel v2](../ADR-063-temporal-otel-v2/)
- [Metrics contract (as-built)](../../../api/metrics.md)
- [Observability contract (as-built)](../../../api/observability.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-09-17 | Proposed / Not started | Drafted during RFC-0031 architecture review from § Metrics contract |
| 2026-09-17 | Accepted / Not started | Owner accepted with the RFC; created at `Accepted` per the RFC-0028/RFC-0030 precedent |
| 2026-09-23 | Accepted / Partial | **Amended.** The boundary rule moves from a lint to the type system of the metric itself: `obsx` v0.42.0 dispatches one View that applies the fleet set to every histogram whose unit is `s`, so a new instrument is correct by declaring `WithUnit("s")` rather than by remembering to pass thirteen numbers. The planned `forbidigo` rule is withdrawn — a regex over source cannot see an instrument built in a library, and the View covers the Temporal SDK and gRPC latencies a lint never would. The two known seconds histograms already carried the unit, so no service changed. Cardinality allowlist tests and the budget dashboard remain open |
| 2026-09-25 | Accepted / Complete | **Complete.** Train #2 put a unit on all 57 instruments that lacked one (annotation units, Prometheus names unchanged); the registry declares every instrument and the live-check rejects a unit or instrument that differs. |

---
_Last updated: 2026-09-25 — Adoption `Complete` at the close of RFC-0031 (both final gates passed). Previously Task 1.3 shipped in obsx v0.42.0: one View applies the fleet boundaries to every histogram declared in seconds, and the planned `forbidigo` rule is withdrawn. Previously 2026-09-17._
