# Infrastructure manifests (`kubernetes/infra`)

This directory holds **operators** (`controllers/`) and **workload configs** (`configs/`).

## Flux vs local Kustomize

- **Flux** applies **subpaths** from the pushed OCI artifact (see `scripts/flux-push.sh`), e.g. `./controllers`, `./configs/monitoring`, `./configs/databases`. Each subpath has its own `kustomization.yaml`.
- **Root `kustomization.yaml` here** is a convenience **umbrella** to build operators + configs together (e.g. `kustomize build .` from `kubernetes/infra`). It must not duplicate resources included by children.
- **Namespaces** live in [`controllers/namespaces.yaml`](controllers/namespaces.yaml) (under `controllers/` so plain `kustomize build kubernetes/infra` works without `--load-restrictor=LoadRestrictionsNone`).

Validation used in CI/dev: [`scripts/flux-validate.sh`](../../scripts/flux-validate.sh) (explicit overlay list).
