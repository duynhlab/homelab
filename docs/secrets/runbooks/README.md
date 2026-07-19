# Secrets Runbooks

Task-focused operations and troubleshooting procedures for OpenBAO, ESO, and
secrets-related Flux dependencies.

## Setup and bootstrap

| When to use | Runbook |
|---|---|
| Fresh local OpenBAO bootstrap, status checks, or seed prod Cloudflare token | [OpenBAO initial setup](./openbao-initial-setup.md) |
| OpenBAO pods are sealed or `secrets-local` is stuck | [OpenBAO unseal and stuck reconciliation](./openbao-unseal.md) |
| Save or restore OpenBAO Raft data | [Raft snapshot and restore](./raft-snapshot-restore.md) |

## Day-2 operations

| When to use | Runbook |
|---|---|
| Add a new static secret synced by ESO | [Add ESO-managed secret](./add-eso-secret.md) |
| Rotate a static OpenBAO KV v2 secret | [Rotate static secret](./rotate-static-secret.md) |
| Revoke a token or leased credential after compromise | [Revoke compromised credential](./revoke-compromised-credential.md) |

## Troubleshooting

| When to use | Runbook |
|---|---|
| ExternalSecret or ClusterSecretStore is not ready | [ESO sync failure](./eso-sync-failure.md) |
| ESO fails about one hour after bootstrap with `permission denied` | [Reviewer JWT auth failure](./reviewer-jwt-auth-failure.md) |

## Planned (not deployed)

| When to use | Runbook |
|---|---|
| Debug future dynamic DB credential support | [Dynamic credentials debug](./dynamic-credentials-debug.md) |
| Add a future dynamic-credential service | [Add service dynamic credentials](./add-service-dynamic-credentials.md) |

## Rules

| Rule | Why |
|---|---|
| Check the current deployed state first | Some OpenBAO features in the docs are planned, not enabled locally |
| Prefer `flux reconcile ... --with-source` after GitOps changes | Keeps the cluster aligned with the repo |
| Do not copy local unseal/root-token practices to production | The local Kind pattern is intentionally unsafe for production learning |
| Keep secrets out of Git | Local placeholders are exceptions documented in the OpenBAO bootstrap flow |

---

_Last updated: 2026-07-19 — Grouped by task type; added `add-eso-secret.md` during secrets docs merge._
