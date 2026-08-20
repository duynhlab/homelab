# KeycloakLoginFailureRatioHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors |
| **Source** | [`keycloak/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keycloak/alerts.yaml) |
| **Metrics** | `keycloak_user_events_total{event="login", error, realm, client_id}` |
| **Status** | active |
| **Local-stack** | vendored in [`vmalert/rules/keycloak.yaml`](../../../../local-stack/observability/vmalert/rules/keycloak.yaml) — same labels, no rewrite |

## Meaning

More than 20% of `login` events carried a non-empty `error` label for 10
minutes, with real traffic behind it (the `and` guard requires >0.05 logins/s ≈
3/min, so an idle realm cannot page on a single typo). Keycloak has **no**
`login_error` event — failures are the *same* `event="login"` series with an
`error` label (`invalid_user_credentials`, `user_not_found`, …), verified live
2026-08-20. Some failure ratio is normal (users mistype); 1-in-5 sustained is
not.

## Impact

Either users cannot get in (broken auth flow, misconfigured client — a real
outage for new sessions) or someone is trying to get in who shouldn't
(brute-force / credential stuffing — a security event). The split below tells
which; the two have opposite mitigations.

## Diagnosis

### PromQL

```promql
# The alert expr, then split the numerator — the error value IS the diagnosis:
sum by (error, client_id, realm) (rate(keycloak_user_events_total{event="login", error!=""}[5m]))
```

- Many `user_not_found`, rotating usernames → credential stuffing.
- `invalid_user_credentials` concentrated on ONE user → targeted brute force.
- Everything on one `client_id`, errors like `invalid_redirect_uri` /
  `invalid_client_credentials` → a broken deploy of that SPA/client, not users.
- Confined to one `realm` → shop (`duynhlab`) vs Backoffice (`duynhlab-staff`)
  scopes the blast radius.

### VictoriaLogs

Keycloak event logs are queryable: `{app="keycloak"} "LOGIN_ERROR"` shows the
per-attempt detail (IP, username, error) that the metric aggregates away; the
`mdc.traceId` field links a failed attempt to its edge trace. `level` and
`loggerName` filter the noise.

### kubectl / compose

```bash
kubectl logs -n identity -l app.kubernetes.io/name=keycloak --tail=200 | grep LOGIN_ERROR
# local-stack:
docker compose logs --tail=200 keycloak | grep LOGIN_ERROR
```

## Mitigation

1. Attack pattern (rotating usernames, few IPs) → the edge owns throttling:
   verify the BackendTrafficPolicy rate limit covers the token/login path;
   Keycloak's own brute-force lockout protects individual accounts.
2. One client broken → roll back that client's deploy or fix its Keycloak
   client config (redirect URIs, secret) in the realm manifest — via PR, the
   realm import owns it.
3. Do not raise the threshold to silence an attack — the ratio is the signal.

## Escalation

Ticket for a client misconfiguration. Treat as a security incident (not just an
ops page) when the pattern is stuffing across many accounts — and say so in the
incident, because lockouts will start generating support noise.

## Related

`KeycloakTokenLatencyHigh` co-firing under an attack is load, not coincidence.
