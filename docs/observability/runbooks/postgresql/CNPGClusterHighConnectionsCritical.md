# CNPGClusterHighConnectionsCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart ([`cluster-high_connection-critical.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg/cluster-high_connection-critical.yaml)) |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_connection_limits` (dashboard); alert uses `cnpg_backends_total` |
| **Grafana** | CloudNativePG Cluster Overview, pg-maintenance |

## Meaning

Fires when a CNPG instance uses **>95%** of `max_connections` for **5 minutes**:

```promql
sum by (pod) (cnpg_backends_total) /
max by (pod) (cnpg_pg_settings_setting{name="max_connections"}) * 100 > 95
```

The chart alert uses built-in backend counts. The custom query
`cnpg_pg_connection_limits_*` on dashboards may show a slightly different ratio
(client backends only) — treat both as connection pressure signals.

## Impact

At 100% capacity PostgreSQL rejects new connections (`FATAL: sorry, too many
clients already`). Applications see connection errors; PgDog may queue or reject
clients depending on pool settings. Total service disruption for database-backed
APIs.

## Diagnosis

### PromQL

```promql
# Chart alert ratio per pod
sum by (pod, cnpg_io_cluster) (cnpg_backends_total)
/ max by (pod, cnpg_io_cluster) (cnpg_pg_settings_setting{name="max_connections"})
* 100

# Dashboard custom query saturation
cnpg_pg_connection_limits_current_connections
/ cnpg_pg_connection_limits_max_connections

# By state (idle in transaction often the culprit)
sum by (datname, state) (cnpg_pg_stat_activity_count_count{cnpg_io_cluster="$CLUSTER"})
```

### Grafana

- **CloudNativePG Cluster Overview** — connections per instance
- **pg-maintenance** — activity by state

### kubectl / psql

```bash
export NAMESPACE=platform   # or product
export CLUSTER=platform-db  # or product-db

kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER"
kubectl top pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER"

kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT datname, usename, state, count(*)
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY 1, 2, 3
ORDER BY count DESC;
"

kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SHOW max_connections;
SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';
"
```

**PgDog pooler** (most services connect via pooler, not direct):

```bash
kubectl logs -n "$NAMESPACE" deploy/pgdog-${CLUSTER%-db} --tail=50
# PromQL: pgdog_* client vs server counts
```

**Direct connections (exceptions):**

- **payment-service** connects direct to `product-db-rw:5432` with TLS — counts
  against Postgres, not PgDog. See
  [PgDog operations](../../../databases/runbooks/pgdog-operations.md).
- **Init/migration jobs** connect direct to `-rw:5432`.

## Mitigation

1. **Reduce connection churn** — verify app pool sizes (`pgxpool` max conns) are
   not excessive; PgDog uses transaction pooling.
2. **Clear idle / idle-in-transaction sessions** — see
   [CNPGIdleInTransaction.md](CNPGIdleInTransaction.md).
3. **Increase `max_connections`** only as a temporary measure — edit CNPG
   `Cluster` PostgreSQL parameters and reconcile; ensure memory can absorb
   `max_connections × work_mem` worst case.
4. **Scale PgDog** if pooler is the bottleneck (client queue, not Postgres).
5. **Do not** disable PgDog to "free connections" — that increases direct
   backend count.

## Escalation

- **Immediate** if apps report connection failures — treat as P1 alongside
  [CNPGClusterOffline.md](CNPGClusterOffline.md) triage if errors are widespread.
- Link [Emergency recovery](../../../databases/010.4-emergency-recovery.md) if
  the cluster is unreachable, not merely saturated.
