# Security: Admission & Segmentation

The platform's two runtime fences: **Kyverno** decides what may be admitted
(policy-as-code at the API server), **NetworkPolicy** decides who may talk to
whom once admitted (east-west micro-segmentation on kindnet, which enforces).

## Quick facts

| | |
|---|---|
| Admission engine | Kyverno (chart `3.8.2`, single-replica controllers on Kind) |
| Policies | 8 deployed (mostly Audit; `disallow-default-namespace` Enforce) + 3 planned — [catalog](policy-catalog.md) |
| PSS | `pss-baseline` Audit cluster-wide; `pss-restricted-apps` **disabled 2026-08-17** — [known gaps](policy-catalog.md#known-gaps--history) |
| Exceptions | 2 registered, owner + expiry mandatory, accepted only from ns `kyverno` — [registry](policy-exceptions.md) |
| Segmentation | 26 committed NetworkPolicies (12 namespaces) + floci fence + Kyverno-generated `deny-all-ingress` per app namespace — [caller matrix](network-policies.md) |
| Verification | `make validate` · `scripts/edge-isolation-sweep.sh` · `scripts/db-isolation-sweep.sh` |

## What to read

| Need | Doc |
|---|---|
| Which Kyverno policies run, in which mode, and the manifest acceptance criteria | [policy-catalog.md](policy-catalog.md) |
| Waive a policy for a workload (owner, expiry, registry contract) | [policy-exceptions.md](policy-exceptions.md) |
| Who may call whom: caller matrix, allowed-ingress topology, GitOps wiring | [network-policies.md](network-policies.md) |

## The two planes

```mermaid
flowchart LR
    subgraph admission ["Admission plane (create/update time)"]
        api["kube-apiserver"]:::platform
        kyverno["Kyverno webhooks<br/>validate · generate · cleanup"]:::platform
        exc["PolicyExceptions<br/>(ns kyverno only)"]:::data
        api --> kyverno
        exc -.->|"waives"| kyverno
    end

    subgraph network ["Network plane (runtime)"]
        deny["deny-all-ingress<br/>(generated per app ns)"]:::platform
        allow["allow-* policies<br/>(committed, per namespace)"]:::data
        traffic["Pod-to-pod traffic"]:::service
        deny --> traffic
        allow --> traffic
    end

    kyverno -->|"generates deny-all"| deny

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
```

## References

- [AGENTS.md § Kyverno admission rules](../../AGENTS.md) — the operative contract for every manifest
- [docs/platform/kyverno.md](../platform/kyverno.md) — controller deployment, rollout history
- [docs/api/api.md § edge exposure](../api/api.md) — audience doctrine the fences implement

---
_Last updated: 2026-08-19 — hub created (the folder was the last docs area without one)._
