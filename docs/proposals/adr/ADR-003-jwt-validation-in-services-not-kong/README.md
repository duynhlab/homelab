# ADR-003: Keep JWT validation in services, not at the Kong gateway

| Status | Date | Related RFC |
|--------|------|-------------|
| Superseded by [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) | 2026-06-20 | — |

> **Superseded by [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) (2026-06-30).** The
> revisit trigger below (move to RS256/ES256) was met: [RFC-0009](../../rfc/RFC-0009/)
> adopts signed RS256 JWTs + Kong edge auth as defense-in-depth. Services still
> validate (ADR-003's other half stands); ADR-006 *adds* an edge check and reverses the
> "no Kong `jwt` plugin" stance. Body kept unchanged below for history.

## Context

Kong is the single public API gateway (`gateway.duynh.me`), deployed as the Kong Ingress
Controller in **DB-less** mode with **`plugins: "bundled"` (OSS only)**. Today every backend
service validates the request JWT itself — `pkg/authmw` (fail-closed) verifies the token and
resolves identity via `auth.GetMe` over gRPC. JWTs are minted by the in-cluster `auth-service`.
The `ingress-api.yaml` routes are pure pass-through and already state *"Services keep validating
JWTs themselves… Kong does not enforce auth."*

The TODO backlog listed "Plugins: … JWT/auth" for Kong, so we evaluated moving JWT verification to
the gateway with Kong's OSS `jwt` plugin (signature + registered-claim checks against a
pre-registered `KongConsumer` credential keyed by the token's `iss`).

## Decision

**Do not add the Kong `jwt` plugin. JWT validation stays in the services (`pkg/authmw`).** Kong
remains an auth-agnostic pass-through proxy; edge hardening is provided by the plugins it already
runs (CORS, rate-limiting, request-size-limiting) plus the security-headers and correlation-id
plugins added alongside this ADR.

## Alternatives considered

### Add the Kong OSS `jwt` plugin on `…/private/` routes
- **How it would work:** a shared `KongConsumer` + a `jwt` credential Secret (`key` = the token's
  `iss`, `secret` = HS256 key or `rsa_public_key` for RS256/ES256); the plugin attached to private
  Ingress paths only, leaving `…/public/` anonymous.
- **Pros:** sheds obviously-invalid tokens (bad signature / expired) at the edge before they reach
  pods; centralises a first-line check.
- **Cons / rejected because:**
  1. **Redundant** — services already do fail-closed validation *and* identity resolution
     (`auth.GetMe`), role checks, and revocation/logout handling. Kong's `jwt` only checks
     signature + `exp`/`nbf`; it cannot replace the in-service check.
  2. **Validation drift** — two independent validators (Kong vs `authmw`) diverge over time on
     algorithm rotation, `iss` changes, clock skew, and claim policy, creating a second source of
     truth for a security control.
  3. **Key-exposure risk** — `auth-service` currently signs with a symmetric key (HS256 is the
     common default; not confirmable from this repo). Wiring Kong then means **handing the signing
     secret to the gateway**, which could mint valid tokens — strictly worse blast radius.
  4. **Operational cost** — requires splitting the mixed public/private Ingresses, a shared
     consumer + credential Secret per namespace, and key-rotation choreography between auth-service
     and Kong — disproportionate for a homelab.

### Enterprise `openid-connect` / `jwt-signer`
Rejected: not available under `plugins: "bundled"` (OSS only); would also re-introduce the
drift/centralisation concerns above.

## Consequences

- Auth remains exactly one source of truth (`pkg/authmw` + `auth.GetMe`); no gateway-side auth
  config to keep in sync. NetworkPolicy continues to fence `internal` routes.
- Kong does **not** reject unauthenticated traffic to `…/private/` routes — services do (they
  return 401). This is intentional defense-in-depth at the service, not the edge.
- **Revisit trigger:** if `auth-service` moves to **RS256/ES256** (so Kong can hold only the
  **public key**) *and* we need to shed bad tokens before they reach pods at scale, re-open this
  ADR. The implementation shape (KongConsumer + `jwt` credential + per-private-route plugin) is
  recorded in the gateway research notes for that future case.
