# EdgeAuthDeniedRatioHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors / identity |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `envoy_http_jwt_authn_denied`, `envoy_http_jwt_authn_allowed` (verified live 2026-08-20) |
| **Local-stack** | same metrics on `job="envoy"` (cluster data plane is `job="envoy-gateway"`) |

## Meaning

More than 50% of requests reaching the jwt_authn filter were denied (401) for
10 minutes, with a min-traffic guard (>0.05 authenticated req/s) so a near-idle
edge cannot page on one denial. Denials are Envoy-local: they never reach an
upstream, so no service-side alert sees them, and a 401 is neither a 5xx nor a
429 — without this rule, mass authentication failure is invisible.

## Impact

The blind spot this alert closes: a JWKS outage that outlives the key cache
converts into mass 401s while every service dashboard stays green. Users are
bounced to sign-in; API calls from both SPAs fail. If the denied traffic is an
unauthenticated scraper instead, impact is nil — the split below decides.

## Diagnosis

### PromQL

```promql
# The ratio, then its parts:
sum(rate(envoy_http_jwt_authn_denied{job="envoy-gateway"}[5m]))
sum(rate(envoy_http_jwt_authn_allowed{job="envoy-gateway"}[5m]))
# THE deciding question — is the JWKS fetch also failing?
rate(envoy_http_jwt_authn_jwks_fetch_failed{job="envoy-gateway"}[5m])
rate(envoy_http_jwt_authn_jwks_fetch_success{job="envoy-gateway"}[5m])
# Keycloak's own view — are refreshes failing there too?
sum by (event, error)(rate(keycloak_user_events_total{error!=""}[5m]))
```

- `jwks_fetch_failed` rising (or `EdgeJWKSFetchFailing` fired earlier) → the
  cache has expired: this is the JWKS outage landing. Root-cause with
  [EdgeJWKSFetchFailing](EdgeJWKSFetchFailing.md).
- Fetches succeeding but denials high → tokens themselves are bad: a Keycloak
  key rotation the edge hasn't picked up, clients pinning expired tokens after
  a frontend deploy, or plain unauthenticated probing.

### kubectl / logs

```bash
kubectl logs -n envoy-gateway -l gateway.envoyproxy.io/owning-gateway-name=platform --tail=100 | grep -i -E "jwt|jwks"
# Access logs: which routes/clients are eating the 401s?
```

```bash
# local-stack
docker compose logs --tail=100 envoy | grep -i jwt
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/api/users/me   # no token → expect 401
```

## Mitigation

1. JWKS path broken → fix that (Keycloak health, SecurityPolicy `remoteJWKS`
   URI, identity NetworkPolicy); denials clear as soon as fresh keys verify.
2. Key rotation mismatch → confirm the realm's current `kid`s
   (`/realms/<realm>/protocol/openid-connect/certs`) differ from what the edge
   cached; a proxy fleet rollout forces a JWKS refetch.
3. Client fleet with stale tokens after a deploy → roll the frontend back or
   force re-login; the edge is behaving correctly.
4. Scraper/probe traffic → nothing is broken; consider rate limits, do not
   loosen the SecurityPolicy.

## Escalation

Page when `allowed` collapsed while `denied` took over prior traffic levels —
that is a platform-wide auth outage in progress. Ticket when it is background
unauthenticated noise on a quiet edge. What not to do: disable the JWT
SecurityPolicy to "restore service" — that turns an auth outage into an open,
unauthenticated edge.

## Related

[EdgeJWKSFetchFailing](EdgeJWKSFetchFailing.md) is the cause-side alert;
this is its symptom-side companion. [KeycloakDown](../keycloak/KeycloakDown.md)
upstream produces both.
