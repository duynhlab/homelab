# RFC-0020 Internal TLS on the `homelab-ca` root

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| provisional | platform-wide | [./research.md](./research.md) — gate passed 2026-07-22 | 2026-07-22 | 2026-10-01 |

> **Don't forget: every decision is a tradeoff.** This RFC buys encrypted, identity-verified
> internal transport at the cost of per-tier certificate wiring, strict rollout ordering, and
> one more thing that can expire. The rejected alternatives and the drawbacks are recorded
> below and in [research § Alternatives](./research.md#alternatives).

## Prerequisites

- [x] [./research.md](./research.md) merged (#576); [research review gate](./research.md#research-review-gate) ticked (2026-07-22)
- [x] Context7 audit complete (#579 — PgDog, Istio, OpenBAO rows resolved)
- [x] Owner approved **ready for RFC** (2026-07-22)
- Mechanism deep-dive lives in [./research.md](./research.md) — this file records decisions, target architecture, and rollout only.

## Summary

Issue a leaf certificate from the already-deployed **`homelab-ca`** (cert-manager
`ClusterIssuer` + trust-manager root bundle) to **every internal endpoint** — CNPG Postgres,
the PgDog/PgBouncer pooler tier, east-west gRPC, and the OpenBAO listener — and decouple the
edge from Cloudflare/Let's Encrypt in the base overlay. One root, six rollout slices, no new
PKI component. All app→DB traffic goes through poolers (`payment`'s direct hop is retired),
apps land on `sslmode=verify-full` in one step, and gRPC mTLS (absorbed from superseded
RFC-0002) ships last as its own gated phase.

The **2026-10-01 amendment** (proposed, owner review pending) adds slices 7–14. They cover
the hops that the 2026-10-01 TLS review found plaintext or unverified, which no original
slice owned:
- the root CA's own hardening;
- Keycloak in-cluster;
- the platform-db clients outside the app fleet;
- Envoy → backends;
- RustFS;
- Valkey;
- the OCI registry;
- the KMS link.

The deployed state they start from is drawn in
[`docs/secrets/cert-manager.md` § 12](../../../secrets/cert-manager.md#12-tls-topology--which-hops-are-encrypted-today).

## Motivation

The platform runs a real private CA, but the only workload certificate it serves is the edge
wildcard `platform-edge-tls`, now held by Envoy Gateway (ADR-044; Kong is retired). Its other
two leaves, `openbao-idp-trust` and `flux-web-idp-trust`, exist only to carry the live CA's
`ca.crt`. Every internal hop is plaintext or shared-password over an optionally-encrypted
socket (re-verified 2026-10-01, see the TLS topology linked in the Summary). On any engagement this is the first internal pen-test / SOC-2 "encryption in transit"
finding, and three ADRs (005, 015, 025) each defer their TLS slice to "later" with no owner.
The PKI foundation is deployed and idle — this RFC puts it to work before the platform moves
to cloud. Full problem framing: [research § Problem statement](./research.md#problem-statement).

### Goals

- Every internal hop encrypted and server-verified against **one root** (`homelab-ca`):
  app→pooler→CNPG, service→service gRPC, everything→OpenBAO.
- All 10 services reach Postgres **through a pooler** with `sslmode=verify-full` — no
  direct-to-CNPG exceptions (`payment` returns behind `pgdog-product`).
- OpenBAO listener on TLS (`tls_disable = 0`) with cert-manager-issued cert (ADR-005 target).
- East-west gRPC on in-process mTLS via `pkg/grpcx`/`pkg/temporalx` (formerly RFC-0002).
- Edge issuer decoupled: base default `homelab-ca`; `letsencrypt-prod` becomes a prod overlay.
- One rotation policy: 90d leaves, renewed 30d before expiry, reload without restart.

### Non-Goals

- **No service mesh / SPIFFE** — rejected at this scale; mesh-later is owned by
  [RFC-0006](../RFC-0006/).
- **No OpenBAO PKI engine** — the CA stays in cert-manager. Moving key custody into OpenBAO
  is future work (chicken-and-egg with Slice 1: OpenBAO's own listener cert must exist before
  OpenBAO starts). The cert-manager Vault issuer keeps that migration open without touching
  workloads.
- **No change to CNPG replication** — `streaming_replica` cert-auth stays on CNPG's own
  auto-CA (never leaves the CNPG boundary).
- **No credential-model changes** — dynamic creds / rotation are RFC-0008; this RFC secures
  the transport those credentials travel over. T1/T2/T3 stack with it.
- **local-stack stays plaintext** — the compose e2e stack keeps its single-network trust
  model; this RFC is cluster-scoped.

## Proposal

Adopt **per-workload cert-manager TLS, in-process** (research option (a)) and climb the three
tiers — T1 encrypt, T2 verify-server, T3 client-cert — per plane, in six slices. Decisions
locked at the research gate (owner, 2026-07-22):

| # | Decision |
|---|----------|
| 1 | Root of trust: reuse `homelab-ca` + trust-manager — no new PKI component |
| 2 | **All app→DB via pooler** — no direct-to-CNPG; `payment`'s direct hop is transitional |
| 3 | CNPG server cert **re-issued from `homelab-ca`** via `spec.certificates` (apps keep one trust root) |
| 4 | Apps jump **straight to `verify-full`** (no intermediate `require` step) |
| 5 | **T3 is per-hop**: app→pooler mTLS (PgDog `tls_client_ca_certificate`); pooler→Postgres carries the pooler's identity (`hostssl … cert` authenticates the pooler; per-role auth stays password/`auth_query` on that hop) |
| 6 | Rotation: **90d lifetime / renew at 30d**, one policy for all internal leaves |
| 7 | `streaming_replica` stays CNPG-managed |
| 8 | Scope: **umbrella Slice 0–6**; Slice 6 (gRPC) last, gated, touches service repos |

**Proposed by the 2026-10-01 amendment.** These are not decided: the RFC stays `provisional`
and the owner has not reviewed them.

| # | Proposed decision |
|---|-------------------|
| 9 | Scope grows to **Slice 0–14**: slices 7–14 close the hops the 2026-10-01 review found outside slices 0–6 |
| 10 | Leaves are signed by an **intermediate CA** under `homelab-ca` (Slice 7). The root signs only the intermediate, carries an explicit `renewBefore`, and its key leaves day-to-day use; this is still cert-manager, so no new PKI component |
| 11 | The platform-db clients outside the app fleet (Temporal, the OpenBao database engine, Keycloak) follow the same `verify-full` rule as the apps. They connect direct to `platform-db-rw`, as `docs/databases` records, so Decision 2's "via pooler" does not apply to them |
| 12 | Envoy → backend TLS (Slice 10) is per backend, and only once that backend serves a `homelab-ca` leaf; no backend is switched to TLS just for the edge |

### User Stories

- *As the operator*, I can show an auditor that no internal hop carries data or passwords in
  cleartext, and that every endpoint proves its identity against one documented root.
- *As on-call*, when I rotate a database password (RFC-0008), the transport it travels over
  is encrypted and server-verified — a sniffed pooler hop no longer yields credentials.
- *As a service author*, I get TLS by following the platform pattern (mount the trust bundle,
  set `sslmode=verify-full`) — no per-service PKI decisions.

### Alternatives

Rejected (full analysis in [research § Alternatives](./research.md#alternatives)): service
mesh (disproportionate for ~9 hops — RFC-0006), SPIFFE/SPIRE (heavy control plane before
cloud), OpenBAO PKI engine (bootstrap circularity — future work), status quo (leaves the
finding open; NetworkPolicy answers "who may connect", never "which service is this").

## Architecture & Diagrams

Target state — every leaf signed by the same root (adapted from
[research § Core mechanism](./research.md#core-mechanism); all internal leaves **planned**):

> **The edge leaf moved with the RFC-0024 cutover.** It was the Kong edge cert
> and is now the Envoy Gateway listener certificate `platform-edge-tls`
> ([ADR-044](../../adr/ADR-044-envoy-gateway-platform-edge/)). The leaf itself
> stays in scope for this RFC — only the workload holding it changed. The
> internal leaves, which are what this RFC is about, are unaffected and still
> **planned**.

```mermaid
flowchart TD
  root["homelab-ca<br/>(root of trust)"] --> issuer["CA ClusterIssuer<br/>+ trust-manager bundle"]
  issuer -->|"server auth"| edge["Envoy Gateway edge cert<br/>(base default; prod: LE overlay)"]
  issuer -->|"server auth · planned"| dbsrv["CNPG server cert<br/>apps verify-full"]
  issuer -->|"server+client · planned"| pool["PgDog / PgBouncer TLS<br/>client-facing + upstream verify_full"]
  issuer -->|"client auth · planned"| appcli["App client certs<br/>T3: app→pooler mTLS"]
  issuer -->|"server+client · planned"| grpc["gRPC mTLS<br/>pkg/grpcx + Temporal link"]
  issuer -->|"server auth · planned"| bao["OpenBAO listener<br/>tls_disable=0"]

  classDef edge fill:#dbeafe,color:#1e3a8a,stroke:#2563eb;
  classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
  classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
  classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;
  class root,issuer platform; class edge edge;
  class dbsrv,pool,appcli planned; class grpc,bao planned;
```

Rollout dependency graph (all **planned**; a lower tier blocks the one above it):

```mermaid
flowchart LR
  s0["Slice 0<br/>Edge decouple"] --> s1["Slice 1<br/>OpenBAO TLS"]
  s0 --> s2["Slice 2<br/>CNPG server cert"]
  s2 --> s3["Slice 3<br/>Pooler TLS<br/>(all app→DB via pooler)"]
  s3 --> s4["Slice 4<br/>Apps sslmode=verify-full<br/>payment → behind PgDog"]
  s4 --> s5["Slice 5<br/>T3 per-hop cert-auth"]
  s0 --> s6["Slice 6<br/>gRPC mTLS (last, gated)"]

  s0 --> s7["Slice 7 · planned, proposed<br/>Intermediate CA + root renewBefore"]
  s7 -.->|"proposed: signs the new leaves"| s1
  s7 -.->|"proposed: signs the new leaves"| s2
  s7 --> s8["Slice 8 · planned, proposed<br/>Keycloak HTTPS in-cluster<br/>JWKS + Grafana OAuth"]
  s2 --> s9["Slice 9 · planned, proposed<br/>platform-db clients verify-full<br/>Temporal · OpenBao DB engine · Keycloak"]
  s7 --> s11["Slice 11 · planned, proposed<br/>RustFS TLS<br/>Barman · DR · ClickHouse · Pyroscope"]
  s7 --> s12["Slice 12 · planned, proposed<br/>Valkey auth, then TLS"]
  s7 --> s13["Slice 13 · planned, proposed<br/>OCI registry TLS + Flux cosign verify"]
  s1 --> s14["Slice 14 · planned, proposed<br/>KMS over HTTPS<br/>prod: cloud KMS"]
  s1 --> s10["Slice 10 · planned, proposed<br/>Envoy BackendTLSPolicy<br/>per backend"]
  s8 --> s10
  s6 --> s10

  classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;
  class s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14 planned;
```

Slices 7–14 come from the 2026-10-01 amendment and are **proposed**. The dotted edges are its
one ordering change to the original graph: if Slice 7 is accepted it lands before slices 1, 2
and 6 issue their leaves, so nothing has to be re-issued under the intermediate later.

## Design Details

Per-slice knobs (mechanism detail and worked syntax: [research § Worked
examples](./research.md#worked-examples)):

| Slice | Change | Where |
|-------|--------|-------|
| 0 | Base edge `Certificate` issuer → `homelab-ca`; drop Cloudflare/LE + `cloudflare-api-token` from base; re-add `letsencrypt-prod` as prod overlay | `kubernetes/infra/` cert + kustomize overlays |
| 1 | `global.tlsDisable: false`; listener `tls_cert_file`/`tls_key_file`; `retry_join` → `https://` + `leader_ca_cert_file`; probe scheme HTTPS; ESO `SecretStore` + bootstrap job get `caBundle` | `kubernetes/infra/controllers/secrets/openbao/helmrelease.yaml` + ESO config |
| 2 | CNPG `spec.certificates.serverTLSSecret`/`serverCASecret` from a cert-manager `Certificate` (SANs: `-rw`/`-ro`/`-r` service names) | `kubernetes/infra/configs/databases/clusters/*` |
| 3 | PgDog `tls_certificate`/`tls_private_key` (client-facing) + `tls_verify = verify_full` + `tls_server_ca_certificate` (upstream); PgBouncer equivalent on platform-db pooler | pooler HelmRelease/Pooler manifests |
| 4 | App `DATABASE_URL` → `sslmode=verify-full` + `sslrootcert` from the mounted trust bundle; **`payment` moves from `product-db-rw` direct to `pgdog-product`** | `kubernetes/apps/services/*.yaml` values |
| 5 | PgDog `tls_client_required` + `tls_client_ca_certificate`; per-service client `Certificate`s; `pg_hba` `hostssl … cert` for the pooler identity (ADR-025 ties in) | pooler + CNPG `pg_hba` + app certs |
| 6 | `pkg/grpcx`/`pkg/temporalx` TLS credentials; per-service server+client `Certificate`; NetworkPolicy unchanged | `duynhlab/pkg` + service repos + homelab certs |

**Amendment slices (2026-10-01, proposed).** Each row names the review finding it closes and
where it sits relative to slices 0–6.

| Slice | Change | Closes | Ordering | Where |
|-------|--------|--------|----------|-------|
| 7 | Intermediate `Certificate` (`isCA: true`) under `homelab-ca`, plus a CA `ClusterIssuer` on the intermediate; `renewBefore` on the root; leaves move to the intermediate issuer; the trust bundle keeps root-only | Root signs leaves directly, 10y, no `renewBefore`, key in daily use | After 0; before 1, 2, 6 issue leaves | `kubernetes/infra/configs/cert-manager/` |
| 8 | Keycloak HTTPS listener with a `homelab-ca` leaf (`KC_HTTPS_*`). Envoy `remoteJWKS` via `Backend` + `BackendTLSPolicy`. Services get `OIDC_JWKS_URL` on `https://` and mount the bundle. Grafana gets `token_url`/`api_url` on `https://` and a CA | JWKS and OAuth token exchange over plaintext HTTP, so a swapped JWKS forges tokens | After 7; independent of 1–6 | `controllers/keycloak/`, `configs/envoy-gateway/policies/`, `apps/domains/*`, `configs/observability/grafana/` |
| 9 | Temporal SQL `tls` block (`enableHostVerification`, CA from the bundle); OpenBao DB engine `connection_url` on `sslmode=verify-full`; Keycloak JDBC `sslmode=verify-full&sslrootcert=…` | Temporal plaintext; DB engine `sslmode=disable` carrying rotator creds; Keycloak driver-default `prefer` | After 2 (CNPG server cert); parallel with 3–4 | `controllers/temporal/`, `platform-db/openbao-db-config.yaml`, `controllers/keycloak/` |
| 10 | `BackendTLSPolicy` per backend that serves a `homelab-ca` leaf (OpenBao UI after 1, Keycloak after 8, services' HTTP after a server-cert slice) | Envoy → every backend is plaintext | After 1 / 8 / 6, backend by backend | `configs/envoy-gateway/` |
| 11 | RustFS TLS with a `homelab-ca` leaf; `endpointCA` on each `ObjectStore`; ClickHouse S3 disk and Pyroscope on `https://` with the CA; the bucket Jobs too | WAL, base backups, DR restore, the cold tier and S3 keys over HTTP | After 7; independent of the DB slices | `controllers/storage/rustfs/`, `databases/clusters/*/objectstore.yaml`, `configs/clickhouse/`, `controllers/profiling/` |
| 12 | Valkey `auth.enabled` with an ESO-delivered password first, then TLS on `:6379` with a `homelab-ca` leaf; the cache client gains TLS config (service repos) | Valkey without auth or TLS | After 7; client half gated like 6 | `controllers/caching/valkey/` + service repos |
| 13 | `homelab-registry` served over TLS with a `homelab-ca` leaf (`certSecretRef` on the OCIRepositories, `insecure` patch removed); `make flux-push` signs with cosign; `spec.verify` on every OCIRepository | Flux pulls cluster state over plain HTTP with no signature check | After 7; independent; touches `scripts/` + `terraform/` | `kubernetes/clusters/local/{flux-system,sources/oci}/`, `scripts/` |
| 14 | KMS link over HTTPS: production points the seal at a cloud KMS endpoint (HTTPS by default); Kind may front floci with TLS for parity | OpenBao → floci awskms seal over HTTP | After 1; production half shared with RFC-0008 | `controllers/secrets/{openbao,floci}/` |

- **Enable/disable:** each slice is an independent values/manifest change, revertible by
  itself (`tls_verify` back to `prefer`, `tlsDisable: true`, `sslmode` back, issuer swap).
  Slice 4 depends on 2+3 being live; disabling 2 or 3 requires stepping 4 back first —
  the reverse of the dependency graph.
- **Default-behavior change:** none until a slice merges; after Slice 4 a service without
  the trust bundle mounted fails DB connect at startup (fail-closed, visible in probes).
- **Operator detection:** `Certificate` objects Ready in `cmctl status`; `psql \conninfo`
  / `pg_stat_ssl` show TLS; `openssl s_client` against `:8200`/`:9090`/`:6432`; PgDog admin
  `SHOW` counters.
- **Drawbacks:** more objects that can expire (mitigated by one 90d/30d policy + expiry
  alert); strict ordering during bring-up (`make up` drill per slice); Slice 6 spans repos
  (why it is last and gated); TLS handshake adds marginal latency on east-west hops.

## Security considerations

- **No secrets in git** — keys live only in cert-manager-managed Secrets; Kyverno policies
  and PSS restricted profiles are unaffected (no privileged/hostPath needed anywhere).
- **NetworkPolicy stays the connectivity fence** — TLS adds *identity and encryption*, it
  does not replace the netpol layer ("who may connect" vs "which service is this").
- trust-manager keeps distributing **root-only** bundles; leaves never enter the bundle.
- T3 hop semantics are explicit (Decision 5) so the pooler cannot be mistaken for
  end-to-end app identity at the database.

## Observability & SLO impact

- Expiry alerting already exists: `CertManagerCertExpiringSoon` fires at < 7d,
  `CertManagerCertExpiryCritical` at < 24h, and `CertManagerCertNotReady` on
  `certmanager_certificate_ready_status` (`prometheusrules/gitops/cert-manager-alerts.yaml`).
  Slice 0 only needs to align the warning threshold with the 30d renewal policy, which is
  14d per this RFC.
- During each DB slice watch connection-error rates and `pg_stat_ssl` coverage; during
  Slice 6 watch gRPC error/latency RED panels for handshake regressions.
- No SLO targets change; error budgets guard each slice's rollout window.

## Rollout & rollback

One slice = one PR = one `make up` drill, in dependency order 0 → 1 → 2 → 3 → 4 → 5 → 6
(1 and 6 only require 0). Blast radius per slice: 0 edge-only; 1 OpenBAO+ESO chain; 2–5
database plane (2 and 3 are transparent to apps — `prefer`-mode clients keep connecting);
6 east-west calls. The proposed slices 7–14 follow the same one-slice-one-PR rule and the
ordering column of their table; each is revertible on its own, except that 10 steps back
before the backend slice it depends on. Rollback = revert that slice's PR; slices 2–3 can roll back only after
stepping 4 back to `sslmode=disable` (reverse order). `payment`'s pooler migration (Slice 4)
falls back to its current direct-TLS connection string.

## Testing / verification

- `make validate` per PR; `make up` drill per slice (fresh-cluster bring-up is where
  ordering bugs live — probe/retry_join/floci interactions).
- Slice 1: `openssl s_client` on `:8200`, ESO round-trip, kill a pod → auto-unseal over TLS.
- Slices 2–4: `psql "sslmode=verify-full" \conninfo` per service DB via pooler;
  `pg_stat_ssl` shows all 10 services' connections TLS; negative test: wrong CA fails.
- Slice 5: connect without client cert → rejected at pooler; `hostssl … cert` verified.
- Slice 6: `grpcurl` with/without client cert; e2e audit (checkout flow crosses 4 gRPC hops).
- Slices 7–14 (proposed): each re-runs the § 12.2 checks in
  [`docs/secrets/cert-manager.md`](../../../secrets/cert-manager.md#122-what-to-check-on-a-live-cluster)
  for its hop. That means `openssl s_client` against the new listener (Keycloak `:8443`,
  RustFS `:9000`, Valkey `:6379`, the registry), `pg_stat_ssl` for Slice 9, and a
  wrong-CA negative test. Slice 13 also needs a tampered OCI artifact to fail `verify`.

## Implementation History

- 2026-07-21 — research merged (#576); RFC-0002 superseded (east-west absorbed here).
- 2026-07-21 — Context7 audit completed (#579): PgDog TLS confirmed, pooler blocker cleared.
- 2026-07-22 — owner decisions recorded (all-via-pooler, replication stays CNPG-managed,
  server-cert source, verify-full jump, 90d/30d, umbrella scope); gate passed; this README
  (provisional).
- 2026-10-01 — TLS review of the deployed Kind cluster. No slice 0–6 is applied: the base
  edge Certificate still names `letsencrypt-prod`. The review found eight gaps that no slice
  owned, and amendment slices 7–14 plus decisions 9–12 were added for them. All of them are
  proposed and need owner review; status stays provisional. Drift fixed in the same change:
  - the Motivation's "exactly one certificate (the Kong edge wildcard)";
  - the expiry alert, which already exists;
  - research's PgDog-upstream row, which said "plaintext" against its own `tls_verify`
    default of `prefer`.

## Related

- [./research.md](./research.md) — plain-language research and Context7 audit trail
- [RFC-0002](../RFC-0002/) (superseded — gRPC mTLS absorbed as Slice 6) · [RFC-0006](../RFC-0006/) (mesh-later) · [RFC-0008](../RFC-0008/) (credentials — complements)
- [ADR-005](../../adr/ADR-005-openbao-ha-raft/) (OpenBAO TLS target) · [ADR-015](../../adr/ADR-015-pg-hba-connection-isolation/) (`pg_hba` isolation) · [ADR-025](../../adr/ADR-025-pgdog-passthrough-dynamic-db-creds/) (credential ladder)
- [`docs/secrets/cert-manager.md`](../../../secrets/cert-manager.md) — deployed PKI chain; [§ 12](../../../secrets/cert-manager.md#12-tls-topology--which-hops-are-encrypted-today) — TLS topology as deployed (the amendment's starting point)
