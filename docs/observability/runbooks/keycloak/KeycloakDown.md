# KeycloakDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | [`keycloak/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keycloak/alerts.yaml) |
| **Metrics** | `up{job="keycloak"}` |
| **Status** | active |
| **Local-stack** | vendored in [`vmalert/rules/keycloak.yaml`](../../../../local-stack/observability/vmalert/rules/keycloak.yaml) — same `job="keycloak"`, no label rewrite |

## Meaning

The Keycloak management interface (`:9000`) has been unscrapeable for 5 minutes —
`up == 0`, or `absent(up)` when the target vanished entirely (Service deleted,
ServiceMonitor label drift). Per the RFC-0022 availability model, Keycloak is on
the hot path of **new** logins and refreshes only: already-issued access tokens
keep verifying at the edge against cached JWKS keys.

## Impact

A countdown, not an instant outage. New sign-ins fail immediately on both SPAs
(shop `duynhlab` realm and Backoffice `duynhlab-staff` realm); active sessions
survive until their access token expires (15 min), then the refresh fails and
the user is bounced to a login page that cannot log them in. Expect
`EdgeJWKSFetchFailing` to co-fire once the edge tries to refresh keys.

## Diagnosis

### PromQL

```promql
up{job="keycloak"} == 0 or absent(up{job="keycloak"})
# Was it dying slowly first? Pool and latency history:
agroal_awaiting_count{job="keycloak"}
histogram_quantile(0.99, sum by (le)(rate(http_server_requests_seconds_bucket{job="keycloak", uri=~".*/token"}[5m])))
```

### kubectl / logs

```bash
kubectl get pods -n identity -l app.kubernetes.io/name=keycloak
kubectl describe pod -n identity -l app.kubernetes.io/name=keycloak | tail -30
kubectl logs -n identity -l app.kubernetes.io/name=keycloak --tail=100
# The usual killer is the DB dependency:
kubectl get cluster -n databases platform-db
```

```bash
# local-stack
docker compose ps keycloak && docker compose logs --tail=100 keycloak
```

### VictoriaLogs

Keycloak logs carry `level`, `loggerName`, and `mdc.traceId` fields. Filter
`{app="keycloak"}` to `level:ERROR` around the drop — a failed DB connection
(`org.hibernate` / Agroal loggers) or an OOM kill preceding the restart is
usually the whole story.

## Mitigation

1. Pod pending/crash-looping → see [KeycloakRestartLoop](KeycloakRestartLoop.md);
   the fix is almost always DB connectivity (`platform-db-rw:5432`), the realm
   import, or memory limits.
2. Scrape-only failure (pod healthy, `up` absent) → check the ServiceMonitor
   selector and the management port (`:9000`, `KC_METRICS_ENABLED`) — the
   platform is fine, the alerting is blind.
3. Do **not** restart Keycloak reflexively while the DB is down — it will crash
   again and reset the JWKS cache clock for the edge.

## Escalation

Page-worthy as-is: the 15-minute token expiry makes this a guaranteed
platform-wide auth outage on a timer. If `platform-db` alerts co-fire, the
incident is the database — treat Keycloak as a casualty, not the cause.
