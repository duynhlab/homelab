# EdgeJWKSFetchFailing

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability / identity |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `envoy_http_jwt_authn_jwks_fetch_failed` |

## Meaning

The edge cannot refresh Keycloak's JWKS. Cached keys keep working, so **nothing
fails yet** — this alert exists precisely because the failure is invisible until
the cache expires or the realm rotates keys, at which point every `private` and
`protected` route answers 401 at once.

## Impact

A dormant, whole-platform authentication outage. Once the cache is stale, both
SPAs bounce to sign-in and every API call from a browser fails — while the
services themselves are healthy and their own alerts stay quiet.

## Diagnosis

```promql
rate(envoy_http_jwt_authn_jwks_fetch_failed[5m])
# Are 401s already appearing?
sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class="4"}[5m]))
```

Check the reachability the edge actually uses. Both stacks use split horizon —
the **issuer** is the browser-facing origin while the **JWKS fetch** is
in-network — so a mismatch here is a common cause:

```bash
# Cluster: the SecurityPolicy's remoteJWKS URI must resolve from the proxy
kubectl get securitypolicy -A -o yaml | grep -A3 remoteJWKS
kubectl get pods -n identity -l app.kubernetes.io/name=keycloak
kubectl logs -n envoy-gateway -l gateway.envoyproxy.io/owning-gateway-name=platform --tail=100 | grep -i jwks
```

```bash
# local-stack: the JWKS URL is keycloak:8080 while the issuer is localhost:8081
grep -A3 remoteJWKS local-stack/gateway/eg/securitypolicy.yaml
curl -s -o /dev/null -w '%{http_code}\n' \
  http://localhost:8081/realms/duynhlab/protocol/openid-connect/certs
```

Since ADR-050 there are **two** realms to check — `duynhlab` (customers) and
`duynhlab-staff` (operators). A failure on the staff realm alone breaks the
Backoffice while the shop keeps working, which is worth stating in the incident.

## Mitigation

- Keycloak down or unready: that is the identity incident; the edge recovers
  when JWKS is reachable again.
- URI wrong after a namespace/service rename: fix the SecurityPolicy manifest —
  and note that a JWKS URI is the one field where "it worked in local-stack"
  proves nothing, because the two stacks resolve it differently.
- NetworkPolicy: the edge must be allowed to reach identity on :8080. This is
  the exact allow the Kong→EG cutover had to re-point.

## Escalation

Ticket if 401s have not started; page the moment they do, because by then it is
a platform-wide auth outage with a known cause.
