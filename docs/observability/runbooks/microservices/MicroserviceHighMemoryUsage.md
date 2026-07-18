# MicroserviceHighMemoryUsage

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Container working-set memory exceeds 90% of its memory limit for 15 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Memory leak (growing maps, slices, or caches without eviction)
- Large response bodies held in memory
- Goroutine leak (each goroutine uses ~8KB stack)
- Insufficient GOGC value (too much live data)

### Investigation
> **Metric remap (RFC-0014 P3 cutover):** `process_resident_memory_bytes` and the
> `go_memstats_*` series were `client_golang` names retired with the scrape. The OTLP
> Go-runtime set is `go_memory_used_bytes` (label `go_memory_type=stack|other`),
> `go_memory_allocated_bytes_total`, `go_memory_allocations_total`, `go_memory_gc_goal_bytes`.
> Container RSS now comes from cAdvisor (`container_memory_working_set_bytes`), which is
> labelled `namespace`/`pod`/`container` (not `app`), so select by namespace + pod regex.

```promql
# Working-set memory (limits-aware RSS, cAdvisor -- retired process_resident_memory_bytes)
container_memory_working_set_bytes{namespace=~"$NAMESPACE", pod=~"$APP.*", container!=""}

# Go heap in use (retired go_memstats_alloc_bytes / go_memstats_heap_inuse_bytes)
sum by (app) (go_memory_used_bytes{app="$APP"})

# Split by region (stack vs other) to spot which segment grows
go_memory_used_bytes{app="$APP"}

# Allocation rate (no frees counter in OTel; watch churn instead)
rate(go_memory_allocations_total{app="$APP"}[5m])

# If go_memory_used_bytes grows steadily post-GC = memory leak
```

**Grafana panels**: Row 4: Go Memory Used (by type), Working-Set Memory (container)

## Mitigation
1. Check Pyroscope heap profile (alloc_space, inuse_space) for the service
2. If `go_memory_used_bytes` grows post-GC: memory leak -- identify the growing data structure
3. If working-set is high but Go heap is stable: non-Go memory (CGO, mmap) -- check with `pprof`
4. Increase memory limit as stopgap, fix the leak in code
