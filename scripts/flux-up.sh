#!/usr/bin/env bash

set -o errexit

# Bootstrap Flux Operator + FluxInstance via OpenTofu (controlplaneio-fluxcd
# flux-operator-bootstrap module). Replaces the previous `helm install` +
# `kubectl apply -k` flow; the FluxInstance manifest is still the single source
# of truth at kubernetes/clusters/<cluster_name>/flux-system/instance.yaml.
#
# ORDERING: the module waits for the FluxInstance to become Ready, which
# requires its sync source (oci://homelab-registry:5000/flux-cluster-sync) to
# already exist in the registry. Run `make flux-push` BEFORE this script — the
# `make up` target sequences cluster-up → flux-push → flux-up for that reason.

tf_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
tf_bin="${TF_BIN:-tofu}"

if ! command -v "${tf_bin}" >/dev/null 2>&1; then
  echo "error: '${tf_bin}' not found on PATH (install OpenTofu, or set TF_BIN=terraform)" >&2
  exit 1
fi

echo "Bootstrapping Flux Operator via ${tf_bin} (${tf_dir})"
"${tf_bin}" -chdir="${tf_dir}" init -input=false
"${tf_bin}" -chdir="${tf_dir}" apply -input=false -auto-approve

echo "✔ Flux Operator bootstrap applied"
echo ""
echo "Next steps:"
echo "  1. Push manifests: make flux-push"
echo "  2. Trigger reconciliation: make flux-sync"
echo "  3. Check status: make flux-status"
