# Security / admission / network

Two fences: Kyverno admission (what may be applied) and NetworkPolicy
segmentation (what may talk to what). Both deny in ways that masquerade as
other failures.

## Authoritative docs

- Security hub (the two fences): [security/README.md](../../../../../docs/security/README.md).
- Kyverno policy catalog + modes: [security/policy-catalog.md](../../../../../docs/security/policy-catalog.md),
  platform view [platform/kyverno.md](../../../../../docs/platform/kyverno.md).
- Exceptions register (owner + TTL): [security/policy-exceptions.md](../../../../../docs/security/policy-exceptions.md).
- East-west allow matrix: [security/network-policies.md](../../../../../docs/security/network-policies.md).
- Kyverno alerts: [kyverno runbooks](../../../../../docs/observability/runbooks/kyverno/README.md).

## Manifests

- `kubernetes/infra/configs/kyverno/cluster-policies/` and `.../exceptions/`.
- `kubernetes/infra/configs/network-policies/`.

## Diagnose

- **Admission deny** during a Flux apply shows as a Kustomization that won't
  build/apply, or API `EOF` under webhook latency. Check Kyverno events and the
  policy; the [admission rules](../../../../../AGENTS.md#kyverno-admission-rules)
  are the quick checklist (namespace, image tag, resources, probes, PSS).
- **Connectivity despite healthy pods** is usually NetworkPolicy. Sweep it:

```bash
make db-isolation                 # pg_hba + policy into the data tier
make edge-isolation ARGS=--live   # edge allow-list
```

## Boundary

- A firing `Kyverno*` metric alert → its runbook file. A *policy deny* during
  apply → the platform/catalog docs + events.
- **Do not loosen a policy** to pass admission. If an exception is justified, it
  is a PR under `kyverno/exceptions/` with `owner` + `expires-at` and a
  [policy-exceptions](../../../../../docs/security/policy-exceptions.md) update —
  not a mitigation you apply live.
