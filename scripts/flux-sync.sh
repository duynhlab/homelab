#!/usr/bin/env bash
# Reconcile the three OCI sources `make flux-push` publishes, then every
# Kustomization that is not suspended. The other OCIRepositories are upstream
# chart sources and are left to their own intervals.

set -o errexit

for s in flux-system infrastructure-oci apps-oci; do
  echo "Syncing source $s..."
  flux reconcile source oci "$s"
done

# flux get prints NAME REVISION SUSPENDED READY MESSAGE; a suspended one errors.
for k in $(flux get kustomizations --no-header | awk '$3 == "False" {print $1}'); do
  echo "Syncing kustomization $k..."
  flux reconcile kustomization "$k"
done

echo ""
echo "=== Kustomization Status ==="
flux get kustomizations

echo ""
echo "✔ Cluster sync complete"
