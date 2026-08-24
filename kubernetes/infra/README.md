# Infrastructure manifests (`kubernetes/infra`)

This directory holds **operators** (`controllers/`) and **workload configs** (`configs/`).

In practice `controllers/` is anything a **chart installs** — operators, but also
plain platform components (Envoy Gateway, Valkey, OpenBAO, Vector, Temporal) — while
`configs/` holds the **CRs and configuration those components consume**. A component
whose config needs its own ordering gets two Kustomizations: `envoy-gateway-local` →
`./controllers/envoy-gateway` then `envoy-gateway-config-local` → `./configs/envoy-gateway`;
Temporal follows the same split.

## Flux vs local Kustomize

- **Flux** applies **subpaths** from the pushed OCI artifact (see `scripts/flux-push.sh`), e.g. `./controllers`, `./configs/observability`, `./configs/databases`. Each subpath has its own `kustomization.yaml`.
- **Root `kustomization.yaml` here** is a convenience **umbrella** to build operators + configs together (e.g. `kustomize build .` from `kubernetes/infra`). It must not duplicate resources included by children.
- **Namespaces** live in [`controllers/namespaces.yaml`](controllers/namespaces.yaml) (under `controllers/` so plain `kustomize build kubernetes/infra` works without `--load-restrictor=LoadRestrictionsNone`).

- **Retiring a manifest**: rename it to `<name>.yaml.bak` and drop it from the
  `kustomization.yaml`. Dropping the entry is what makes it inert; the suffix is what
  keeps it *readable* — commenting out every line does the same job and destroys the
  file. `.bak` is tracked in git (deliberately), and it is skipped by
  `flux-validate.sh` (which globs `*.yaml`) and by Renovate, so it can no longer rot
  loudly — the intent for something retired. Example: the alexandrevilain
  temporal-operator's HelmRelease, CRs and HelmRepository (ADR-030).

Validation used in CI/dev: [`scripts/flux-validate.sh`](../../scripts/flux-validate.sh) (explicit overlay list).
