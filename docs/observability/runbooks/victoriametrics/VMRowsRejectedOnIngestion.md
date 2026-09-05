# VMRowsRejectedOnIngestion

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `vm_rows_ignored_total` by `reason` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

VictoriaMetrics is **discarding rows at ingestion**. The `reason` label is the
whole diagnosis, and the reasons are not equally alarming:

| `reason` | Meaning |
|---|---|
| `too_big_timestamp`, `too_small_timestamp` | Sample outside the accepted window — clock skew, or backfill beyond retention |
| `nan_value` | The exporter sent NaN |
| `invalid_name`, `invalid_label` | Malformed metric or label name |
| `too_many_labels` | Series exceeds the label limit |

Unlike a queue delay, **rejected rows are gone**. There is no retry.

## Impact

Silent gaps. A metric that is rejected does not error anywhere the producer can
see — the exporter believes it sent, and the series simply never appears. That
makes this one of the few alerts whose absence you cannot infer anything from.

## Diagnosis

```promql
sum by (reason) (rate(vm_rows_ignored_total[5m]))
topk(10, sum by (reason) (increase(vm_rows_ignored_total[1h])))
```

```bash
kubectl logs -n monitoring deploy/vmsingle-victoria-metrics --tail=200 | grep -i 'ignor\|reject\|cannot parse'
```

Then find the producer. Timestamp reasons point at a clock or at a backfill;
name and label reasons point at one exporter and usually name it in the log line.

## Mitigation

1. **Timestamp** → check node clocks; if it is a deliberate backfill, it is
   outside retention and the rejection is correct.
2. **Invalid name/label** → fix the instrumentation. This is a producer bug.
3. **too_many_labels** → a cardinality problem wearing a different hat; see
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md).

## Escalation

Warning, but do not let it sit. Rejected rows are permanent gaps, and a gap
nobody investigated becomes a dashboard nobody trusts.

## Related

- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)
- [VMAgentTooManyScrapeErrors](VMAgentTooManyScrapeErrors.md) — the other end of
  the pipeline.

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
