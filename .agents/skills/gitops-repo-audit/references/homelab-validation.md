# Validating the `homelab` repository

This repo ships two complementary validation paths:

## Canonical (matches Flux overlays)

From the repository root:

```bash
./scripts/flux-validate.sh
```

This builds **only** the Kustomize overlays that Flux reconciles (see the `kustomize_overlays` array in the script). Use this in CI or before `flux push`.

## Skill `validate.sh` (this skill)

```bash
./scripts/validate.sh -d /path/to/homelab
```

The skill validates **all** `kustomization.yaml` trees under the repo. Namespace manifests live under `kubernetes/infra/controllers/namespaces.yaml` (no `../` references) so `kustomize build kubernetes/infra` works with the **default** load restrictor — no need for `--load-restrictor=LoadRestrictionsNone` for that path.

If a future layout reintroduces a root umbrella that conflicts with child overlays, prefer:

- Fixing the Kustomize graph (single source of truth for shared resources), or
- Temporarily excluding a path with `validate.sh -e <dir>` (narrow exclusions only — avoid excluding all of `kubernetes/infra` unless you accept skipping validation for those manifests).

For day-to-day work on this project, **`./scripts/flux-validate.sh`** remains the source of truth for “what Flux applies.”
