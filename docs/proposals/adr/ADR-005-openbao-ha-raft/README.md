# ADR-005: Run OpenBAO HA (Raft) instead of Vault dev mode

Replace HashiCorp Vault dev mode with a 3-node OpenBAO HA cluster on Raft storage.

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-06-29 | — |

## Context

The platform initially ran **HashiCorp Vault in dev mode**: in-memory, single
node, state lost on every restart, auto-unsealed with a static root token, and
under the BSL (non-OSS) license. That is unsuitable even for a representative
homelab — the secrets tier feeds database, backup (S3/RustFS), and TLS
credentials via External Secrets Operator (ESO), so losing it on a pod restart
breaks the whole stack, and an OSS license is a project requirement.

## Decision

We replaced Vault dev with **OpenBAO** — the Apache-2.0 fork of Vault, API- and
ESO-compatible — deployed as a **3-node HA cluster using Raft integrated storage**
with per-node PVCs, via the official Helm chart, in the `openbao` namespace. ESO
authenticates over **Kubernetes auth** (TokenReview) bound to a least-privilege
`eso-read` policy scoped to `secret/{data,metadata}/local/{databases,infra,services}/*`.

On **local Kind** the cluster is unsealed with **Shamir** (the unseal key + root
token stored in the `openbao-init-keys` K8s Secret, re-applied by a 60s unsealer
CronJob), and TLS is disabled — explicit, documented **local-only** compromises.
KMS/Transit auto-unseal and TLS are the production target.

## Alternatives considered

- **Stay on Vault dev mode** — *Rejected:* no persistence, single node, BSL license.
- **Single-node standalone OpenBAO with a PVC** — *Rejected:* persists, but no HA;
  a node loss takes secrets offline.
- **SealedSecrets / SOPS** — *Rejected:* simpler, but no leasing, no dynamic
  secrets, no central policy/audit, and no Vault-compatible API for ESO.
- **Cloud secret managers only (AWS/GCP)** — *Deferred:* wanted an in-cluster,
  Vault-compatible API and a single ESO integration that also works on Kind; cloud
  KMS still enters later as the unseal backend.

## Consequences

- Secrets survive pod/node restarts; quorum tolerates one node down; OSS license;
  a foundation that ports to EKS/GKE.
- ESO auth is sound (Kubernetes auth without a pinned `token_reviewer_jwt`,
  least-privilege policy).
- **Known local-only gaps (carried, not solved, by this decision):**
  Shamir-key-and-root-token-in-a-Secret, TLS disabled, dev credentials seeded from
  Git, root token not revoked after bootstrap. Each is a production hardening item
  tracked in the production-secrets-hardening RFC.
- **Revisit trigger:** production deployment, or availability of a cloud KMS /
  Transit backend to replace Shamir auto-unseal.

---

<!-- Append-only: supersede with a new ADR rather than rewriting this one. -->

---
_Last updated: 2026-06-29_
