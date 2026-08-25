# ADR-061: Route edge access logs to ClickHouse only, collect edge runtime logs

> **Decision summary:** We will drop the Envoy Gateway access-log stream from the
> VictoriaLogs leg of the collector's logs pipeline — ClickHouse becomes its only
> store — and start collecting the proxy's *runtime* logs into VictoriaLogs via a
> dedicated Vector source, because access logs are analytical records whose every
> real question (status distributions, latency percentiles, TraceId JOINs) is SQL,
> while runtime logs are the ops signal that today reaches no store at all. We
> accept that a ClickHouse outage leaves access logs with only the stdout
> fallback, and that the trace→log button is blank for edge spans.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-25 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Which store holds each class of Envoy Gateway log; not the access-log format, the OTLP sink, or the label guard — those stay as ADR-060 shipped them |
| **Affected components** | OTel Collector (logs pipelines), Vector, Envoy Gateway (`EnvoyProxy` logging level), VictoriaLogs, ClickHouse |
| **Related ADR** | [ADR-060](../ADR-060-envoy-access-log-transport/) — refined, not superseded: the OTLP transport and the `otlp-logs=true` guard are unchanged; this ADR changes the collector-side fan-out and adds the runtime branch |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | this ADR's PR |
| **Adoption** | **Complete** — measured on Kind 2026-08-25 during a full `make e2e GATE=kind` run: see [Verification](#verification-measured) |

## Context

ADR-060 put the edge's access logs on the OTLP road, and — because they ride the
collector's shared `logs` pipeline — they landed in **both** stores. Living with
that for a day exposed three facts:

1. **The VictoriaLogs copy is the low-value copy.** The access log's JSON keys
   map to log-record *attributes*, not a body — VictoriaLogs renders
   `missing _msg field` and free-text search can never see them. Every real
   question asked of these records is analytical: status distribution, latency
   percentiles, 429-by-client, and above all the `JOIN otel_traces ON TraceId`
   that only ClickHouse can answer.
2. **It is the noisiest OTLP log stream** — 5,941 records/6h under a k6 gate
   run — on a VLSingle that has already been OOMKilled by log volume once
   (see the memory-limit note in `vlsingle.yaml`).
3. **The pod-level exclusion silenced a signal nobody meant to drop.** The
   `otlp-logs=true` label removes the *whole* proxy pod from Vector, but only
   the access log has an OTLP sink — Envoy's **runtime** logs (startup, config
   rejects, upstream warnings) were collected nowhere. Verified live: a real
   `gRPC config: initial fetch timed out` warning on stdout, zero records for
   it anywhere in VictoriaLogs. Envoy offers no export for component logs
   (`ProxyLogging` sets levels only), so the fix must be on the reading side.

Edge alerting is unaffected by any of this: all `Edge*` alerts stand on
`envoy_*` metrics, not logs. No dashboard and no k6 gate row reads edge access
logs from VictoriaLogs (verified by grep across both repos and
`scripts/k6/observability.js`).

## Decision

Redefine the routing per log class:

| Edge log class | Character | Store | Path |
|---|---|---|---|
| **Access log** (request records, TraceId) | high-volume, structured, analytical | **ClickHouse only** (90d, JOINs `otel_traces`) | OTLP sink → collector; `filter/drop_edge_logs` removes it from the VictoriaLogs pipeline |
| **Runtime log** (proxy process) | sparse, textual, ops | **VictoriaLogs** (7d) | new Vector source scoped to the proxy pods, keeping only non-JSON lines |
| **Controller log** | sparse, ops | VictoriaLogs (unchanged) | Vector |
| **stdout** (File sink) | incident fallback | no store | `kubectl logs` (unchanged) |

Mechanics — three manifests, no new components:

- **Collector** (`kubernetes/infra/controllers/tracing/otel-collector/otel-collector.yaml`):
  the single dual-export `logs` pipeline splits in two. The **key name `logs`
  is deliberately kept** for the VictoriaLogs leg (it gains
  `filter/drop_edge_logs`, an OTTL condition on
  `resource.attributes["service.name"] == "platform.envoy-gateway"`), and
  `logs/clickhouse` is added (receives everything). The `otlp` receiver fans
  out to both; each pipeline gets its own copy. Keeping the key matters:
  chart 0.170.0 ships a **default `logs` pipeline (exporters: `[debug]`)** and
  helm deep-merges values over defaults — during the live gate, renaming our
  pipeline away from `logs` resurrected the chart default within one upgrade
  (verified by unpacking the chart; its own `values.yaml` documents the
  null-removal helm bug). Same-key shadowing is how `metrics` and `traces`
  already suppress their defaults.
- **Vector** (`kubernetes/infra/controllers/logging/vector/vector.yaml`): a
  second `kubernetes_logs` source with
  `extra_label_selector: "gateway.envoyproxy.io/owning-gateway-name"` — an
  *existence* selector that matches only EG proxy pods, never the app pods
  that also carry `otlp-logs=true` — feeding a filter that keeps only lines
  not starting with `{`. The discriminator is our own declared contract:
  access logs are the JSON format in `envoyproxy.yaml`; runtime lines start
  `[ts][level][component]`.
- **EnvoyProxy** (`kubernetes/infra/configs/envoy-gateway/envoyproxy.yaml`):
  `spec.logging.level.default: warn` pinned explicitly — unset, stdout carried
  `[debug]` lines; now that runtime lines are stored, volume is bounded at the
  source.

## Consequences

- **Access logs lose the dual store.** During a ClickHouse outage the only
  record of that window is the pod's stdout (the ADR-060 File sink, which this
  ADR deliberately keeps). Acceptable here because edge alerting stands on
  metrics and the collector's `sending_queue`/`retry_on_failure` absorb short
  gaps.
- **`tracesToLogsV2` is blank for edge spans** — the span's Logs tab points at
  VictoriaLogs, which no longer holds the edge's request records. The
  replacement is the ClickHouse dashboard suite's native TraceId JOIN (already
  deployed). App spans are untouched.
- A new class of records appears in VictoriaLogs: the proxy runtime stream
  (its `service` stream field falls back to the pod name — proxy pods carry no
  `app` label).
- If the access-log format ever changes to a Text format starting with `[`,
  the Vector runtime filter would start double-storing those lines — the
  format is our own declared contract, and the manifests now say so at both
  ends.
- Docs and query guides move the edge's request-log examples from LogsQL to
  SQL (`docs/observability/logging/`, this PR).

## Verification (measured)

Measured on the live Kind cluster, 2026-08-25, with the change applied and a
full `make e2e GATE=kind` suite as the traffic source (raw evidence in the
implementing PR):

1. VictoriaLogs received **0** new edge access-log records across the whole
   gate window (baseline 15:55:05Z → 16:08Z), while three tagged probe
   requests before the gate were each confirmed dropped by
   `otelcol_processor_filter_logs_filtered` (3 → 6) and present in ClickHouse
   (exactly 3 — no double-write).
2. ClickHouse `otel.otel_logs` edge rows grew **181 → 453** over the gate.
3. The proxy runtime stream holds **93** records in VictoriaLogs (Envoy
   startup/config lines captured across proxy restarts — the class that was
   previously collected nowhere) with **0** access-log records inside it
   (word `response_flags` in that stream: 0 hits).
4. Application logs kept flowing to **both** stores and stayed in parity:
   **146 → 211** in VictoriaLogs and **146 → 211** in ClickHouse.
5. The edge-log ↔ span `JOIN … ON TraceId` returned the gate's own requests
   (e.g. `DELETE /cart/v1/private/cart`, request_id `b57f7423…`, span 570ms).
6. k6: saga 4/4 rows (9/9 assertions), staff and operator suites pass; smoke
   15/15 on re-run (first run 14/15 — `K5.5 Temporal SDK has series`, a
   post-node-restart timing flake unrelated to log routing: 72 `temporal_*`
   series were present on immediate re-check).

---

_Last updated: 2026-08-25 — initial decision, shipped with its implementation._
