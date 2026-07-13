# ADR-006: Adopt RS256 signed JWTs + Kong edge authentication

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted (implemented) | 2026-06-30 | [RFC-0009](../../rfc/RFC-0009/) |

> **Don't forget: every decision is a tradeoff.** This decision buys edge-side
> rejection of bad tokens and a stateless, offline-verifiable identity — at the cost
> of losing instant revocation and taking on JWKS/key-rotation machinery.

## Context

Authentication today uses **opaque, DB-backed session tokens**: `auth-service` mints a
32-byte random token, stores it in a `sessions` row, and every authenticated request
is validated by services calling `auth.GetMe` over gRPC (a Postgres lookup per
request). [ADR-003](../ADR-003-jwt-validation-in-services-not-kong/) decided to **keep
validation in the services** and leave Kong an auth-agnostic pass-through, *explicitly*
recording a revisit trigger: *"if auth-service moves to RS256/ES256 … re-open this
ADR."*

[RFC-0009](../../rfc/RFC-0009/) proposes exactly that move — to signed RS256 JWTs and
Kong edge authentication — and was accepted. This ADR records the resulting decision.

## Decision

**We will adopt signed RS256 JWTs and enable Kong OSS `jwt` edge authentication, as
defense-in-depth.** Concretely:

1. **`auth-service` mints RS256 access JWTs** (standard claims `iss`/`aud`/`sub`/`exp`
   /`iat`/`nbf`/`jti` + `username`/`email` + a `roles` placeholder; `kid` header) and
   publishes its **public key at a JWKS endpoint**. The private signing key stays in
   `auth-service` / OpenBAO; verifiers receive only the **public** key.
2. **Services verify the JWT locally** (`pkg/authmw`) against a cached JWKS — removing
   the `auth.GetMe` call from the request hot path. Services remain the **authoritative**
   fail-closed validator and the source of identity claims.
3. **Kong runs the OSS `jwt` plugin** on `…/private/` routes as the **coarse, first-line**
   check (signature + `exp`), rejecting obviously-bad tokens before they reach pods.

This **reverses ADR-003's "do not add the Kong `jwt` plugin" stance.** It does *not*
reverse ADR-003's other half — services still validate; edge validation is *added on
top*, not substituted. Because auth-service signs with an asymmetric key and Kong holds
only the public key, ADR-003's key-exposure objection no longer applies.

## Alternatives considered

- **Keep ADR-003 (service-only validation).** Simpler, one source of truth, but no
  early rejection at the edge and keeps the `GetMe` hot-path hop. Rejected: RFC-0009's
  revisit trigger is met and edge pre-filtering has real value.
- **Symmetric HS256 JWT.** The shared secret would have to reach Kong and every
  service — any could *mint* tokens. Rejected: RS256 keeps minting power solely in
  auth-service (this is ADR-003's key-exposure point, now resolved by going asymmetric).
- **Edge-only auth (no service check).** A misconfigured route or any in-cluster path
  would bypass all auth. Rejected: defense-in-depth is the production norm.
- **Kong Enterprise `openid-connect`** (auto JWKS discovery, introspection). Not in OSS
  `bundled`; documented for comparison in RFC-0009, not adopted.

## Consequences

- **Gained:** offline-verifiable identity; no `auth.GetMe` per request; bad tokens shed
  at the edge; standard claims enable future authz (`roles`) and tooling.
- **Lost — instant revocation.** A stateless JWT cannot be un-issued; a leaked access
  token is valid until `exp`. Mitigated by a short access TTL (1 h) + refresh-token
  rotation with reuse-detection; an optional Valkey `jti` denylist is held in reserve
  (RFC-0009 O2).
- **Operational cost.** A JWKS endpoint, key rotation, and — under OSS — **manual edge
  key choreography** (Kong holds a static public key, not JWKS); two places that verify
  must stay consistent.
- **Phased rollout — completed 2026-07-02.** Rollout followed RFC-0009: Phase 2 (auth
  mints JWT + JWKS) → Phase 3 (`pkg/authmw` local verify) → Phase 4 (Kong edge plugin)
  → Phase 5 (cutover: opaque session tokens, the `sessions` table and the `auth.GetMe`
  gRPC fallback are gone — JWT is the only credential; logout revokes the refresh-token
  family).
- **Revisit trigger:** adopting a service mesh ([RFC-0006](../../rfc/RFC-0006/)) could
  move edge/identity concerns into the mesh; moving to an external IdP / Enterprise
  OIDC would replace the OSS `jwt` edge mechanism. Re-open this ADR in either case.
</content>

---
_Last updated: 2026-07-02_
