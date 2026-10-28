# Secrets / TLS

OpenBAO → ESO → Secrets → pods, and cert-manager → trust-manager for TLS. Most
symptoms are "ExternalSecret NotReady" or "cert won't issue".

## Authoritative docs

- Pipeline hub + secret catalog: [secrets/README.md](../../../../../docs/secrets/README.md).
- Task + troubleshooting runbooks: [secrets/runbooks/README.md](../../../../../docs/secrets/runbooks/README.md)
  (ESO sync failure, reviewer JWT ~1h post-bootstrap, dynamic-credentials debug,
  unseal, rotation, compromise revoke).
- cert-manager + trust-manager CA bundle: [secrets/cert-manager.md](../../../../../docs/secrets/cert-manager.md).
- OpenBAO internals: [secrets/openbao.md](../../../../../docs/secrets/openbao.md).

## Manifests

- `kubernetes/infra/configs/secrets/` (OpenBAO, ESO ClusterSecretStore,
  ExternalSecrets), `kubernetes/infra/configs/cert-manager/`.

## Diagnose

```bash
kubectl get externalsecret,clustersecretstore -A | grep -v ' True\| SecretSynced'
kubectl describe externalsecret <name> -n <ns>
kubectl get certificate,certificaterequest -A | grep -v ' True '
```

- ESO failing ~1h after bootstrap with `permission denied` → reviewer JWT auth
  runbook.
- After a GitOps change, prefer `flux reconcile ks <name> -n flux-system
  --with-source` to realign the cluster.
- Prod `letsencrypt-*` issuers NotReady → the bootstrap-only Cloudflare token
  must be re-seeded ([platform/setup.md](../../../../../docs/platform/setup.md));
  this is **not** a local bring-up blocker (`homelab-ca` issues the local edge).

## Boundary

- Never echo secret values; prefer staff-OIDC paths over root/ceremony.
- **Do not copy local floci/recovery-key practices to prod** — the Kind pattern
  is intentionally unsafe for learning.
- Rotation/revocation is a Task-led procedure — follow the runbook, get approval
  for compromise revocation ([triage-and-safety](../triage-and-safety.md#approval-gates)).
