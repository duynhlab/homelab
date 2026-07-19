# ADR-023: Adopt ClickHouse as supplementary OLAP for OTel logs+traces SQL

Add ClickHouse as a long-retention SQL store for observability logs and traces,
alongside the existing ops primaries.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-19 | [RFC-0019](../../rfc/RFC-0019/) | [RFC-0019 research.md](../../rfc/RFC-0019/research.md) |

> **Every decision is a tradeoff.** We accept a new stateful backend to operate in
> exchange for long-retention, cross-signal SQL that the ops primaries cannot give.

## Context

VictoriaLogs, Tempo, and the VictoriaTraces pilot all cap at **7-day** retention and
answer **LogsQL/TraceQL only** — there is no cross-day **SQL/OLAP** over structured
log/trace fields (errors by service over N weeks, duration percentiles, status mixes),
and no way to **JOIN** logs↔traces in one store on `trace_id`. RED metrics on
VictoriaMetrics do not substitute for log/trace search. Because everything is
instrumented with **OpenTelemetry** (the vendor-neutral "narrow waist"), a new backend
is a **collector-exporter change, not an app change**. RFC-0019 framed this; the owner
chose to implement **Phase B (observability) for real**, dropping Phase A (commerce).

## Decision

We will adopt **ClickHouse** as a **supplementary OLAP backend for logs and traces only**,
deployed via the **Altinity `clickhouse-operator`** + a `ClickHouseInstallation` CR
(1 shard × 1 replica). The OTel Collector **fans out** (dual-writes) logs and traces to
ClickHouse `otel_logs` / `otel_traces` **alongside** VictoriaLogs / Tempo / VictoriaTraces
(kept as day-to-day ops primaries) via the contrib `clickhouse` exporter (`create_schema`
bootstraps the MergeTree tables). **Metrics stay on VictoriaMetrics — never ClickHouse.**

- **Storage:** local PVC (`standard`); **retention:** `ttl 90d` (vs 7d ops).
- **Query:** the Grafana `grafana-clickhouse-datasource` plugin (SQL panels/Explore).
- **Analytics model:** *logs-first* — `otel_logs` (100%, unsampled) is the counting
  workhorse; `otel_traces` (head-10% sampled) are exemplars joined on `trace_id`.
- **No app/service code change** (`pkg/obsx` / `pkg/grpcx` untouched).
- Gated the same way as everything: the **local-stack e2e audit must pass** before Kind.

## Alternatives considered

- **VictoriaLogs/Tempo only** — zero new infra, but no long-retention cross-signal SQL. Lost.
- **ClickStack / HyperDX** — all-in-one UI, but an extra stack, not GitOps-native here. Lost.
- **Raise retention on VLogs/Tempo** — still LogsQL/TraceQL, not SQL/OLAP, and costlier on
  those engines. Lost.
- **Official ClickHouse operator** — Cloud-aligned but younger on Kind; **Altinity** chosen for
  Kind maturity (RFC-0019).
- **Consistent-probability sampling now** (adjusted-count trace analytics) — deferred; not needed
  for logs-first. Revisit if trace-count accuracy becomes a requirement.

## Consequences

**Gain:** long-retention (90d) SQL over logs+traces; cross-signal `trace_id` JOIN in one store;
no app change; an upstream-standard exporter; ops primaries untouched.

**Accept (the cost):**
- A new **stateful backend** to run/patch/Kyverno-harden (single-replica pilot, PVC — no HA;
  bump resources when going real, per owner).
- The single OTel Collector gains a **4th trace + 2nd log sink**. `sending_queue` +
  `retry_on_failure` + bumped `memory_limiter`/limits absorb **runtime** backpressure, but
  `create_schema` runs DDL in the exporter's `start()`, so an unreachable ClickHouse fails
  the **whole collector at startup** (taking the other sinks with it). Mitigated by ordering
  ClickHouse first — local-stack `depends_on: service_healthy`, cluster `tracing-local
  dependsOn clickhouse-local`. This guards cold-start only; a collector restart while
  ClickHouse is down still crash-loops. Full decoupling (when past pilot) = `create_schema:
  false` + a schema-bootstrap Job.
- **Access control:** no public Ingress; the `default` password is the control. **Not**
  NetworkPolicy-fenced — `monitoring` gets no Kyverno default-deny and netpol is inert on
  kindnet; a `:9000`/`:8123` NetworkPolicy is a follow-up for an enforcing CNI.
- Trace analytics see only the **10% head sample**; `otel_traces` counts undercount — mitigated
  by the logs-first model (and a future consistent-probability upgrade if needed).
- A ClickHouse **password** to manage (ESO/OpenBAO in-cluster; dev inline in local-stack).

## Related

- [RFC-0019](../../rfc/RFC-0019/) · [research.md](../../rfc/RFC-0019/research.md)
- [clickhouse/README.md](../../../observability/clickhouse/README.md) (operational guide)
- [stack-review.md](../../../observability/stack-review.md) (the gaps this closes)
