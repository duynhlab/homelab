# KeycloakTokenLatencyHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency |
| **Source** | [`keycloak/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keycloak/alerts.yaml) |
| **Metrics** | `http_server_requests_seconds_bucket{job="keycloak", uri=~".*/token"}` |
| **Status** | active |
| **Local-stack** | vendored in [`vmalert/rules/keycloak.yaml`](../../../../local-stack/observability/vmalert/rules/keycloak.yaml) — same labels, no rewrite |

## Meaning

p99 latency on the token endpoint (`/realms/{realm}/protocol/{protocol}/token`
— the `uri` label is templated) exceeded 1s for 10 minutes. This endpoint
serves every password grant, code exchange, and refresh: it is the identity hot
path. Bucket boundaries top out at 2.5s, so any reported p99 above that is
clamped — read "2.5" as "at least 2.5".

## Impact

Every login and every silent token refresh on both SPAs stalls. Refreshes
happen in the background, so users first experience it as random slow page
loads, then as visible login delays. Left alone this typically degrades into
timeouts → failed refreshes → the symptoms of an auth outage.

## Diagnosis

Pool saturation is the #1 cause of Keycloak latency spikes — check it first.

### PromQL

```promql
histogram_quantile(0.99, sum by (le)(rate(http_server_requests_seconds_bucket{job="keycloak", uri=~".*/token"}[5m])))
# 1. Pool first:
agroal_awaiting_count{job="keycloak"}          # >0 → threads queuing (KeycloakDbPoolExhausted)
agroal_available_count{job="keycloak"}         # pinned at 0 → pool at ceiling
# 2. Load: is this latency or throughput?
sum(rate(http_server_requests_seconds_count{job="keycloak", uri=~".*/token"}[5m]))
sum by (event)(rate(keycloak_user_events_total[5m]))   # login/refresh surge?
# 3. Is the DB itself slow? (CNPG platform-db dashboards / alerts)
```

### kubectl / logs

```bash
kubectl top pod -n identity -l app.kubernetes.io/name=keycloak   # CPU throttling / GC pressure
kubectl logs -n identity -l app.kubernetes.io/name=keycloak --tail=100
```

### VictoriaLogs / traces

`{app="keycloak"} level:WARN` — Agroal acquisition-timeout warnings name the
pool; slow-query log lines name the statement. The `mdc.traceId` field joins a
slow token request to its edge span in Tempo.

## Mitigation

1. `agroal_awaiting_count > 0` → follow
   [KeycloakDbPoolExhausted](KeycloakDbPoolExhausted.md); this alert is the
   symptom, that one is the cause.
2. Login surge (attack) → see
   [KeycloakLoginFailureRatioHigh](KeycloakLoginFailureRatioHigh.md); rate
   limiting at the edge is the lever.
3. CPU at limit → raise the CPU limit via PR; Keycloak's password hashing is
   deliberately expensive and burns CPU under login load.
4. `platform-db` slow → that is the incident; fix the database, not Keycloak.

## Escalation

Ticket while p99 is between 1–2.5s and refreshes still succeed. Page when the
p99 clamps at 2.5s or token requests start timing out — that is minutes from an
effective auth outage.
