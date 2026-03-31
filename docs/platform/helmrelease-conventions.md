# HelmRelease conventions (Flux)

All `HelmRelease` resources in this repo use a **consistent remediation policy** so failed installs/upgrades retry before giving up.

## Standard (`helm.toolkit.fluxcd.io/v2`)

```yaml
spec:
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
```

Charts that set **CRD policies** on install/upgrade (e.g. `install.crds: Create`) keep those fields and add `remediation` alongside them.

## Rationale

- Aligns with [HelmRelease install/upgrade remediation](https://fluxcd.io/flux/components/helm/helmreleases/#install-configuration) in Flux.
- Reduces flakiness from transient API errors during reconciliation.
- Matches existing releases that already used `remediation.retries: 3` (OpenBAO, RustFS, External Secrets, PgDog).

## ResourceSet-generated apps

Domain `ResourceSet` templates (`kubernetes/apps/domains/*.yaml`, `frontend-rs.yaml`) include the same `install` / `upgrade` blocks so microservice HelmReleases behave like platform charts.
