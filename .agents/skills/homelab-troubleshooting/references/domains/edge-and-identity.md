# Edge / identity

North-south failures at `*.duynh.me`: routing, policy, rate limits, upstream
health, JWT/JWKS, and the identity provider behind them.

## Authoritative docs

- Edge model + symptom tables: [platform/envoy-gateway.md](../../../../../docs/platform/envoy-gateway.md).
- Edge alerts: `docs/observability/runbooks/envoy-gateway/`
  ([index](../../../../../docs/observability/runbooks/envoy-gateway/README.md)).
- Identity provider: [platform/keycloak.md](../../../../../docs/platform/keycloak.md);
  Keycloak alerts: `docs/observability/runbooks/keycloak/` (per-alert; no README yet).
- Verification contract (realms, edge vs in-service): [api/identity.md](../../../../../docs/api/identity.md).

## Manifests

- `kubernetes/infra/configs/envoy-gateway/` (routes, SecurityPolicy, certificate).
- Edge cert is served by Envoy; issuance is cert-manager — see
  [secrets-tls](secrets-tls.md).

## Diagnose

| Symptom | First look |
|---|---|
| Mass 401 at the edge | JWKS reachability from the gateway; Keycloak up; realm/issuer config |
| 404 / wrong route | HTTPRoute merge, Host header must be a `*.duynh.me` name |
| 429 | rate-limit SecurityPolicy; local-first limiter (ADR-045) |
| 5xx / upstream unhealthy | upstream Service endpoints, pod health — then [applications](applications.md) |

```bash
make edge-isolation ARGS=--live   # edge NetworkPolicy allow-list sweep
```

Access from a host without the hosts file / 80-443 mapping: port-forward the
edge Service, keeping the `*.duynh.me` Host header — see
[platform/setup.md](../../../../../docs/platform/setup.md).

## Boundary

- Current edge is **Envoy Gateway**. Kong docs are historical — ignore unless
  the request is about the migration.
- A firing `Edge*`/`EnvoyGateway*` alert goes to its runbook file; the symptom
  tables are for exploratory, alert-less investigation.
