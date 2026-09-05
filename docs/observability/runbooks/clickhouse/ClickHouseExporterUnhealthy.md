# ClickHouseExporterUnhealthy

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `otelcol_exporter_send_failed_log_records{exporter="clickhouse"}`, `…_send_failed_spans` |
| **Status** | active |
| **Dashboard** | ClickHouse → Overview · OTel Collector |
| **Local-stack** | present — the compose stack runs the same collector |

## Meaning

The **OTel Collector's** clickhouse exporter has been failing sends for 10
minutes. This is the consumer-side view: the collector can be perfectly up while
this one exporter backpressures, which is why it complements
`OtelCollectorDown` rather than duplicating it.

**Why this alert reads as "dead" in a metric audit, and is not.** Both series are
counters that OpenTelemetry creates only on the **first failure** — until then
they do not exist, and an audit checking "does this metric exist" will flag the
rule. Their sibling `otelcol_exporter_send_failed_metric_points` *is* present on
this cluster, which confirms the family name is right. `for: 10m` is what makes
the rule sound: by the time a sustained failure has run ten minutes there are
plenty of samples for `rate()`. A brief burst is genuinely missed — that is the
deliberate trade of a 10-minute window.

## Impact

OTel logs and traces are not landing in the OLAP store. VictoriaLogs and
VictoriaTraces keep their own copies, so triage is unaffected — **except for the
edge access log, which is ClickHouse-only** (ADR-061). That stream has no second
copy and what is dropped is gone.

Long-retention SQL and the `trace_id` JOIN lose coverage for the outage window.

## Diagnosis

Decide first whether the fault is the exporter or the store:

```promql
# Is the queue backing up
otelcol_exporter_queue_size{exporter="clickhouse"}
otelcol_exporter_queue_capacity{exporter="clickhouse"}

# Is anything landing at all
rate(otelcol_exporter_sent_log_records{exporter="clickhouse"}[5m])
```

```bash
kubectl logs -n monitoring deploy/otel-collector-opentelemetry-collector --tail=100 \
  | grep -i clickhouse
```

Then ask ClickHouse whether it is accepting writes:

```bash
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n monitoring chi-clickhouse-otel-0-0-0 -- clickhouse-client --password="$PW" --query "
  SELECT table, max(modification_time) FROM system.parts
  WHERE database='otel' AND active GROUP BY table"
```

Stale `modification_time` on all three tables means nothing is being inserted.

## Mitigation

Work the store first — the exporter is usually reporting someone else's problem:

1. Replica readonly → [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md)
2. Disk full → [ClickHouseDiskCritical](ClickHouseDiskCritical.md)
3. Insert pressure → [ClickHouseTooManyParts](ClickHouseTooManyParts.md)
4. Schema mismatch → the exporter runs `create_schema: false` and only INSERTs
   (ADR-065). If the committed DDL and the exporter's INSERT column list have
   drifted, inserts fail **at runtime under traffic**, and nothing in CI catches
   it. Compare the error in the collector log against the table definition.

## Escalation

Warning. Escalate when `otelcol_exporter_queue_size` approaches capacity — that
is the point where the outage becomes permanent data loss for the edge access
log.

## Related

- [ClickHouseInsertsDelayed](ClickHouseInsertsDelayed.md) — the softer precursor.
- [ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md) — if the
  store is down, this alert is a symptom.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
