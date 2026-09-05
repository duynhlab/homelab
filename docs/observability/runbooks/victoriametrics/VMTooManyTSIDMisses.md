# VMTooManyTSIDMisses

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `vm_missing_tsids_for_metric_id_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

VictoriaMetrics cannot resolve a metric ID to its series identifier. This is **not**
a cache miss — that is
[VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md). A TSID miss
means the index and the data disagree: the data references a series the index
cannot describe.

Upstream treats this as an index-integrity signal, which is why it is critical
despite being rare.

## Impact

Queries can silently return **incomplete results** — samples exist on disk but
cannot be found through the index. That is worse than an error, because nothing
looks wrong: a dashboard renders a line with a gap and no one is told.

## Diagnosis

```promql
sum(rate(vm_missing_tsids_for_metric_id_total[5m]))
sum(vm_rows{type="indexdb"})
vm_cache_entries{type="storage/tsid"}
```

```bash
kubectl logs -n monitoring deploy/vmsingle-victoria-metrics --tail=200 | grep -iE 'tsid|index|corrupt'
```

Correlate with the past: an unclean shutdown, an OOMKill mid-merge, or a disk-full
event are the usual precursors. Check whether
[VMTooManyRestarts](VMTooManyRestarts.md) or
[VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md) fired recently.

## Mitigation

1. Read the logs first — VictoriaMetrics usually names the affected part.
2. A restart lets it rebuild in-memory index structures and clears transient
   cases.
3. Persistent misses point at on-disk index damage. That is a data-integrity
   conversation, not a restart: capture the logs before doing anything
   destructive.
4. On this platform the store is **not replicated** (single `vmsingle`), so there
   is no healthy copy to fail over to. Treat the data as precious.

## Escalation

Critical. Escalate with the log excerpt — silent incomplete query results are the
kind of failure that erodes trust in every dashboard afterwards.

## Related

- [VMTooManyRestarts](VMTooManyRestarts.md)
- [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
