# Flux Operator bootstrap (OpenTofu)

OpenTofu root module that bootstraps **Flux Operator** + the **`FluxInstance`**
on the homelab Kind cluster, replacing the old `helm install` + `kubectl apply -k`
flow in `scripts/flux-up.sh`.

It wraps [`controlplaneio-fluxcd/flux-operator-bootstrap`](https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap).
OpenTofu owns only the ephemeral bootstrap mechanism (namespace, RBAC, a
bootstrap `Job`); the Job installs Flux Operator and applies the `FluxInstance`
with create-if-missing semantics, then **Flux adopts** them and reconciles
steady-state. Unchanged manifests ⇒ `tofu plan` shows zero diff.

## Files

| File | Purpose |
|------|---------|
| `versions.tf`  | Required OpenTofu/provider versions + backend (local now, remote for prod) |
| `providers.tf` | `helm` + `kubernetes` providers pointed at the Kind context |
| `variables.tf` | `cluster_name`, `kubeconfig_path`, `kube_context`, `revision` |
| `main.tf`      | The bootstrap module call (+ commented production secrets) |
| `example.tfvars` | Reference values (defaults already match local) |

The `FluxInstance` manifest is **not** duplicated here — it is read from
`kubernetes/clusters/<cluster_name>/flux-system/instance.yaml`, the same file the
kubectl flow used.

## Usage (local)

```bash
make flux-up        # tofu init + apply (run by `make up`)
# or directly:
tofu -chdir=terraform init
tofu -chdir=terraform apply
```

Verify and confirm idempotency:

```bash
flux-operator -n flux-system get all
tofu -chdir=terraform plan   # must be zero diff
```

## Production readiness (prepared, not active)

Everything below is staged in code/comments so production is a fill-in:

1. **State backend** — uncomment the `backend "s3"` block in `versions.tf`
   (or use GCS / Terraform Cloud). Local state stays gitignored.
2. **Provider auth** — swap `config_context` in `providers.tf` for explicit
   endpoint/token/CA or an `exec` credential plugin.
3. **Pull secret** — uncomment `managed_resources.secrets_yaml` +
   `ghcr_auth_dockerconfigjson` in `main.tf`, sourced from an external secrets
   store. No secret material lands in state (module stores only a SHA-256 hash).
4. **FluxInstance** — point `var.cluster_name` at `production` and drop the
   insecure OCI patch in that cluster's `instance.yaml` (TLS registry).
