# Streaming Aggregation — the at-scale metrics playbook

How a metrics pipeline survives 1000+ microservices: aggregate series **in
flight** — before they ever become storage cardinality — instead of paying to
store per-instance data nobody queries. This is the playbook layer above
[app-side cardinality control](metrics-apps.md#app-side-cardinality-control):
app hygiene bounds *what one replica emits*; streaming aggregation bounds *what
the fleet costs*.

| | |
|---|---|
| **Status** | **At-scale playbook** — shadow pilot per [RFC-0013](../../proposals/rfc/RFC-0013/README.md) P3; **not** the default pipeline in this homelab |
| **Engine** | vmagent / VictoriaMetrics single-node streaming aggregation |
| **Config surface** | `VMAgent` CR `remoteWrite[].streamAggrConfig` (VM Operator) |
| **Problem it solves** | Per-instance label cardinality × replicas × churn at fleet scale |
| **Cost model** | State in aggregator RAM per active window; storage sees only aggregated outputs |
| **Trigger** | Per-instance labels dominate active series AND fleet-level queries dominate usage |

---

## Overview

A Prometheus-model TSDB does not price metrics — it prices **time series**: one
per unique `metric name + label set`. Every scaling problem in a metrics
pipeline is ultimately this multiplication getting out of hand:

```
series ≈ Σ over services ( replicas × label-combinations × series-per-combination )
```

App-side hygiene (route templates, bounded labels, no request-scoped IDs —
see [metrics-apps.md](metrics-apps.md)) keeps *label-combinations* bounded.
But two factors are **not** controllable in application code:

1. **`instance` (and `pod`)** — injected by the scrape layer, one value per
   replica. It multiplies every app series by the replica count, and every
   deploy/restart mints a fresh set (churn).
2. **Fleet size** — 10 services + 2 workers today; a large platform runs hundreds to
   thousands.

At fleet scale, almost every operational question is asked at the
service/route level ("which service is erroring", "which endpoint is slow"),
not per pod. The per-instance dimension is paid for on **100% of series** and
queried on **~1%** of them. Streaming aggregation removes that dimension in
the pipeline — the raw samples are aggregated in memory over fixed windows and
only the aggregated series reach storage.

## The cardinality math

### What one replica of this platform actually emits

Measured from the running local-stack (Prometheus text endpoint, one replica
each, real traffic; lazy label instantiation means these grow toward the
worst-case bound as more route×status combinations are hit):

| Service | Series/replica (measured) | Notes |
|---|---|---|
| cart | 720 | most route×code combos materialized |
| product | 530 | + 51 `rpc_client_*` (gRPC → review) |
| notification | 410 | |
| auth | 392 | |
| order | 382 | + 76 `temporal_*` SDK series |
| user | 135 | |
| shipping | 83 | gRPC-only traffic → HTTP combos not yet materialized |
| review | 66 | 〃 |
| payment | 49 | 〃 |
| **Σ (apps, 1 replica each)** | **2,777** | |

Worst-case bound per replica for the fleet-standard middleware
(~12 non-infra routes × ~4 status codes = ~48 combos):

```
http_server_request_duration_seconds       : 48 combos × (14 bucket lines + _sum + _count) ≈ 768
http_server_(request|response)_body_size_bytes : 48 combos × (6 bucket lines + _sum + _count) × 2 ≈ 768
(http_server_active_requests)               : not emitted — otelgin v0.69 has no in-flight gauge
go_* / process_* runtime                    : ~250
                                            ≈ 1,800 series / replica worst-case
```

### The same math at fleet scale

Take a conservative production shape — 600 realized series per replica
(between our measured ~400 median and the 1,800 bound), 15s scrape:

| Fleet | Replicas | Active series (raw) | Samples/s (raw) | Active series with `instance` stripped |
|---|---|---|---|---|
| **Measured 9-service snapshot (2026-07-06)** | 1–2 | ~3k | ~200 | ~2.5k — *pointless, the multiplier is 1–2* |
| 100 services | ×5 | ~300k | ~20k | ~60k |
| 1,000 services | ×10 | **~6M** | **~400k** | **~600k** |
| 1,000 services + deploy churn | ×10, daily rollouts | 6M *active* + millions of stale-but-indexed | — | churn disappears too: aggregated series carry no per-pod identity |

Two things break first as the raw column grows:

- **Storage/index RAM** scales with *active + recently-churned* series. Rolling
  restarts of 10,000 pods mint 10,000 × 600 new series while the old ones age
  out of the index.
- **Query cost** scales with series touched: `sum by (app)` over 6M raw series
  fans in 6M points per step *at query time* — on every dashboard refresh.

The insight behind in-flight aggregation, proven publicly at shops running
100M+ samples/s: **do that `sum without (instance)` once, in the pipeline,
instead of on every query** — and never let the per-instance series reach the
TSDB at all.

## Why the familiar tools don't solve this

| Approach | Why it falls short at scale |
|---|---|
| **Recording rules** (our `app:*`) | Evaluated *after* ingestion — storage already paid for the raw series; the rules **add** series on top. Rule evaluation itself fans in the full raw cardinality every interval. Right tool at small scale; a cost *amplifier* at large scale. |
| **Relabel-dropping `instance`** | Aggregation-by-deletion is wrong: two replicas' samples collide into one series with conflicting values (last-write-wins garbage). Dropping is only safe for series you discard entirely. |
| **Scaling storage horizontally** (cluster/Thanos/Mimir) | Pays to store cardinality that has no readers. Necessary eventually for HA/retention — but it scales the *bill*, not the signal-to-noise. |
| **StatsD-style client aggregation** | Moves aggregation into app processes and a bespoke protocol; loses the pull model, per-replica health (`up`), and exemplars. |

Streaming aggregation composes with — not replaces — the first and third: keep
recording rules for query-shaping on already-small series, keep clustered
storage for HA, and use streaming aggregation to control what enters storage.

## How streaming aggregation works

vmagent (and single-node VictoriaMetrics) can apply aggregation rules on the
**remote-write path**: samples matching a rule are folded into in-memory
aggregation state; every `interval` the state flushes as new output series.

```yaml
- match: 'http_server_request_duration_seconds_bucket'  # series selector
  interval: 1m                               # aggregation window
  without: [instance, pod]                   # labels to aggregate away
  outputs: [total]                           # aggregation function(s)
```

Output naming is collision-proof by construction:
`http_server_request_duration_seconds_bucket:1m_without_instance_pod_total` — the raw
series (if kept) and the aggregate can coexist.

### Choosing outputs by metric type

The output function must match the metric's semantics — this is the single
most common mistake:

| Metric type | Correct outputs | Wrong (and why) |
|---|---|---|
| Counter (`*_total`, histogram `_bucket`/`_count`/`_sum`) | `total` (cumulative, counter-reset aware) or `increase` | `sum_samples` — sums raw cumulative values, produces garbage across resets/restarts |
| Gauge (queue depth, active connections) | `avg`, `max`, `min`, `last` | `sum`/`total` — the sum of point-in-time gauges across replicas is meaningful only if you truly want fleet total; `total` treats them as counters |
| Latency distribution | aggregate the existing histogram series with `total`, or `quantiles(...)`/`histogram_bucket` on raw values | per-replica percentiles averaged together — percentiles don't average |

### Histogram invariants

A histogram is one logical object spread over many series. Aggregating it has
two hard rules:

1. **`_bucket`, `_count`, `_sum` must use the same `without` list** — otherwise
   `histogram_quantile()` gets buckets and counts with mismatched label sets
   and returns NaN or lies.
2. **All `le` buckets of one histogram must reach the same aggregator** —
   never shard series by `le` (or `vmrange`) across aggregator instances.

## Architecture at scale — the two-tier pattern
This is a **reference architecture, not a deployed or committed target** for
the current homelab.


One aggregator can't hold fleet state, and a load balancer in front of N
aggregators is *wrong*, not just slow: aggregation is stateful, and correctness
requires **all samples of one output series to meet in one process**. The
solution is deterministic sharding — a stateless router tier that consistent-
hashes series onto a stateful aggregator tier, ignoring exactly the labels the
aggregators will strip:

```mermaid
flowchart LR
    subgraph Apps["Reference scale · not deployed"]
        A1["1000+ services × N replicas<br/>(reference workloads)"]
    end
    subgraph T1["Tier 1 · reference only"]
        R1["vmagent router-1<br/>(reference)"]
        R2["vmagent router-2<br/>(reference)"]
    end
    subgraph T2["Tier 2 · reference only"]
        G1["vmagent aggr-0<br/>without [instance, pod]<br/>(reference)"]
        G2["vmagent aggr-1<br/>without [instance, pod]<br/>(reference)"]
    end
    ST[("VictoriaMetrics cluster<br/>(reference)")]
    A1 -.->|"reference: scrape / OTLP push"| R1 & R2
    R1 & R2 -.->|"reference: remote write + shardByURL<br/>ignoreLabels: instance, pod"| G1 & G2
    G1 & G2 -.->|"reference: aggregated series only<br/>dropInput on matched raw"| ST

    classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;
    class A1,R1,R2,G1,G2,ST planned;
```

Invariants that make this correct (each maps to a real failure mode):

- **Shard key = the labels you keep.** Routers hash with
  `-remoteWrite.shardByURL` + `shardByURL.ignoreLabels=instance,pod` so all
  replicas of `{app="cart", path="/cart/v1/..."}` land on the same aggregator.
  The `ignoreLabels` set must be a superset-match of the aggregators'
  `without` list, or one output series gets computed twice with partial data.
- **No load balancer between tiers** — routing must be hash-deterministic.
- **Aggregators are individually addressed** (StatefulSet + headless DNS, one
  remote-write URL per pod from the routers).
- **One `le` never splits** — follows from hashing on kept labels only.
- **Each aggregator stamps a unique label** if its outputs could otherwise
  collide with a peer's.
- **Scale-out reshuffles shards** — adding an aggregator remaps series mid-
  window; expect one blip of partial aggregates (same class of event as an
  aggregator restart).

### What one aggregation window does

```mermaid
sequenceDiagram
    participant R as Router (tier 1)
    participant A as Aggregator (tier 2)
    participant S as Storage
    R->>A: samples for {app="cart", instance="pod-a"} = 10
    R->>A: samples for {app="cart", instance="pod-b"} = 12
    Note over A: fold into in-memory state<br/>keyed by labels minus [instance, pod]
    A->>S: flush at interval boundary:<br/>cart:1m_without_instance_pod_total = 22
    Note over A: state is RAM-only —<br/>restart mid-window loses that window
```

Consequences to design for:

- **Restart = lost partial window** (and first window after start is skipped).
  Acceptable for trends; why SLO-critical alerting should tolerate a
  one-interval gap, and why `flush_on_shutdown` exists for graceful restarts.
- **Late samples** past `staleness_interval` are dropped from aggregation —
  keep `interval ≥ 2× scrape interval` and watch the lag self-metrics.
- **Dedup before aggregation** (`dedup_interval`) is how HA scrape pairs avoid
  double-counting into the fold.

## When do you need this?

```mermaid
flowchart TD
    Q0["Metrics bill / TSDB RAM growing?"] -->|no| N0["You don't need this.<br/>Keep app-side hygiene + recording rules."]
    Q0 -->|yes| Q1["Are labels bounded app-side?<br/>(route templates, no IDs)"]
    Q1 -->|no| F1["Fix instrumentation first —<br/>aggregating garbage stores less garbage,<br/>but it's still garbage"]
    Q1 -->|yes| Q2["Is the growth driven by<br/>instance/pod × replicas × churn?"]
    Q2 -->|no| F2["Different problem:<br/>drop unused metrics via relabeling,<br/>lengthen scrape interval, downsample"]
    Q2 -->|yes| Q3["Do you still need<br/>per-instance queries on these metrics?"]
    Q3 -->|"yes, routinely"| F3["Keep raw; pre-shape queries<br/>with recording rules; revisit later"]
    Q3 -->|"rarely / debug-only"| F4["Streaming aggregation:<br/>1) shadow (keepInput)<br/>2) verify vs recording rules<br/>3) cut consumers over<br/>4) dropInput on matched raw"]
    F4 --> Q4["Single vmagent can't hold state /<br/>needs HA?"]
    Q4 -->|yes| F5["Two-tier: router shard tier +<br/>aggregator StatefulSet tier"]
    Q4 -->|no| F6["Single vmagent streamAggr<br/>(this homelab's pilot shape)"]

    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    class Q0,Q1,Q2,Q3,Q4 metric;
    class F4,F5,F6 data;
    class N0,F1,F2,F3 platform;
```

The homelab today answers the *first* question with "no" (~3k app series,
VMSingle idles) — which is exactly why the pilot below is scoped as a
**learning shadow**, not a cost fix. The playbook exists for the day the
answer flips, and for platforms where it is already "yes".

## How it works in this platform (pilot shape)

The homelab's app metrics now arrive by **OTLP push** (`obsx SDK →
otel-collector → vmagent OTLP ingest → VMSingle`; the per-app `/metrics` scrape
was retired in RFC-0014 P3). Streaming aggregation lives on vmagent's
remote-write path, so it applies regardless of how samples enter. The VM
Operator exposes it declaratively on the `VMAgent` CR, so
the pilot is a GitOps-only change to
[`vmagent.yaml`](../../../kubernetes/infra/configs/observability/metrics/victoriametrics/vmagent.yaml)
— no new components, no router tier (one vmagent = one aggregator = the
sharding invariants hold trivially):

```yaml
# kubernetes/infra/configs/observability/metrics/victoriametrics/vmagent.yaml (pilot, RFC-0013 P3a)
spec:
  remoteWrite:
    - url: "http://vmsingle-victoria-metrics.monitoring.svc:8428/api/v1/write"
      # SHADOW mode: aggregated series are ADDED next to raw ones.
      # keepInput default (true-equivalent: no dropInput) — Sloth SLOs,
      # recording rules, dashboards keep reading raw series untouched.
      streamAggrConfig:
        rules:
          # Fleet-level RED without per-replica identity. App series arrive
          # via OTLP push (no `job`/`instance` label; the per-replica label is
          # `k8s_pod_name` from the OTLP resource), so select on `app` and
          # strip `k8s_pod_name`.
          # One rule covers _bucket/_count/_sum -> same `without` list,
          # preserving histogram_quantile() on the aggregated set.
          - match: '{__name__=~"http_server_request_duration_seconds(_bucket|_count|_sum)", app!=""}'
            interval: 1m
            without: [k8s_pod_name]
            outputs: [total]
          # The in-flight gauge rule was dropped: otelgin (v0.69) emits no
          # active-requests metric, so `requests_in_flight` no longer exists
          # after the RFC-0014 P3 cutover.
```

What this yields in VMSingle, next to the raw series:

```
http_server_request_duration_seconds_bucket:1m_without_k8s_pod_name_total{app="cart", http_route="...", le="0.5"}
http_server_request_duration_seconds_count:1m_without_k8s_pod_name_total{app="cart", http_route="..."}
```

These are the same shapes the `app:*` recording rules compute after
ingestion — which is the point: the shadow phase compares the two for
equivalence before any consumer is switched (RFC-0013 P3b).

## Operations

### Enable / disable

Enable: add `streamAggrConfig` to the remote-write entry in the `VMAgent` CR →
`make flux-push && make flux-sync`. Disable: revert the commit. Raw series are
never touched in shadow mode, so rollback has zero blast radius.

### Watch the aggregator itself

vmagent exports self-metrics for the aggregation stage (already scraped via
the flux-system/monitoring pipeline):

| Metric | Meaning / alarm condition |
|---|---|
| `vm_streamaggr_matched_samples_total` | Samples entering aggregation — flat at 0 = rules match nothing |
| `vm_streamaggr_flushed_samples_total` | Output samples per flush — gaps = missed windows |
| `vm_streamaggr_ignored_samples_total{reason="too_old"}` | Late samples dropped — rising = pipeline lag vs `interval` |
| `vm_streamaggr_dedup_dropped_samples_total` | Duplicates removed pre-fold |
| `vm_streamaggr_samples_lag_seconds` (histogram) | Ingestion delay distribution — keep p99 ≪ `interval` |

### Pitfall checklist

| Pitfall | Guard |
|---|---|
| `sum_samples` on counters | Use `total`/`increase`; watch counter-reset self-metrics |
| Histogram `_bucket`/`_count`/`_sum` with different `without` | One rule (regex match) covering all three |
| Sharding by `le` across aggregators | Hash only on kept labels (single aggregator: N/A) |
| LB in front of aggregators | Individually addressed StatefulSet pods |
| Restart loses window | `flush_on_shutdown: true` for graceful; alerts tolerate 1-interval gap |
| Aggregated output colliding with raw names | Never set `keep_metric_names` in shadow mode |
| `dedup.minScrapeInterval` (storage) vs `dedup_interval` (aggregation) mismatch | Align both when HA-duplicating |
| Catch-all `match` eating RAM | Match exact metric families only; budget state = active input series |

## References

- VictoriaMetrics — [Streaming aggregation](https://docs.victoriametrics.com/victoriametrics/stream-aggregation/)
- VictoriaMetrics — [vmagent](https://docs.victoriametrics.com/victoriametrics/vmagent/) (`remoteWrite.shardByURL`, `shardByURL.ignoreLabels`)
- VictoriaMetrics Operator — [API: `StreamAggrConfig` / `StreamAggrRule`](https://docs.victoriametrics.com/operator/api/)
- In-repo: [metrics hub](README.md) · [metrics-apps.md](metrics-apps.md) · [RFC-0013](../../proposals/rfc/RFC-0013/README.md)

---
_Last updated: 2026-07-14 — re-pointed the pilot to semconv/OTLP metric names (RFC-0014 P3); app path is OTLP push, not scrape._
