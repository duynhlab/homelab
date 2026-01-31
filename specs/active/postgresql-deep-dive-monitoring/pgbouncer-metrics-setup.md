# PgBouncer Metrics Implementation Guide

## 1. Overview
This guide documents the enabling of metrics for PgBouncer instances managed by the Zalando Postgres Operator (e.g., `auth-db`).
Since the Zalando Operator handles the `Deployment` of the pooler, we cannot easily inject a sidecar container for metrics. Instead, we implemented a **Standalone Exporter Pattern**.

## 2. Implementation Architecture
- **Component**: `pgbouncer-exporter` (Image: `prometheuscommunity/pgbouncer-exporter:v0.11.0`)
- **Type**: Standalone `Deployment` in the same namespace (`auth`).
- **Connection**: Connects to the existing `pgbouncer` service (`auth-db-pooler`) on port 5432.
- **Authentication**: Uses the `pooler` user credentials stored in the operator-generated secret (`pooler.<cluster-name>.credentials.postgresql.acid.zalan.do`).
- **Scraping**: A `ServiceMonitor` exposes the metrics on port `9127` to Prometheus.

## 3. Deployment Status: Auth-DB
✅ **Completed**. The following resources were deployed:

1.  **Deployment**: `auth-db-pgbouncer-exporter`
    *   Injects credentials from `pooler.auth-db.credentials.postgresql.acid.zalan.do`.
2.  **Service**: `auth-db-pgbouncer-exporter`
3.  **ServiceMonitor**: `auth-db-pgbouncer-exporter`

### Verification
You can check the pod status:
```bash
kubectl get pods -n auth -l app=auth-db-pgbouncer-exporter
```

You can port-forward to verify metrics:
```bash
kubectl port-forward -n auth deploy/auth-db-pgbouncer-exporter 9127:9127
curl localhost:9127/metrics | grep pgbouncer_
```

**Sample Output (Confirmed):**
```promql
pgbouncer_databases_pool_size{database="postgres",host="auth-db",...} 60
pgbouncer_pools_client_active_connections{database="pgbouncer",user="pgbouncer"} 1
pgbouncer_up 1
pgbouncer_version_info{version="PgBouncer 1.22.0"} 1
```

## 4. How to Enable for Other Clusters (e.g., `review-db`, `supporting-db`)

To replicate this for other Zalando clusters, follow these steps:

1.  **Create Directory**: `kubernetes/infra/configs/databases/clusters/<cluster-name>/monitoring/`
2.  **Create Manifest**: Copy `kubernetes/infra/configs/databases/clusters/auth-db/monitoring/pgbouncer-exporter.yaml` and replace:
    *   `auth-db` -> `<cluster-name>`
    *   `auth` -> `<namespace>`
    *   `pooler.auth-db.credentials...` -> `pooler.<cluster-name>.credentials...`
3.  **Update Kustomization**: Add `monitoring/pgbouncer-exporter.yaml` to the `resources` list in `<cluster-name>/kustomization.yaml`.
4.  **Apply**: `kubectl apply -k kubernetes/infra/configs/databases/clusters/<cluster-name>`

## 5. Other Clusters Note
-   **Transaction-DB**: Uses `PgCat`, which has built-in metrics on port 9930. A `ServiceMonitor` (`pgcat-transaction`) is already in place.
-   **Product-DB**: Uses `PgDog`. Ensure its `ServiceMonitor` is configured similarly if not already.
