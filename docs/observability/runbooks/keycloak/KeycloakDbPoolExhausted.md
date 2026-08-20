# KeycloakDbPoolExhausted

| | |
|---|---|
| **Severity** | critical |
| **Category** | saturation |
| **Source** | [`keycloak/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keycloak/alerts.yaml) |
| **Metrics** | `agroal_awaiting_count{datasource="default"}` (plus `agroal_available_count`, `agroal_active_count`, `agroal_max_used_count`) |
| **Status** | active |
| **Local-stack** | vendored in [`vmalert/rules/keycloak.yaml`](../../../../local-stack/observability/vmalert/rules/keycloak.yaml) — same labels, no rewrite |

## Meaning

`agroal_awaiting_count > 0` for 2 minutes: request threads are **blocked
waiting** for a connection from Keycloak's Agroal DB pool. This is the
unambiguous exhaustion signal — `available_count == 0` alone can be a healthy
pool at full utilization, but threads *waiting* means demand has outrun the
pool for a sustained window. Pool saturation is the #1 cause of Keycloak
latency spikes.

## Impact

Every login, refresh, and admin operation queues behind the pool. First seen as
token-endpoint latency (`KeycloakTokenLatencyHigh` typically co-fires), then as
acquisition timeouts — surfacing to users as 5xx on login, indistinguishable
from Keycloak being down.

## Diagnosis

### PromQL

```promql
agroal_awaiting_count{job="keycloak"}
agroal_available_count{job="keycloak"}    # 0 while awaiting>0 = confirmed exhaustion
agroal_max_used_count{job="keycloak"}     # high-water mark vs the configured max
# Demand side — what is eating the pool?
sum by (event)(rate(keycloak_user_events_total[5m]))
sum(rate(http_server_requests_seconds_count{job="keycloak"}[5m]))
```

Two distinct shapes: **demand spike** (request rate up — login surge or attack)
vs **supply stall** (rate flat but connections held — slow queries or a
struggling `platform-db` making every statement hold its connection longer).

### kubectl / logs

```bash
kubectl get cluster -n databases platform-db          # DB healthy?
kubectl logs -n identity -l app.kubernetes.io/name=keycloak --tail=100 | grep -i -E "agroal|timeout"
# What is the DB doing with Keycloak's connections?
kubectl exec -n databases platform-db-1 -- psql -U postgres -c \
  "SELECT state, count(*), max(now()-query_start) FROM pg_stat_activity WHERE usename='keycloak' GROUP BY state;"
```

```bash
# local-stack
docker compose logs --tail=100 keycloak | grep -i agroal
```

### VictoriaLogs

`{app="keycloak"} "Acquisition timeout"` — Agroal names the starved operation;
`level:WARN` with `loggerName:io.agroal*` catches the queuing before timeouts
start.

## Mitigation

1. Supply stall → fix `platform-db` (long transactions, lock pileup); the pool
   drains itself once statements complete. Killing Keycloak pods does NOT help —
   fresh pods queue on the same slow database.
2. Demand spike from an attack → throttle at the edge (see
   [KeycloakLoginFailureRatioHigh](KeycloakLoginFailureRatioHigh.md)).
3. Genuine steady-state growth → raise the pool max
   (`KC_DB_POOL_MAX_SIZE`) via PR — and check `platform-db`'s
   `max_connections` headroom first; a bigger Keycloak pool starves other
   tenants of the shared cluster.

## Escalation

Critical and page-worthy: sustained waiting is minutes from user-visible login
failures. If `platform-db` alerts co-fire, the database is the incident. What
not to do: restart Keycloak "to clear the pool" — it drops in-flight sessions
and reconnect storms the database.
