# Loki Kubernetes Logs - Debug Runbook

**Symptom:** Grafana Loki Kubernetes Logs dashboard shows no logs.

**Architecture:** Vector (DaemonSet) → Loki (Deployment) → Grafana (Explore / Dashboard)

---

## Quick Checklist

| Step | Check | Command |
|------|-------|---------|
| 1 | Loki pod running | `kubectl get pods -n monitoring -l app=loki` |
| 2 | Vector DaemonSet running | `kubectl get pods -n kube-system -l app.kubernetes.io/name=vector` |
| 3 | Loki receiving data | `kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/ready` |
| 4 | Grafana datasource | Grafana → Connections → Loki → Test |
| 5 | LogQL query | `{namespace=~".+"}` in Explore |

---

## 1. Verify Loki is Running

```bash
# Pod status
kubectl get pods -n monitoring -l app=loki

# Loki ready endpoint
kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/ready
# Expected: ready

# Loki metrics (ingestion rate)
kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/metrics | grep loki_ingester_chunks_stored_total
```

**If Loki not ready:** Check logs `kubectl logs -n monitoring -l app=loki --tail=50`

---

## 2. Verify Vector is Collecting and Pushing

```bash
# Vector pods (DaemonSet - one per node)
kubectl get pods -n kube-system -l app.kubernetes.io/name=vector

# Vector logs - look for Loki sink errors
kubectl logs -n kube-system -l app.kubernetes.io/name=vector --tail=100 | grep -i loki

# Vector internal API (if enabled)
kubectl port-forward -n kube-system svc/vector 8686:8686
# curl http://localhost:8686/health
```

**Common Vector errors:**
- `connection refused` → Loki not ready or wrong endpoint
- `rate limit` → Loki ingestion limits
- `invalid labels` → Label name/format issue (Loki: `[a-zA-Z_:][a-zA-Z0-9_:]*`)

---

## 3. Verify Loki Labels (Dashboard Compatibility)

**Grafana Loki Kubernetes dashboard (15141)** expects these labels:
- `namespace` ✓
- `stream` ✓ (stdout/stderr) - **Vector must send this**
- `container` ✓

**Vector Loki sink** sends: `service`, `namespace`, `pod`, `container`, `stream`

If `stream` was missing, dashboard template `label_values(stream)` returns empty → queries fail.

**Fix:** Ensure Vector add_labels transform extracts `.stream` and Loki sink includes `stream: "{{ stream }}"`.

---

## 4. Grafana Datasource

```bash
# Loki service reachable from Grafana
kubectl exec -n monitoring deploy/grafana -- wget -qO- --timeout=5 http://loki.monitoring.svc.cluster.local:3100/ready
```

**Grafana UI:** Connections → Data sources → Loki → Save & Test

**Expected URL:** `http://loki.monitoring.svc.cluster.local:3100`

---

## 5. LogQL Queries to Try

In Grafana **Explore** → Select **Loki** datasource:

```logql
# All namespaces (broadest)
{namespace=~".+"}

# Specific namespace
{namespace="product"}

# By service
{service="auth"}

# With stream (stdout/stderr)
{namespace="product", stream=~"stdout|stderr"}
```

**Time range:** Ensure "Last 15 minutes" or "Last 1 hour" - Loki may have retention limits.

---

## 6. Dependency Order

Vector HelmRelease has `dependsOn: kube-prometheus-stack`. Loki is deployed separately. If Vector starts before Loki is ready, initial pushes may fail. Vector will retry.

**Check Flux reconciliation:**
```bash
flux get kustomizations -A | grep -E "logging|loki|vector"
```

---

## 7. Loki Config (Storage)

Loki uses `emptyDir` for storage - data is lost on pod restart. For persistent logs, configure PVC in Loki deployment.

**Retention:** `retention_period: 168h` (7 days) in configmap.

---

## 8. Vector → Loki Endpoint

```yaml
# Vector values (vector.yaml)
sinks:
  loki:
    endpoint: http://loki.monitoring.svc.cluster.local:3100
```

**From kube-system namespace:** `loki.monitoring.svc.cluster.local` resolves to Loki Service in monitoring namespace.

---

## Summary: Most Likely Causes

1. **Missing `stream` label** → Dashboard template variables empty → Fix: Add stream to Vector Loki sink (done in vector.yaml)
2. **Loki not ready** → Vector pushes fail → Check Loki pod, config
3. **Wrong time range** → No logs in selected window → Try "Last 6 hours"
4. **Grafana datasource misconfigured** → Test connection in Grafana UI
