# ADR-016: Metrics cutover to the OTLP push pipeline

Retire the scrape pipeline for the nine platform services: the OTLP-path
rules, SLOs and dashboard become canonical, the apps' ServiceMonitor shrinks
to a `legacy-checkout` fence, and the order-worker PodMonitor is deleted.

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-09 | [RFC-0014](../../rfc/RFC-0014/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

RFC-0014 P1/P2 left both pipelines running: every service dual-emitted
(client_golang scrape + semconv OTLP push) and every consumer existed twice —
scrape-era alerts/rules/SLOs/dashboard beside the new-name copies routed to a
staging receiver. The RFC's production plan called for a ≥1-week soak; this
platform is a learning environment with no 24/7 deployment, so the owner
decided to **replace immediately** after the copies were verified against
live local-stack data (all expressions executed against real OTLP series;
old-vs-new p95/Apdex/error-ratio agreed; the full checkout saga exercised the
gRPC and Temporal paths).

Two facts discovered during verification shaped the cutover:

- **Temporal metric names are identical on both paths** (`temporal_workflow_*`,
  `temporal_activity_*`, `temporal_worker_task_slots_*` — verified against a
  live saga run), so the worker's PodMonitor can retire without touching the
  Temporal dashboard.
- Two scrape-era signals have **no OTLP successor** (otelgin v0.69 emits no
  `http.server.active_requests`; the OTel Go runtime has no GC-pause metric)
  — their alerts retire with the scrape rather than survive on dead sources.

## Decision

One homelab commit swaps the pipeline end to end:

1. **ServiceMonitor `microservices-api` → `legacy-checkout`** (D-13): scoped
   to the `checkout` namespace only, keeping `job="microservices"` so the
   fenced scrape-era alert group still evaluates for the exempt service. The
   fence pre-exists checkout's deployment; its retirement condition (checkout
   adopts obsx, or is decommissioned) is documented on the object.
2. **PodMonitor `order-worker` deleted** — the worker pushes OTLP like every
   other service; its Temporal metrics keep their names.
3. **The P2 copies become canonical**: `alerts-otel.yaml`/`recording-rules-
   otel.yaml` renamed over the deleted legacy files; the `Otel` alert-name
   suffix and `pipeline: otel` labels dropped, so canonical alert names (and
   runbook anchors) are preserved across the swap with new expressions
   underneath. The D-4 heartbeat-absence pair replaces `up{}`-based liveness
   in the same commit.
4. **Staging route/receiver removed** from Alertmanager — alerts route by
   severity again.
5. **Dashboard CR re-pointed** at `microservices-dashboard-otel.json`; the
   local-stack Grafana provisions the adapted local copies (microservices +
   Temporal).
6. Sloth SLOs swap in the mop chart (`slo-otel.yaml` → canonical, legacy
   template retired) — a paired helm-charts release.

Code removal (client_golang middleware, `/metrics`, the otelprom bridge in
pkg and the nine repos) is **deliberately deferred** to a later wave:
until then, re-applying one ServiceMonitor restores the scrape pipeline —
the rollback is a single file.

## Alternatives

- **Soak the copies for a calendar week (RFC default).** Right for
  production; here it buys no additional signal — there is no live traffic
  beyond what the owner generates, and the copies were verified against the
  same data a soak would produce. Rejected by owner decision.
- **Keep both pipelines indefinitely.** Double ingest (~2× app series),
  double consumer maintenance, and the drift class RFC-0014 exists to kill.
  Rejected.
- **Cut over and delete the instrumentation code in the same wave.** Removes
  the one-file rollback while the new pipeline is young. Rejected — code
  removal follows once the cutover has lived through a few `make up` cycles.

## Consequences

- PromQL consumers use only the semconv names; `request_duration_seconds*`
  ingest continues solely for `app="checkout-service"` (none until checkout
  deploys).
- Liveness semantics change: pod death is detected by heartbeat-series
  absence (~5 minutes of VictoriaMetrics staleness lag) instead of a failed
  scrape (~15 s). Accepted in D-4; the pod-kill drill runs at the next
  `make up` session.
- In-flight saturation and GC-pause alerting are gone until otelgin ships
  `http.server.active_requests` (tracked `blocked-upstream` in the RFC
  tracker); GC health is covered by the pacing-pressure alert instead.
- Failure-only counters (e.g. `temporal_request_failure`) no longer report
  zero values — push emits only recorded instruments, so "no data" replaces
  "0" on failure panels.
- The scrape-era dashboard and rule history remain in git; P5 deletes the
  remaining docs references and the dead middleware.

_Last updated: 2026-07-09_
