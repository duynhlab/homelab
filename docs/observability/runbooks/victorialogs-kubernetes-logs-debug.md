# VictoriaLogs Kubernetes Logs - Debug Runbook

**Symptom:** Grafana shows no Kubernetes logs in the **VictoriaLogs** datasource
(Explore returns empty, or a logs panel is blank).

**Architecture:** per-node Vector agent (DaemonSet) → VictoriaLogs (VLSingle) → Grafana.

```mermaid
flowchart LR
    Pods[Kubernetes Pods] --> Vector["Vector agent<br/>(kube-system, DaemonSet)"]
    Vector -->|/insert/jsonline| VLogs["VictoriaLogs / VLSingle<br/>(monitoring :9428)"]
    VLogs -->|/select/logsql/query| Grafana["Grafana<br/>VictoriaLogs datasource"]
```

> Reference (endpoints, stream fields, sinks, config):
> [`observability/logging/victorialogs.md`](../logging/victorialogs.md).

---

## Quick Checklist

| Step | Check | Command |
|------|-------|---------|
| 1 | VLSingle running | `kubectl get vlsingle -n monitoring` |
| 2 | Vector agent running | `kubectl get pods -n kube-system -l app.kubernetes.io/name=vector` |
| 3 | VictoriaLogs healthy | port-forward `svc/vlsingle-victoria-logs 9428` → `curl localhost:9428/health` |
| 4 | Logs actually ingested | LogsQL query `_stream:{namespace="monitoring"}` |
| 5 | Grafana datasource | Grafana → Connections → **VictoriaLogs** → Save & Test |

---

## 1. Verify VictoriaLogs is Running

```bash
# VLSingle CR + pod
kubectl get vlsingle -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=vlsingle

# Health (after port-forward)
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428
curl -s http://localhost:9428/health   # expected: VictoriaLogs is Ready
```

**If not ready:** check the operator and pod logs —
`kubectl logs -n monitoring -l app.kubernetes.io/name=vlsingle --tail=50`.

---

## 2. Verify Vector is Collecting and Pushing

```bash
# Vector pods (DaemonSet - one per node)
kubectl get pods -n kube-system -l app.kubernetes.io/name=vector

# Vector logs - look for sink errors / successful pushes
kubectl logs -n kube-system -l app.kubernetes.io/name=vector --tail=100 | grep -i victorialogs
kubectl logs -n kube-system -l app.kubernetes.io/name=vector --tail=100 | grep -i error
```

**Common Vector errors:**
- `connection refused` → VictoriaLogs not ready or wrong endpoint
- `429 / rate limit` → ingestion backpressure; check VLSingle resources
- `400 bad request` → malformed `VL-*` headers (see victorialogs.md → Vector Sink Headers)

The three sinks are `victorialogs_all`, `victorialogs_pg_plans`,
`victorialogs_pg_parse_failures` — all HTTP to `/insert/jsonline`.

---

## 3. Verify Logs Are Ingested (LogsQL)

```bash
# Broadest query (any stream)
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=*' --data-urlencode 'limit=10'

# By namespace stream field
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{namespace="product"}' --data-urlencode 'limit=10'
```

**Stream fields** (set by Vector): `namespace`, `service`, `pod_name`,
`container_name`. If a query filters on a field that is not a stream field,
use a plain word/phrase filter instead of `_stream:{...}`.

---

## 4. Grafana Datasource

```bash
# VictoriaLogs reachable from Grafana
kubectl exec -n monitoring deploy/grafana -- \
  wget -qO- --timeout=5 http://vlsingle-victoria-logs.monitoring.svc.cluster.local:9428/health
```

- **Datasource:** VictoriaLogs (plugin `victoriametrics-logs-datasource`), UID `victorialogs`
- **Provisioned by:** `kubernetes/infra/configs/observability/grafana/datasource-victorialogs.yaml`
- **URL:** `http://vlsingle-victoria-logs.monitoring.svc.cluster.local:9428`
- **UI:** Connections → Data sources → VictoriaLogs → Save & Test

---

## 5. LogsQL Queries to Try

In Grafana **Explore** → select the **VictoriaLogs** datasource:

```logsql
# All logs (broadest)
*

# Specific namespace (stream field)
_stream:{namespace="product"}

# By service
_stream:{service="auth"}

# PostgreSQL query plans (CloudNativePG auto_explain)
_stream:{cluster_name!=""}
```

**Time range:** ensure "Last 15 minutes" or "Last 1 hour". VLSingle retention is
`7d` (see VLSingle CRD).

---

## 6. Dependency Order

Vector and VictoriaLogs are reconciled by Flux. If Vector starts before
VictoriaLogs is ready, initial pushes fail and retry.

```bash
flux get kustomizations -A | grep -E "logging|monitoring|vector"
```

---

## Summary: Most Likely Causes

1. **VLSingle not ready** → Vector pushes fail → check VLSingle CR + pod
2. **Wrong time range** → no logs in the selected window → widen to "Last 6 hours"
3. **Grafana datasource misconfigured** → Save & Test the VictoriaLogs datasource
4. **Querying a non-stream field via `_stream:{...}`** → use a word/phrase filter instead

## Related

- [VictoriaLogs backend](../logging/victorialogs.md) — full reference
- [Structured Logging overview](../logging/README.md)
- LogsQL: https://docs.victoriametrics.com/victorialogs/logsql/

---
_Last updated: 2026-07-21 — Moved from `docs/runbooks/troubleshooting/` to observability runbooks._
