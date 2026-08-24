# Grafana Tempo

> **Archived (RFC-0027, 2026-08-24) — kept deliberately as learning material.**
> This consolidates what the platform learned from running Grafana Tempo, which it
> ran **twice** — once from hand-written manifests and once from the
> `grafana-community/tempo` Helm chart. The live trace stores are
> [**VictoriaTraces**](victoriatraces.md) (7 days) and **ClickHouse** (90 days,
> SQL). The body below is **frozen history** — never updated; the manifests it
> describes now live beside their directories as `*.yaml.bak`.
>
> Decisions: [ADR-059](../../proposals/adr/ADR-059-retire-tempo/) retired both
> installs; [ADR-057](../../proposals/adr/ADR-057-span-metrics-in-collector/) moved
> the RED span metrics out first, because that was the prerequisite.

## Why we left (known problems)

Recorded so the reasons survive the removal
([RFC-0027](../../proposals/rfc/RFC-0027/README.md) has the full analysis):

- **The delivery question never landed — twice.**
  [ADR-032](../../proposals/adr/ADR-032-tempo-operator-monolithic/) proposed the
  `tempo-operator`, was `Withdrawn` in favour of
  [ADR-040](../../proposals/adr/ADR-040-tempo-community-helm-chart/), and ADR-040
  itself sat at `Proposed` with no decision date. Two records about *how* to run
  Tempo, neither resolved. The third record about Tempo retired it.
- **Two installs, one store.** Both received the same spans through the same
  collector fan-out and wrote to two different RustFS buckets. Two copies over the
  same 7-day window answer no question one copy cannot.
- **It made a signal hostage.** The chart install's `metrics_generator` was the
  only live producer of RED span metrics, which the SLO and Apdex arithmetic
  consume. That single fact made Tempo unremovable until the metric was moved.
- **It doubled the load on a flapping component.** RustFS took writes from four
  producers, two of them this pair, while restarting under its own liveness probe —
  11 restarts in 3h12m with CPU throttling measured at 0.0.
- **The two E2E gates measured different platforms.** local-stack never ran Tempo;
  it derived the same class of metrics with the collector's `span_metrics`
  connector. The Kind gate's K5.5 row therefore recorded the spanmetrics leg as
  *N/A on the cluster*.

## The trap worth remembering: two installs were not two copies

They looked interchangeable. Exactly one difference mattered.

| | Tempo (hand-written manifests) | Tempo (Helm chart) |
|---|---|---|
| Bucket | `tempo-traces` | `tempo-chart-traces` |
| `metrics_generator` | declared but **inert** — `remote_write: []` | **enabled** → vmagent, `send_exemplars: true` |
| Processors | — | `service-graphs` + `span-metrics` |
| Scraped by | `ServiceMonitor/tempo`, selector `app: tempo` | `serviceMonitor.enabled: false` |

Two consequences followed from that table, and both are the kind of thing that
fails quietly:

- **`TempoDown` only ever watched one of them.** It alerted on
  `up{job=~".*tempo.*"}`, and the only scrape producing that label selected
  `app: tempo` — the hand-written install. Had the raw install been removed while
  the chart stayed, the alert would have had **zero series**: loading cleanly,
  never firing, and reading as healthy forever. Removing *both* is what made
  deleting the alert the correct action rather than a hidden regression.
- **Nothing consumed what the live generator produced.**
  `grep -rE "traces_spanmetrics|traces_service_graph" kubernetes/` returned
  nothing — no dashboard, alert or recording rule. A producer with no consumer.

## What Tempo's metrics-generator did

It derived two families of metrics from spans, inside Tempo, after storage:

- **Span metrics** — RED per service and operation. Replaced by the collector's
  `span_metrics` connector ([ADR-057](../../proposals/adr/ADR-057-span-metrics-in-collector/)),
  which produces `spanmetrics_calls_total` and `spanmetrics_duration_*` before any
  store is involved.
- **Service graphs** — metrics about *edges*: `traces_service_graph_request_total{client, server}`,
  plus failure counters and latency histograms measured from both the client and
  the server side. Derived by pairing a parent span of kind `client` with its child
  span of kind `server`.

Service graphs are the more interesting loss, because span metrics cannot replace
them: span metrics answer *"how is service X doing"* and have already aggregated
away *who called whom*. That pairing cannot be recovered from the aggregate.

What replaced it is **not** a metrics producer. VictoriaTraces serves the Jaeger
dependency-graph API at `/select/jaeger/api/dependencies` behind
`-servicegraph.enableTask`, and Grafana's `jaeger` datasource has a native
**Dependency graph** query type that renders it as a Node Graph. That yields
topology and call counts but not per-edge failure or latency; where those are
needed, the spans themselves are still in ClickHouse for 90 days and a self-join
recovers the full picture. The trade and the rejected alternatives are recorded in
[ADR-059](../../proposals/adr/ADR-059-retire-tempo/).

## What was kept from the experience

- **A backend swap is a collector-exporter change, not an app change.** The removal
  surface touched **no file** under `kubernetes/apps/` — no service redeploy, no
  `pkg` bump. That is [ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/)'s
  principle proving itself in the removal direction.
- **Derive signals before storage, not inside it.** Any metric an SLO depends on
  should be produced by something whose lifetime is independent of a storage choice.
- **Count a removal surface with care.** `grep -rli tempo kubernetes/` returned
  **94** files. The number that mattered was **38**, because "tempo" matches inside
  both *Tempo**ral*** and *"**tempo**rarily"* — and of those 38, only 23 carried
  live configuration.

## References

- [RFC-0027](../../proposals/rfc/RFC-0027/README.md) — the retirement decision and its rollout
- [RFC-0027 research](../../proposals/rfc/RFC-0027/research.md) — measurements and Context7 audit
- [ADR-057](../../proposals/adr/ADR-057-span-metrics-in-collector/) · [ADR-059](../../proposals/adr/ADR-059-retire-tempo/)
- [VictoriaTraces](victoriatraces.md) · [tracing hub](README.md)
- [`docs/platform/kong-gateway.md`](../../platform/kong-gateway.md) — the archived-doc pattern this follows

---
_Last updated: 2026-08-24 — archived; frozen at retirement._
