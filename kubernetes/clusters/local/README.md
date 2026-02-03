# Flux Operator Local Cluster Setup

**Cluster:** mop (Kind)  
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

**Access Points:**
- Flux UI: http://localhost:9080
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Frontend: http://localhost:3000

---

## Installation Architecture

### Why Helm + kubectl (Not flux-operator CLI)

We use **Helm to install Flux Operator + kubectl to apply FluxInstance** instead of the simpler CLI approach.

**Reason:** Production-ready pattern, GitOps-friendly, industry standard, career development value.

**Installation Order:**

```bash
# Step 1: Install Flux Operator (Helm)
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --wait

# Step 2: Apply FluxInstance CRD (kubectl)
kubectl apply -k kubernetes/clusters/local/flux-system/

# Or use Makefile
make flux-up
```

**Why this order?**
- FluxInstance is a CRD managed by Flux Operator
- Operator must exist first to reconcile FluxInstance
- CRDs are created by Helm in step 1
- If reversed: FluxInstance apply fails (CRD not found)

---

## OCI Registry

**Registry URL:** `localhost:5050`  
**Insecure:** Yes (local development only)  
**Purpose:** Store Kubernetes manifests as OCI artifacts

### Registry Setup

```bash
# Start registry (automatic with cluster-up)
docker run -d \
  --name flux-registry \
  --restart unless-stopped \
  -p 5050:5000 \
  registry:2

# Connect to Kind network
docker network connect kind flux-registry

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

```
1. controllers-local
   └── No dependencies (first to deploy)
   └── Creates namespaces + installs operators/CRDs (monitoring, databases, slo)

2. configs-local
   └── dependsOn: [controllers-local]
   └── Applies instances/configs (monitoring, apm, databases, slo)

3. apps-local
   └── dependsOn: [configs-local]
   └── 9 Backend Microservices + Frontend + K6
   └── K6 depends on all microservices via HelmRelease dependsOn
```

**Result:** Applications **will NOT start** until `configs-local` is ready. Flux enforces this automatically.

**Verify dependencies:**
```bash
# Check apps-local dependsOn
kubectl get kustomization apps-local -n flux-system -o yaml | grep -A5 dependsOn

# Expected output:
# dependsOn:
#   - name: configs-local
```

---

## Verification

### Check Flux Status

```bash
# All Kustomizations
flux get kustomizations

# Controllers/configs
flux get kustomization controllers-local
flux get kustomization configs-local

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
# Fix: Install operator first
make flux-install
```

**Issue:** Registry not accessible from Kind
```bash
# Check registry is running
docker ps | grep flux-registry

# Connect to Kind network
docker network connect kind flux-registry
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
│   ├── infrastructure-oci.yaml    # OCI source for infrastructure
│   ├── apps-oci.yaml              # OCI source for apps
│   ├── helm/                      # HelmRepository sources
│   └── kustomization.yaml
├── controllers.yaml               # Kustomization: namespaces + operators
├── configs.yaml                   # Kustomization: instances/configs
├── apps.yaml                      # Kustomization: 9 microservices + frontend
└── kustomization.yaml             # Master kustomization
```

---

## Production vs Local

### Local (Current)
- Insecure OCI registry (`localhost:5050`)
- Single replica for all services
- Minimal resource requests
- No persistent volumes for databases

### Production (Future)
- Authenticated registry (ECR/GAR/ACR)
- 3-5 replicas for HA
- Production resource limits
- Persistent storage for databases
- TLS everywhere
- Secret management (External Secrets Operator)

---

## Next Steps

1. **Test deployment:** `make cluster-up && make flux-install && make flux-push`
2. **Verify all services:** `make flux-status`
3. **Access Grafana:** http://localhost:3000
4. **Load test:** K6 runs automatically after apps deploy

---

## References

- **Flux Operator Docs:** https://fluxcd.control-plane.io/operator/
- **Kustomize Docs:** https://kustomize.io/
- **OCI Artifacts:** https://fluxcd.io/flux/cheatsheets/oci-artifacts/
- **Project Docs:** `../../../docs/platform/setup.md`
