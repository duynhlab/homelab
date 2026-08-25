# ADR-044: Make Envoy Gateway the platform edge on the Gateway API

> **Decision summary:** We will replace Kong OSS 3.9 with **Envoy Gateway** as the
> platform's only edge, routed by standard Gateway API resources plus EG policy CRDs,
> with edge JWT verification moving from a statically provisioned RS256 credential to
> SecurityPolicy `remoteJWKS` against the Keycloak realm — because Kong Inc. froze the
> OSS line (no 3.10+, unannounced EOL) and Kong OSS cannot fetch JWKS. We accept a
> ~150-file greenfield rebuild and a quarterly upgrade duty in exchange for a
> CNCF-governed edge, portable standard routing, and a rotation-transparent Keycloak
> integration built exactly once. **ADR-006's principle survives, re-homed:** the edge
> does coarse checks; services (`pkg/authmw`) remain the authoritative fail-closed
> verifier.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-11 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Which product is the platform edge, and in which config dialect it is driven. Rate-limit semantics and the local E2E gate are split out (see Related ADR). |
| **Affected components** | `kubernetes/infra/controllers/kong/` → Envoy Gateway HelmReleases, `kubernetes/infra/configs/kong/` → Gateway API + EG policy CRs, 31 Ingresses → HTTPRoutes, 11 NetworkPolicies, Kong monitoring (alerts, recording rules, dashboard, OTTL filter), ESO `auth-issuer-jwt`, Kyverno `kong-openbao` exception, `docs/platform/` |
| **Related RFC** | [RFC-0024](../../rfc/RFC-0024/) |
| **Related research** | [research.md](../../rfc/RFC-0024/research.md) |
| **Related ADR** | [ADR-041](../ADR-041-keycloak-platform-idp/) (adopt Keycloak as platform IdP — the realm this edge trusts, per RFC-0022), [ADR-045](../ADR-045-local-first-edge-rate-limiting/) (edge rate limiting), [ADR-046](../ADR-046-e2e-gate-kind-fallback/) (local E2E gate), [ADR-003](../ADR-003-jwt-validation-in-services-not-kong/) / [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) (the Kong-era decisions this record re-homes) |
| **Supersedes** | [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) (vehicle only — the edge-coarse/service-authoritative split is preserved) |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0024 program — P2/P4/P5 trains |
| **Adoption** | **Complete** — Envoy Gateway is the only edge and the Kind gate passed 2026-08-25: K4.1 plain HTTP redirects, K4.2 TLS is `homelab-ca`, K4.3 routing is by Host header, K4.8 the realm fence holds |

## Context

The platform's only edge is **Kong OSS 3.9**, deployed as KIC in DB-less mode:
31 Ingresses (`ingressClassName: kong`), 10 KongClusterPlugins, 5 KongUpstreamPolicies
plus 25 `konghq.com/*` Service annotations, a Kong-shaped monitoring surface
(13 alerts + 20 recording rules keyed to `kong_*` metrics — repo-verified count; the
RFC text said 19 recording rules), and a bespoke 283-line `kong.yml` dialect in
local-stack. Kong Inc. froze that line in 2025: **no OSS 3.10+ exists in any form**,
the unlicensed Enterprise image runs with a read-only Admin API (unusable for this
platform's DB-less config push), and the 3.9 maintenance line has **no published
end-of-support date**.

The freeze collides with the identity program. [RFC-0022](../../rfc/RFC-0022/README.md)
moves identity to Keycloak, but Kong OSS's `jwt` plugin **cannot fetch JWKS** — it
holds a statically provisioned RS256 public key ([ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/)'s
vehicle), forcing a static-key ESO fan-out (`ExternalSecret auth-issuer-jwt`) and a
manual edge step in the key-rotation runbook; [RFC-0023](../../rfc/RFC-0023/README.md)'s
`protected` routes get only signature+exp at this edge, no role awareness. Building
the Keycloak edge on Kong means building it twice. RFC-0022 recorded a
gateway-distribution exit trigger; the owner activated it proactively on 2026-08-10
after a verified 24-criteria comparison (**EG 14 / tie 4 / Kong 1** —
[criteria matrix](../../rfc/RFC-0024/research.md#vs-platform-as-built)).

## Scope

### In scope

- The edge product: Envoy Gateway replaces Kong OSS as the platform's **only** edge.
- The config dialect: standard Gateway API (GatewayClass/Gateway/HTTPRoute) plus EG
  policy CRDs (SecurityPolicy, BackendTrafficPolicy, ClientTrafficPolicy, EnvoyProxy,
  Backend).
- The edge JWT vehicle: SecurityPolicy `remoteJWKS` against the Keycloak realm,
  including the in-cluster IdP pattern (`Backend` + `BackendTLSPolicy`), and the edge
  claim-authorization gate on `protected` routes.
- Cutover style (greenfield, no parallel-run) and the Kong decommission/archive rule.
- The version floor and pinning discipline (≥ v1.8.3, tag + digest).

### Out of scope

- Edge rate-limiting semantics — decided by [ADR-045](../ADR-045-local-first-edge-rate-limiting/).
- Where the local E2E release-audit gate runs — decided by [ADR-046](../ADR-046-e2e-gate-kind-fallback/).
- The identity design itself (realm, clients, claims, TTLs, `user_id` migration) —
  RFC-0022 is the design record; ADR-041 records its adoption.
- OIDC-at-edge for the SPAs (`keycloak-js` stays; EG's OIDC filter is recorded
  capability, not adopted), service mesh / east-west mTLS, ext_authz/OPA.
- Any service API path, host name, or audience vocabulary — all survive as-is.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Distribution viability | The edge is the security perimeter; a frozen line with unannounced EOL is one unpatched CVE from a forced migration. EG ships quarterly minors with live patch streams under CNCF governance |
| 2 | Build the Keycloak edge once | `remoteJWKS` makes the RFC-0022 integration native: zero provisioned key material, rotation-transparent. On Kong, the same integration needs a static-key ESO fan-out and a manual rotation step — then gets rebuilt anyway |
| 3 | Standard, portable config | Gateway API routes survive a future gateway change; Kong's Ingress-plus-vendor-annotations and the local `kong.yml` dialect do not |
| 4 | Preserve defense-in-depth | ADR-006's edge-coarse/service-authoritative split is a working security posture; the migration must re-home it, not weaken it |
| 5 | Edge telemetry | The edge is the fleet's tracing root and access-log source; EG's ParentBased sampler matches the fleet model, and its JSON logs + CEL filters resolve standing audit findings (F-2, F-8) |

## Decision

We will make **Envoy Gateway the platform's only edge**, pinned at **≥ v1.8.3** by tag
**and digest**, replacing Kong OSS 3.9 in a **greenfield cutover** — no parallel-run,
because Kind environments rebuild constantly and the production cluster contains no
Kong.

Routing is standard **Gateway API**: one GatewayClass, Gateways per host class
(`gateway.duynh.me`, `local.duynh.me`, admin hosts), and HTTPRoutes for all 31 ingress
surfaces. Everything the standard API does not cover attaches as EG policy CRDs:
**SecurityPolicy** (JWT, claim authorization, CORS, CIDR fencing),
**BackendTrafficPolicy** (retries, timeouts, health checks, request buffer, rate
limiting per ADR-045), **ClientTrafficPolicy**, **EnvoyProxy** (telemetry), and
**Backend** (non-Service upstreams).

Edge JWT verification moves from ADR-006's statically provisioned RS256 credential to
SecurityPolicy **`remoteJWKS`** against the Keycloak realm — zero provisioned key
material, rotation-transparent; the in-cluster IdP is reached via `Backend` +
`BackendTLSPolicy`. `protected` routes (RFC-0023) additionally gain an edge claim
gate: `realm_access.roles` must contain `backoffice_admin`. **This supersedes the Kong
vehicle of ADR-006 — and transitively ADR-003's Kong framing — while preserving the
principle both records converged on:** the edge does coarse checks; services
(`pkg/authmw`) remain the authoritative fail-closed verifier.

Kong is decommissioned completely — HelmRelease, all plugin/consumer CRs, the
`auth-issuer-jwt` ExternalSecret, the `kong_*` monitoring surface, the OTTL
deprecation filter, and the Kyverno `NET_BIND_SERVICE` exception — while Kong
**documentation is archived read-only** (banner, no rewrite) as platform history.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Envoy Gateway is the only edge. No second gateway, no Kong resource, and no parallel-run state may be introduced. |
| **Config dialect** | Routing changes are expressed as Gateway API resources + EG policy CRDs. No vendor annotations on Ingresses; no new bespoke gateway config dialect anywhere (cluster or local). |
| **Edge auth** | Edge JWT verification uses `remoteJWKS` against the Keycloak realm only. No provisioned key material, no credential Secret, no ESO path may reappear at the edge. |
| **Authority** | Services (`pkg/authmw`) remain the authoritative fail-closed verifier. Edge checks (signature/iss/aud/exp, role claim on `protected`) are additive; no route may rely on the edge as its only auth layer. |
| **Version pin** | The EG chart/images are pinned ≥ v1.8.3 by tag + digest; quarterly minor upgrades are a standing duty, watched by Renovate. |
| **Decommission** | Kong configs and monitoring are deleted, not disabled. Kong docs (`docs/platform/kong-gateway.md`, ADR-003/006) are archived read-only with banners/superseded-by links — never rewritten. |

### Decision view

```mermaid
flowchart LR
    Client["SPAs / clients"] --> GW["Envoy Gateway (planned)<br/>Gateway API routes<br/>SecurityPolicy remoteJWKS"]
    KC["Keycloak realm duynhlab"] -.->|"JWKS auto-refresh (planned)"| GW
    GW --> Svc["Owning services<br/>pkg/authmw — authoritative"]
    Kong["Kong OSS 3.9<br/>static RS256 credential"] -.->|"decommissioned"| GW

    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;

    class Client edge;
    class Svc service;
    class KC platform;
    class Kong external;
    class GW planned;
```

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Envoy Gateway** | CNCF governance, live patch streams; free JWKS/claim-authz; standard portable routing; telemetry model matches the fleet | ~150-file rebuild; quarterly upgrade duty; standalone-mode maturity unproven (ADR-046 owns the fallback) | Selected |
| **B — Stay pinned on Kong OSS 3.9** | Zero work now; patches still flowing today | Frozen features, unannounced EOL; permanent static-key edge for Keycloak; RFC-0022/0023 edge artifacts built twice; the exit trigger the owner already activated | Rejected |
| **C — Kong Gateway Enterprise** | `openid-connect` plugin (JWKS at edge); vendor support | Enterprise pricing for one feature; the unlicensed image is unusable (read-only Admin API); rejected in RFC-0022 research and re-confirmed | Rejected |
| **D — APISIX** | Apache-governed, free openid-connect, active community | Second config dialect (not Gateway API-native to the same depth); loses the standard-YAML-everywhere prize. **Recorded as the fallback vendor** if EG ever dead-ends the way Kong did | Rejected |
| **E — Drop edge JWT entirely** | Nothing to migrate for auth | A gateway is still needed for routing/TLS/rate-limit; discards ADR-006's defense-in-depth for ~zero savings once `remoteJWKS` exists | Rejected |

### Why the selected option won

Envoy Gateway is the only option that satisfies drivers 1–3 simultaneously: a
governed, patched distribution, a JWKS-native edge that makes the Keycloak
integration a one-time build with no key material, and routing in the
Kubernetes-standard dialect that would largely survive even a future gateway change.
The 24-criteria review scored it ahead on 14 criteria with 4 ties and a single Kong
win (compose maturity — which ADR-046 handles with a spike and an approved fallback).

### Why the closest alternative lost

Staying pinned (B) is the closest option because it costs nothing today — and that is
exactly its trap. The platform is about to build its Keycloak edge; on Kong that edge
is a static-key ESO fan-out plus a manual rotation step, both existing only because
of a limitation of a product line whose end date its vendor will not publish. Every
month of delay adds Kong-shaped artifacts the eventual forced migration deletes.
Moving before RFC-0022/0023 implement means the identity edge is built once, on the
survivor.

## Consequences

### Positive consequences

- Edge key rotation becomes invisible: `remoteJWKS` auto-refreshes, so the
  `auth-issuer-jwt` ExternalSecret and the manual edge rotation step are never built.
- `protected` routes gain an edge role gate (403 before the request enters the
  cluster) — impossible on Kong OSS — while services stay authoritative.
- Routes become portable standard YAML; the local `kong.yml` dialect dies (ADR-046);
  the edge rejoins a patched, CNCF-governed release train.
- Standing telemetry findings improve by migration: F-8 (frozen semconv) resolves,
  F-2 (unfilterable probe logs) gains CEL filtering at source, F-7's sampling model
  (ParentBased, 0.1) carries over as a number copy, not a redesign.

### Negative consequences and accepted trade-offs

- A real migration across ~150 files, with observability as the L-sized risk area:
  13 alerts + 20 recording rules on `kong_*` rewritten on `envoy_*`, dashboards
  swapped, the Vector `kong_json` pipeline re-mapped once.
- Quarterly upgrade duty replaces "pin and forget" (owner: accepted); Kong plugin
  intuition resets to Gateway API + Envoy semantics.
- 11 NetworkPolicies keyed to the `kong` namespace must be re-pointed — the
  highest-silence risk (traffic blackholes); swept with a checklist and Kind
  verification.
- Greenfield cutover means rollback is source-level (revert the PR train and
  rebuild), never a runtime toggle.

### Neutral consequences

- No service API, route path, host name, or audience class changes; the edge's
  NodePort exposure (30080/30443) carries over unchanged.
- ADR-003/ADR-006 stay in the record with superseded-by links; RFC-0009 gains one
  more superseded-in-part note; CHANGELOG history is untouched.
- The identity work itself (Keycloak deploy, auth-service retirement) executes in
  the same program but is owned by the RFC-0022 design record and ADR-041.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Gateway API CRDs + EG HelmReleases in the Flux chain (`cert-manager → gateway-api-crds → envoy-gateway → envoy-gateway-config`) | platform | RFC-0024 P2 | `make validate` green; EG reconciles on Kind |
| Gateway + HTTPRoutes for all 31 surfaces; SecurityPolicies (remoteJWKS, claim authz, CIDR, CORS); BTP; Kong deleted from the cluster chain | platform | RFC-0024 P2 | Scripted route-parity diff passes; Kong resources gone |
| Rewrite the 13 alerts + 20 recording rules on `envoy_*`; dashboards + Vector schema; delete the OTTL Kong filter | platform | RFC-0024 P4 | Alert catalog §2 rewritten; every rewritten alert fired synthetically |
| Decommission sweep: ESO secret, 11 NetworkPolicies re-pointed, Kyverno exception dropped, scripts re-pointed | platform | RFC-0024 P5 | Connectivity matrix from the EG namespace passes |
| Docs: create `docs/platform/envoy-gateway.md`; archive `docs/platform/kong-gateway.md` (banner); superseded-by links on ADR-003/006; `docs/api/api.md` edge-exposure prose | platform | RFC-0024 P5/P6 | No doc describes Kong as current |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Route parity | Scripted diff of every host/path/audience pair before/after (31 surfaces, incl. temporal-ui); 404/401/403 per audience class re-asserted |
| Edge auth | Valid/invalid/expired Keycloak tokens rejected at edge **and** service; `protected` returns 403 without `backoffice_admin`; realm key rotation requires no edge action |
| Service authority | `pkg/authmw` untouched; a request bypassing the edge is still rejected by the service (fail-closed) |
| No Kong residue | Repo grep: no `konghq.com/*`, `KongClusterPlugin`, `kong.yml`, or `job="kong"` outside archived docs |
| Telemetry | Trace continuity SPA→edge→service (ParentBased); rewritten alerts fired; probe-filter CEL proven by volume delta |
| Documentation | `docs/api/api.md` edge exposure and `docs/platform/envoy-gateway.md` link this ADR |

## Amendments

### 2026-08-17 — CRD delivery moves from Helm to server-side apply

The decision above is unchanged: Envoy Gateway is the edge, driven by Gateway
API resources. What changes is **how its CRDs reach the cluster**.

The first Kind bring-up of this layer proved the planned mechanism cannot work.
The `gateway-crds-helm` chart ships CRDs in `templates/`, so Helm stores both
the rendered manifest and the whole chart in the release Secret:

| Delivery path | Measured | Ceiling | Result |
|---------------|----------|---------|--------|
| HelmRelease (planned) | release Secret ~2.06 MB | 1 MiB — `Secret` validation | rejected by the API server |
| `kubectl apply`, client-side | `envoyproxies` CRD 1.35 MB | 256 KB — `last-applied-configuration` annotation | rejected |
| **Server-side apply** (adopted) | 18 objects | — | applies |

The ceiling is structural, not a misconfiguration. Helm stores the parent
chart's `templates/` plus the rendered manifest in the release Secret;
subcharts are not stored (verified by decoding a live release: `dependencies`
is empty). `gateway-crds-helm` puts the CRDs in the **parent** chart's
`templates/`, so both copies land in the Secret. `channel: standard` still
packages the unused experimental file, and removing it leaves ~1.63 MB; chart
`v1.9.0` packages the same way and is larger still.

**This is a documented upstream limitation, and the fix here is upstream's own
recommendation.** Envoy Gateway's install guide says to install the CRDs
separately with `helm template … | kubectl apply --server-side -f -`
"due to a Helm limitation with large CRDs", and to install the controller chart
with `--skip-crds`. Applying a vendored render through a Flux Kustomization —
which uses server-side apply — is the GitOps translation of exactly that
command; the command itself is preserved in the directory's README.

The alternative of letting the controller chart install its own CRD subchart
was rejected on **channel**, not on size: that subchart's release Secret would
stay in the tens of KB, but it ships the Gateway API **experimental** channel
with no option to select standard, in `v1.8.3` and `v1.9.0` alike. This
platform routes only HTTP and gRPC and deliberately runs the standard channel.

**Amended decision:** `kubernetes/infra/controllers/gateway-api-crds/` holds the
CRDs as vendored manifests, applied by the existing `gateway-api-crds-local`
Flux Kustomization, which uses server-side apply. The controller HelmRelease
keeps `crds: Skip` and additionally sets
`crds.gatewayAPI.safeUpgradePolicy.enabled: false`, so the `safe-upgrades`
ValidatingAdmissionPolicy has exactly one declared owner.

**Accepted trade-off:** ~3.4 MB of generated YAML in git, and an Envoy Gateway
upgrade now requires re-rendering that directory in the same change as the
controller pin. The regeneration command is in
[`gateway-api-crds/README.md`](../../../../kubernetes/infra/controllers/gateway-api-crds/README.md).

**Obligation added:** the "Gateway API CRDs + EG HelmReleases in the Flux chain"
row above is satisfied by the Kustomization, not by a second HelmRelease.

### 2026-08-18 — Envoy Gateway v1.9.0, and the CRD delivery argument re-verified at source

The decision and the delivery mechanism are both unchanged. This amendment
bumps the pin, adopts a cleaner switch for the same intent, and — because the
previous amendment's reasoning was challenged in review — records the source
evidence behind it so the next reader does not have to re-derive it.

#### The subchart rejection is confirmed, not corrected

A review argued that Amendment #1's claim — that the CRD subchart offers no way
to select the standard channel — was false, on the grounds that
`crds.gatewayAPI.channel: standard|experimental` demonstrably exists. Both
chart packages were unpacked at `v1.8.3` and `v1.9.0` and compared directly.
**Amendment #1 is confirmed.** The toggle is real, but it belongs to a
different chart than the one Amendment #1 rejected:

| Chart | Channel control | Where its CRDs live | Blocked by |
|-------|-----------------|---------------------|------------|
| `gateway-crds-helm` (standalone, CRD-only) | `crds.gatewayAPI.channel` | parent `templates/` | **size** — 1 MiB `Secret` |
| `gateway-helm/charts/crds` (subchart of the controller chart) | none — `values.yaml` is three lines, no `channel` key | `crds/` + `crds/generated/` | **channel** — experimental only |

The subchart's complete `values.yaml` is `gatewayAPI.safeUpgradePolicy.enabled`
and nothing else, and every Gateway API CRD it ships carries
`gateway.networking.k8s.io/channel: experimental` — 13 of 13 at `v1.9.0`, 12 of
12 at `v1.8.3`. Selecting `standard` in the standalone chart does not rescue
that chart either: the unused experimental bundle (1.40 MB) stays packaged
regardless, and a full render — standard channel plus the Envoy Gateway
extension CRDs, which is what one HelmRelease would have to carry — is 3.73 MB.

So both rejections in Amendment #1 stand, and they are **not
interchangeable** — the size ceiling applies to the standalone chart, the
channel constraint to the subchart. Neither chart can deliver the standard
channel inside a Helm release, which is why vendor + server-side apply remains
the only path. The two charts are easy to conflate; the directory README now
names both in full for that reason.

#### Upstream evidence

The ceiling is a known, open upstream limitation, not a local misconfiguration.
[envoyproxy/gateway#6105](https://github.com/envoyproxy/gateway/issues/6105)
("gateway-crds-helm v1.4.0 install fails – rendered release exceeds 1 MiB
Secret size limit", open since 2025-05-18):

- maintainer **arkodg** confirms it as a known issue and points at the official
  [Installing CRDs separately](https://gateway.envoyproxy.io/docs/install/install-helm/#installing-crds-separately)
  procedure — the `helm template … | kubectl apply --server-side` route this
  directory implements as GitOps;
- **hovvsoon** reports that splitting the CRDs across separate charts or
  separate `HelmRelease` resources still breaches the limit, which closes off
  the "just use two HelmReleases" alternative for Flux users specifically;
- **98jan** shows a Flux setup that works only by bypassing Helm, and notes the
  CRD files under `gateway-crds-helm/templates/` are Helm-templated and so are
  not consumable as raw manifests — the reason this directory vendors a
  *rendered* copy rather than pointing a `GitRepository` at upstream;
- **aukevanleeuwen** posts the Terraform equivalent (`helm_template` +
  `kubectl_manifest` with `server_side_apply = true`), independently arriving at
  the same shape as this platform's Kustomization;
- maintainer **zirain** attributes the size to too much having been packed into
  a single CRD, and notes those APIs cannot simply be dropped without breaking
  compatibility — so no near-term upstream fix should be assumed.

#### Adopted: `crds.enabled: false`

[PR #8850](https://github.com/envoyproxy/gateway/pull/8850) added a
`crds.enabled` dependency toggle to `gateway-helm`, announced in the `v1.9.0`
release notes. It is in fact already present and functional in the pinned
`v1.8.3` chart (`Chart.yaml` carries `- condition: crds.enabled` and
`values.yaml` `crds.enabled: true` in both packages) — so this is an
availability correction, not a new capability, and the adoption is not gated on
the bump.

The HelmRelease now sets `crds.enabled: false`, which drops the subchart as a
dependency outright. Verified by rendering `gateway-helm` `v1.9.0` both ways:
with the flag off the release manifest is 19 KB and contains zero CRDs and zero
`ValidatingAdmissionPolicy` objects; with it on, the `safe-upgrades` policy and
its binding appear. `crds.gatewayAPI.safeUpgradePolicy.enabled: false` is kept
deliberately redundant — it is the switch upstream documents for externally
managed Gateway API CRDs, and it keeps that object single-owned even if the
dependency is ever re-enabled. `crds: Skip` stays on install and upgrade as a
third line of defence.

[PR #9024](https://github.com/envoyproxy/gateway/pull/9024) is the reason the
VAP needs handling at all: it moved those resources out of a `crds/` directory
into chart templates precisely because **Flux treats everything under `crds/`
as a CRD** ([#9015](https://github.com/envoyproxy/gateway/issues/9015)). The
`v1.9.0` notes list it as a breaking change, but the layout is identical in the
`v1.8.3` package already in use — which is why this repository has needed
`safeUpgradePolicy.enabled: false` since Amendment #1 and sees no behavior
change here.

#### Bundle and version moves

- **Envoy Gateway `v1.8.3` → `v1.9.0`** (chart digest
  `sha256:06e7c26e50d40f0b98d6d1243a3c8dd094464c6099df727216876c19401ffe5f`,
  published 2026-08-15). Security carries the bump on its own: Go 1.26.6, a
  read-only container root filesystem, and a `GatewayNamespaceMode` bypass fix.
- **Gateway API `v1.5.1` → `v1.6.1` is mandatory, not optional.** `v1.9.0`
  reconciles `TCPRoute`/`UDPRoute` through `gateway.networking.k8s.io/v1`; if
  the `v1.6` bundle is absent those routes are *silently skipped*. The standard
  channel gains `tcproutes` and `udproutes`, taking this directory from 18 to
  20 objects.
- The vendored `safe-upgrades` policy moves to `bundle-version: v1.6.1`. Its own
  validation rejects Gateway API CRDs annotated `v1.0`–`v1.4` and experimental
  CRDs landing on standard ones; `v1.5.1` → `v1.6.1` standard passes both, so
  the policy cannot deadlock its own bundle bump.
- **Control-plane memory limit `512Mi` → `768Mi`.** The `EndpointSliceIndex`
  runtime flag now defaults on and indexes EndpointSlices in the controller;
  upstream explicitly asks operators to review and raise memory before
  upgrading, or opt out via `runtimeFlags.disabled`. Raising the ceiling is
  preferred to disabling an indexing improvement in a cluster this small.

#### Breaking-change assessment against the deployed manifests

`v1.9.0` carries 19 breaking changes. Each was checked against what this
platform actually applies — 21 `SecurityPolicy`, 14 `BackendTrafficPolicy`, 57
`HTTPRoute`, 2 `EnvoyProxy`, 11 `Backend`, across the cluster config and the
local stack — rather than assumed inert.

Two needed a real decision:

- **`EndpointSliceIndex` defaults on** → control-plane memory limit raised (see
  above).
- **The Gateway API `v1.6` requirement** → the vendored bundle moves with the
  controller (see above).

One came close to blocking the upgrade and is worth recording, because the
margin is thin. `SecurityPolicy.spec.mergeType` and
`BackendTrafficPolicy.spec.mergeType` are now **rejected on `Gateway`, Gateway
listener, and `ListenerSet` targets** and permitted only on xRoute targets.
This platform uses `mergeType: StrategicMerge` in 19 places, and it does target
a `Gateway` — but never both at once:

| Policy | `mergeType` | Targets | Verdict |
|--------|-------------|---------|---------|
| `jwt-edge`, `jwt-edge-staff`, `admin-cidr-internal` | `StrategicMerge` | `HTTPRoute` only | allowed — xRoute |
| `cors-policy` | none | `Gateway/platform` | allowed — no `mergeType` |
| all 14 `BackendTrafficPolicy` | none | `HTTPRoute` only | allowed |

So the gateway-wide CORS baseline is admissible only because it never needed
`mergeType` — the per-route policies are the ones that merge onto it. **Adding
`mergeType` to `cors-policy`, or re-targeting any merging policy at the
`Gateway`, is now an admission failure** rather than a silently-ignored field.

The remaining 16 are inert here, verified by absence rather than assumption: no
`ClientTrafficPolicy` (so no `clientIPDetection`), no `apiKeyAuth`, no
`wellKnownCACertificates: System` on any `Backend` or `BackendTLSPolicy`, no
TCP/UDP/TLS route, no `sessionPersistence`, no Lua `EnvoyExtensionPolicy`, no
SDS unix-socket URL, no shared-only global rate-limit rule, and — the reason
several of them cannot reach us — **no `EnvoyPatchPolicy` and no extension
server anywhere in the repository**, which is what the xDS-level renames
(JWT provider names, `typedPerFilterConfig`, `system_ca_certificates`, the
removed `use_eds_cache_for_ads` guard) require in order to bite. The
`XRateLimitHeadersOptionDisabled` fix is documented upstream as affecting no
existing manifest.

One is easy to misread and so deserves naming: **tracing client sampling now
defaults to 0% instead of 100%**. The new `clientSamplingFraction` field governs
whether a *caller-forced* sampling decision is honored; it is distinct from
`samplingRate`, which still exists on `EnvoyProxy` and still governs the
sampling this platform relies on — `10` in the infra baseline, patched to `100`
for local. The two remain mutually exclusive by CRD validation. Nothing here
ever depended on client-forced tracing, so edge sampling behavior is unchanged.

**Amended decision:** unchanged from 2026-08-17 in substance. The controller
HelmRelease adds `crds.enabled: false` to the existing `crds: Skip` and
`safeUpgradePolicy.enabled: false`, and the vendored bundle moves to Envoy
Gateway `v1.9.0` with Gateway API `v1.6.1`.

## Revisit triggers

Re-open this decision when one or more of the following become true:

- Envoy Gateway's distribution dead-ends the way Kong's did (frozen line, withdrawn
  patches) — APISIX is the recorded fallback vendor, and the Gateway API routes
  largely survive such a move.
- A service mesh adoption (RFC-0020/RFC-0006 territory) moves edge/identity concerns
  into the mesh.
- The quarterly upgrade duty proves materially heavier than the ~2 lines/year the
  research estimated, or the edge-coarse/service-authoritative split is invalidated
  (e.g. a requirement for edge-only auth or full OIDC-at-edge for the SPAs).

A review does not automatically reverse the decision. A changed decision requires a
new ADR that supersedes this one.

## References

- [RFC-0024](../../rfc/RFC-0024/) — the deciding RFC (before→after map, resource mapping, phases)
- [RFC-0024 research](../../rfc/RFC-0024/research.md) — criteria matrix, deep-dives, blast-radius inventory, Context7 audit
- [RFC-0022](../../rfc/RFC-0022/README.md) — identity design record executed by the same program
- [RFC-0023](../../rfc/RFC-0023/README.md) — `protected` route class gaining the edge role gate
- [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) / [ADR-003](../ADR-003-jwt-validation-in-services-not-kong/) — the superseded Kong-era decisions
- [ADR-045](../ADR-045-local-first-edge-rate-limiting/) · [ADR-046](../ADR-046-e2e-gate-kind-fallback/) — sibling edge decisions
- [`docs/platform/kong-gateway.md`](../../../platform/kong-gateway.md) — to be archived read-only
- [envoyproxy/gateway#6105](https://github.com/envoyproxy/gateway/issues/6105) — the open upstream issue behind the CRD delivery amendments

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Proposed inside the RFC-0024 review |
| 2026-08-11 | Accepted / Not started | Accepted with RFC-0024; numbering assigned 044–046 because ADR-039/040 were consumed by unrelated decisions (RFC text had said 045–047) |
| 2026-08-17 | Accepted / Partial | Amended: CRD delivery moves from a HelmRelease to vendored manifests applied server-side, after the first Kind bring-up proved the Helm path exceeds the 1 MiB `Secret` limit |
| 2026-08-18 | Accepted / Partial | Amended: Envoy Gateway v1.8.3 → v1.9.0 with Gateway API v1.6.1 (mandatory for the TCPRoute/UDPRoute `v1` move); adopted `crds.enabled: false`; re-verified Amendment #1's subchart rejection against both chart packages and recorded the upstream evidence |
| 2026-08-24 | Accepted / Partial | Documentation validation row satisfied: [`docs/platform/envoy-gateway.md`](../../../platform/envoy-gateway.md) now links this ADR (and 045/046) and carries a Design decisions section for both amendments — it had linked neither since it was created. Its resource counts were also trued up against the manifests, and both amendments' live constraints written down. Remaining for `Complete`: the Kind K-row gate pass |
| 2026-08-25 | Accepted / **Complete** | Kind gate passed. **The Documentation row is closed for real this time** — `docs/api/api.md` now links this ADR; the 2026-08-24 entry claimed that row was satisfied while only `envoy-gateway.md` linked it. |

---
_Last updated: 2026-08-25 — Adoption → **Complete** on the Kind gate pass (ELIGIBLE); the History row was appended in the same edit._
