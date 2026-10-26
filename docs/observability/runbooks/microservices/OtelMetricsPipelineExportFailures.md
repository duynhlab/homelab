# OtelMetricsPipelineExportFailures

| Item | Value |
|---|---|
| **Severity / category** | critical / availability |
| **Source** | [Microservice rules](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |
| **Metrics** | `otelcol_exporter_send_failed_metric_points` |
| **Status** | Active in repository configuration |
| **Validation** | Static rule/runbook comparison, 2026-10-23; no new firing test |
| **Dashboard** | Grafana → Collector self-telemetry; confirm the actual provisioned board title |

## Meaning

The configured expression is:

```promql
sum by (exporter) (increase(otelcol_exporter_send_failed_metric_points[15m])) > 0
```

It has `for: 0m`: a positive increase in the 15-minute window can fire at the
next evaluation. The manifest's description still says “5 minutes” and
“points/s”; those words do not match the expression. Use the expression above
and track that annotation correction separately from this docs-only change.

An export failure needs investigation. Determine whether the running exporter
reports retry attempts or terminal failures, and correlate its logs and queues
before quantifying loss. An export-error log alone is not a count of unique
lost points. Empty queries may mean no sparse failure series has been created;
check scrape health and successful exports as well.

## Impact

Metrics can arrive late or be lost. SDK-based dashboards and SLO evaluation may
be stale even while application traffic succeeds. Collector self-telemetry is
scraped independently, so use that path to investigate the broken OTLP path.

## Diagnosis

Read-only commands; choose the Collector pod from the output rather than
assuming a shortened Deployment name:

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=opentelemetry-collector
kubectl -n monitoring logs -l app.kubernetes.io/name=opentelemetry-collector \
  --all-containers=true --since=20m --tail=200
kubectl -n monitoring get events --sort-by=.lastTimestamp
```

1. Use the alert's `exporter` label to identify the destination in the
   [pipeline table](../../opentelemetry/collector.md#the-deployed-pipelines).
   Application OTLP metrics target vmagent; derived span metrics use a separate
   remote-write exporter.
2. Inspect destination readiness, Service/EndpointSlices, recent configuration
   changes, connection/TLS errors and backend saturation. Review logs locally
   before sharing them; exception text may contain sensitive data.
3. Query queue size/capacity and enqueue/refusal counters exposed by the running
   Collector. Confirm names from its scraped metrics before using version-specific
   queries. Compare successful export rate and backend sample freshness over
   the same UTC window. No configured alert for a metric is not proof it is zero.
4. Check restarts and OOM events. The configured limiter is soft 600MiB, hard
   800MiB, inside a 1Gi limit. Restarting a process with volatile queues can lose
   pending data.

## Mitigation

1. Restore the identified backend or network/configuration fault through its
   owning runbook and GitOps path. Do not increase queue consumers into an
   already saturated backend.
2. Let queues drain while observing export successes and destination freshness.
   Avoid restarting the Collector merely to clear the alert.
3. If capacity is the cause, measure input/output rates and memory before
   proposing queue, resource or replica changes. Stateful processors and
   aggregation require a scaling design; this runbook makes no such change.

## Recovery validation

Confirm both data delivery and alert recovery: successful exports resume,
queues return to their pre-incident level, backend samples advance, and a known
request produces expected metrics. Then verify the expression is false for two
evaluation intervals **after the 15-minute lookback clears**. Record any
permanent gaps; a zero queue is also consistent with discarded data.

## Escalation

Treat sustained stale service/SLO telemetry, terminal drops, full queues or
repeated restarts as an observability incident. Escalate to the platform owner
with exporter, destination, UTC window, rates and recent changes. A recovered
transient failure still needs its observed loss/latency recorded. Never silence
this alert solely because the application endpoints are healthy.

## Related

- [Collector operations and resilience](../../opentelemetry/collector.md#operations)
- [Linux Kind verification](../telemetry-kind-verification.md)
- [Alert lifecycle and evidence levels](../../alerting/alert-lifecycle-and-runbooks.md)
