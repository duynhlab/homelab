# Flux Operator Local Cluster Setup

**Cluster:** homelab (Kind)  
**GitOps:** Flux Operator + Kustomize + OCI Registry  
**Environment:** Local Development

---

## Quick Start

```bash
# 1. Create Kind cluster + local registry
make cluster-up

# 2. Bootstrap Flux Operator + FluxInstance
make flux-up

# 3. Push manifests to OCI registry
make flux-push

# 4. Verify deployment
make flux-status

# 5. Open Flux Web UI
make flux-ui
```

**Access Points** (port-forward fallback from `make flux-ui`):
- Flux UI: http://localhost:9080
- Grafana: http://localhost:3000
- VictoriaMetrics: http://localhost:8428/vmui
- Frontend: http://localhost:3001

---

## Installation Architecture

### OpenTofu bootstrap

`make flux-up` runs `scripts/flux-up.sh`, which applies the OpenTofu root in
[`terraform/`](../../../terraform/README.md) (the `flux-operator-bootstrap`
module). A bootstrap `Job` installs Flux Operator and applies the
`FluxInstance` from `flux-system/instance.yaml`; Flux then adopts both and
reconciles steady-state. The earlier `helm install` + `kubectl apply -k` flow
is retired. `make tf-plan` must show zero diff once bootstrapped.

---

## OCI Registry

**Registry URL:** `localhost:5050`  
**Insecure:** Yes (local development only)  
**Purpose:** Store Kubernetes manifests as OCI artifacts

### Registry Setup

```bash
# Start registry (automatic with cluster-up, scripts/kind-up.sh)
docker run -d \
  --name homelab-registry \
  --restart=always \
  -p 127.0.0.1:5050:5000 \
  registry:3

# Connect to Kind network
docker network connect kind homelab-registry

# Verify
curl http://localhost:5050/v2/_catalog
# Expected: {"repositories":[]}
```

### Push Manifests

```bash
# Push infrastructure manifests (simplified structure - refactored 2026-01-12)
flux push artifact oci://localhost:5050/flux-infra-sync:local \
  --path=kubernetes/infra \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git rev-parse HEAD)"

# Push apps manifests (simplified structure - refactored 2026-01-12)
flux push artifact oci://localhost:5050/flux-apps-sync:local \
  --path=kubernetes/apps \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git rev-parse HEAD)"

# Or use Makefile
make flux-push
```

**Note:** Structure simplified from `base/overlays` to direct `infra/` and `apps/` manifests (2026-01-12).

**Production Note:** Use authenticated registry (AWS ECR, Google GAR, Azure ACR) with TLS enabled.

---

## Deployment Order

Flux automatically deploys in correct dependency order via `dependsOn` field in Kustomization CRDs:

30 files in this directory declare one Kustomization CR each; `mcp.yaml` is
commented out of `kustomization.yaml`, so 29 apply, and the FluxInstance adds
`flux-system`. Count them at run time rather than trusting this number. The
full graph is in [`docs/platform/setup.md`](../../../docs/platform/setup.md);
the edges that matter most:

```
controllers-local            # namespaces + operators/CRDs; first to deploy
network-policies-local       # dependsOn controllers-local (inert on kindnet)
databases-local              # after secrets, monitoring, cnpg-barman-plugin,
                             # storage, network-policies
apps-local                   # dependsOn databases-local, monitoring-local,
                             # temporal-config-local, keda-local
                             # 10 microservices + 2 workers + storefront + backoffice
```

**Result:** Applications **will NOT start** until those four waves are Ready. Flux enforces this automatically.

## PodDisruptionBudgets

PDBs are added only where there is real redundancy: the Envoy proxy fleet (`replicas: 2`, `minAvailable: 1` via the EnvoyProxy CR) and OpenBAO (HA 3-node Raft, `maxUnavailable: 1`). Single-replica components (cert-manager, ESO, VMSingle, VictoriaLogs) need to be scaled to 2 before a PDB is added, otherwise a `minAvailable: 1` PDB makes the lone pod undrainable and deadlocks node drains/upgrades.

**Verify dependencies:**
```bash
# Check apps-local dependsOn
kubectl get kustomization apps-local -n flux-system -o yaml | grep -A5 dependsOn

# Expected output:
# dependsOn:
#   - name: databases-local
#   - name: monitoring-local
#   - name: temporal-config-local
#   - name: keda-local
```

---

## Verification

### Check Flux Status

```bash
# All Kustomizations
flux get kustomizations

# Controllers/databases
flux get kustomization controllers-local
flux get kustomization databases-local

# Apps
flux get kustomization apps-local

# Or use Makefile
make flux-status
```

### Check Resources

```bash
# Flux Operator
kubectl get deployment -n flux-system flux-operator

# FluxInstance
kubectl get fluxinstance -n flux-system

# All Flux controllers
kubectl get pods -n flux-system

# All resources
kubectl get pods --all-namespaces
```

### Common Issues

**Issue:** FluxInstance CRD not found
```bash
# Fix: re-run the OpenTofu bootstrap, which installs the operator first
make flux-up
```

**Issue:** Registry not accessible from Kind
```bash
# Check registry is running
docker ps | grep homelab-registry

# Connect to Kind network
docker network connect kind homelab-registry
```

**Issue:** Apps deploy before databases ready
```bash
# Fixed: apps-local has correct dependsOn
kubectl get kustomization apps-local -n flux-system -o yaml | grep -A5 dependsOn
```

---

## File Structure

```
kubernetes/clusters/local/
├── README.md                      # This file
├── flux-system/
│   ├── namespace.yaml             # flux-system namespace
│   ├── instance.yaml              # FluxInstance CRD
│   └── kustomization.yaml
├── sources/
│   ├── oci/                       # OCIRepository sources (infrastructure, apps, charts)
│   ├── helm/                      # HelmRepository sources
│   └── kustomization.yaml
├── controllers.yaml               # Kustomization: namespaces + operators
├── <wave>.yaml                    # one Kustomization CR per wave (databases, monitoring, …)
├── apps.yaml                      # Kustomization: 10 microservices + workers + SPAs
└── kustomization.yaml             # Master kustomization
```

---

## Production vs Local

### Local (Current)
- Insecure OCI registry (`localhost:5050`)
- Single replica for the microservices (`replicaCount: 1`)
- Minimal resource requests

### Production (Future)
- Authenticated registry (ECR/GAR/ACR)
- 3-5 replicas for HA
- Production resource limits
- Persistent storage for databases
- TLS everywhere

---

## Next Steps

1. **Test deployment:** `make up` (cluster-up → flux-push → flux-up)
2. **Verify all services:** `make flux-status`
3. **Access Grafana:** http://localhost:3000

---

## References

- **Flux Operator Docs:** https://fluxcd.control-plane.io/operator/
- **Kustomize Docs:** https://kustomize.io/
- **OCI Artifacts:** https://fluxcd.io/flux/cheatsheets/oci-artifacts/
- **Project Docs:** `../../../docs/platform/setup.md`
