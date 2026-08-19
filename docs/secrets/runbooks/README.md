# Secrets Runbooks

Task-focused operations and troubleshooting procedures for OpenBAO, ESO, and
secrets-related Flux dependencies.

## Convention

These are **procedural task runbooks**: one-line hook → optional scope table →
numbered bash steps → `_Last updated_` footer. The per-alert template at
[`../../observability/runbooks/_TEMPLATE.md`](../../observability/runbooks/_TEMPLATE.md)
governs **alert** runbooks only and does not apply here.

## Setup and bootstrap

| When to use | Runbook |
|---|---|
| Verify a fresh local OpenBAO bootstrap, re-run the Job, or seed prod Cloudflare token | [OpenBAO initial setup](./openbao-initial-setup.md) |
| OpenBAO pods are sealed (floci auto-unseal failed) or `secrets-local` is stuck | [OpenBAO unseal and stuck reconciliation](./openbao-unseal.md) |
| Save or restore OpenBAO Raft data | [Raft snapshot and restore](./raft-snapshot-restore.md) |

## Day-2 operations

| When to use | Runbook |
|---|---|
| Add a new static secret synced by ESO | [Add ESO-managed secret](./add-eso-secret.md) |
| Write a KV secret on a live cluster (break-glass generate-root ceremony) | [Add or write a KV secret on a live cluster](./add-secret-live-cluster.md) |
| Rotate a static OpenBAO KV v2 secret | [Rotate static secret](./rotate-static-secret.md) |
| Put another service's DB password under OpenBAO rotation (ADR-025 pilot) | [Add service dynamic credentials](./add-service-dynamic-credentials.md) |
| Revoke a token or credential after compromise | [Revoke compromised credential](./revoke-compromised-credential.md) |

## Troubleshooting

| When to use | Runbook |
|---|---|
| ExternalSecret or ClusterSecretStore is not ready | [ESO sync failure](./eso-sync-failure.md) |
| ESO fails about one hour after bootstrap with `permission denied` | [Reviewer JWT auth failure](./reviewer-jwt-auth-failure.md) |
| The `notification` static-role password stops syncing or rotating (ADR-025 pilot) | [Dynamic credentials debug](./dynamic-credentials-debug.md) |

## Rules

| Rule | Why |
|---|---|
| Check the current deployed state first | Some OpenBAO features in the docs are planned, not enabled locally |
| Prefer `flux reconcile ... --with-source` after GitOps changes | Keeps the cluster aligned with the repo |
| Do not copy local floci/recovery-key practices to production | The local Kind pattern is intentionally unsafe for production learning |
| Keep secrets out of Git | Local placeholders are exceptions documented in the OpenBAO bootstrap flow |

---

_Last updated: 2026-08-19 — Indexed `add-secret-live-cluster.md`; moved the two ADR-025 runbooks out of "Planned"; added the procedural-runbook convention note._
