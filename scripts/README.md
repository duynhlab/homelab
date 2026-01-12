# Scripts Directory

This directory contains deployment and management scripts for the monitoring platform.

---

## GitOps Scripts (Flux Operator)

**Recommended for production-ready deployment:**

| Script | Purpose | Equivalent |
|--------|---------|------------|
| `kind-up.sh` | Create Kind cluster + OCI registry | `make cluster-up` + `make registry-up` |
| `kind-down.sh` | Delete cluster + registry | `make clean-all` |
| `flux-up.sh` | Bootstrap Flux Operator (Helm) | `make flux-up` |
| `flux-push.sh` | Push manifests to OCI registry | `make flux-push` |
| `flux-sync.sh` | Sync and reconcile manifests | `make flux-sync` |
| `flux-ui.sh` | Open Flux Web UI | `make flux-ui` |

### Workflow

```bash
# 1. Create cluster + start registry
./scripts/kind-up.sh

# 2. Bootstrap Flux Operator (Helm-based)
./scripts/flux-up.sh

# 3. Push manifests to OCI registry
./scripts/flux-push.sh

# 4. (Optional) Force reconciliation
./scripts/flux-sync.sh

# 5. Open Flux Web UI
./scripts/flux-ui.sh
```

---

## Script Details

### kind-up.sh

**Purpose:** Create Kind cluster with local OCI registry

**What it does:**
1. Starts Docker registry on `localhost:5050`
2. Creates Kind cluster `mop` (4 nodes: 1 control-plane + 3 workers)
3. Connects registry to Kind network
4. Registers registry in cluster ConfigMap

**Configuration:**
- `CLUSTER_NAME=mop` (default)
- `CLUSTER_VERSION=v1.33.7` (Kubernetes version)

**Duration:** ~2-3 minutes

**Pattern:** Based on [`flux-operator-local-dev/scripts/kind-up.sh`](https://github.com/controlplaneio-fluxcd/flux-operator-local-dev)

---

### kind-down.sh

**Purpose:** Delete Kind cluster and OCI registry

**What it does:**
1. Deletes Kind cluster `mop`
2. Removes Docker registry container

**Duration:** ~10-20 seconds

---

### flux-up.sh

**Purpose:** Bootstrap Flux Operator via Helm (not CLI)

**What it does:**
1. Installs Flux Operator via Helm chart:
   ```
   helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator
   ```
2. Applies FluxInstance from `kubernetes/clusters/local/flux-system/instance.yaml`
3. Waits for all Kustomizations to sync:
   - controllers-local
   - configs-local
   - apps-local
   - flux-system

**Key difference from reference repo:**
- Uses **Helm** instead of `flux-operator` CLI
- Reason: Production-ready pattern, better control

**Duration:** ~5-10 minutes (includes all infrastructure + apps deployment)

---

### flux-push.sh

**Purpose:** Push Kubernetes manifests to local OCI registry

**What it does:**
1. Checks if manifests changed (via `flux diff artifact`)
2. If changed, pushes to `localhost:5050`:
   - `flux-cluster-sync:local` (from `kubernetes/clusters/local/`)
   - `flux-infra-sync:local` (from `kubernetes/infra/`) - **Simplified structure (refactored 2026-01-12)**
   - `flux-apps-sync:local` (from `kubernetes/apps/`) - **Simplified structure (refactored 2026-01-12)**
3. Includes Git source + revision metadata

**Smart behavior:**
- Only pushes if changes detected
- Shows "✔ no changes detected" if unchanged

**Duration:** ~10-30 seconds

---

### flux-sync.sh

**Purpose:** Force reconciliation of all Kustomizations

**What it does:**
1. Triggers `flux reconcile` for all Kustomizations:
   - controllers-local
   - configs-local
   - apps-local
2. Shows resource tree for apps

**Use when:**
- After `flux-push.sh` to speed up reconciliation
- Manual changes reverted (drift detection)
- Troubleshooting reconciliation issues

**Duration:** ~1-2 minutes

---

### flux-ui.sh

**Purpose:** Open Flux Web UI in browser

**What it does:**
- Port-forwards Flux Web UI to `http://localhost:9080`

**Note:** Press Ctrl+C to stop port-forwarding

---

## Legacy Scripts (Script-Based Deployment)

**Status:** Deprecated - Use GitOps scripts instead

| Script | Purpose | Status |
|--------|---------|--------|
| `00-verify-build.sh` | Verify local builds | ✅ Active (pre-deployment) |
| `01-create-kind-cluster.sh` | Create Kind cluster | ✅ Active (cluster setup) |
| `02-deploy-monitoring.sh` | Deploy monitoring stack | ⚠️ Deprecated → Use `flux-push.sh` |
| `03-deploy-apm.sh` | Deploy APM stack | ⚠️ Deprecated → Use `flux-push.sh` |
| `04-deploy-databases.sh` | Deploy databases | ⚠️ Deprecated → Use `flux-push.sh` |
| `05-deploy-microservices.sh` | Deploy microservices | ⚠️ Deprecated → Use `flux-push.sh` |
| `06-deploy-k6.sh` | Deploy k6 load testing | ⚠️ Deprecated → Use `flux-push.sh` |
| `07-deploy-slo.sh` | Deploy SLO system | ⚠️ Deprecated → Use `flux-push.sh` |
| `08-setup-access.sh` | Setup port-forwarding | ✅ Active (local access) |
| `09-reload-dashboard.sh` | Reload Grafana dashboards | ✅ Active (troubleshooting) |
| `10-error-budget-alert.sh` | Handle error budget alerts | ✅ Active (SRE operations) |
| `cleanup.sh` | Complete cleanup | ✅ Active (cleanup) |

---

## Migration Guide

### Old Workflow (6 Scripts)
```bash
./scripts/02-deploy-monitoring.sh
./scripts/03-deploy-apm.sh
./scripts/04-deploy-databases.sh
./scripts/05-deploy-microservices.sh
./scripts/06-deploy-k6.sh
./scripts/07-deploy-slo.sh
```

### New Workflow (2 Scripts)
```bash
./scripts/flux-up.sh    # Bootstrap Flux (one-time)
./scripts/flux-push.sh  # Push manifests (repeatable)
```

**Benefits:**
- ✅ 6 scripts → 2 scripts
- ✅ Single command deploys everything
- ✅ Automatic drift detection
- ✅ Built-in rollback (change OCI tag)
- ✅ Multi-environment support (local/staging/production)
- ✅ 67-89% YAML reduction (Kustomize)

---

## Makefile Alternative

All Flux scripts have Makefile equivalents:

```bash
# Scripts
./scripts/flux-up.sh     →  make flux-up
./scripts/flux-push.sh   →  make flux-push
./scripts/flux-sync.sh   →  make flux-sync
./scripts/flux-ui.sh     →  make flux-ui
```

**Choose based on preference:**
- **Scripts:** Self-contained, explicit, easy to read
- **Makefile:** Concise, tab-completion, shows all commands (`make help`)

Both methods are production-ready.

---

## Pattern Reference

These scripts follow the pattern from:
- Repository: [`flux-operator-local-dev`](https://github.com/controlplaneio-fluxcd/flux-operator-local-dev)
- Author: Stefan Prodan (ControlPlane.io)
- License: AGPL-3.0

**Key differences:**
- Added `flux-ui.sh` (Flux Web UI access)
- Multiple Kustomizations (infrastructure, monitoring, apm, databases, apps, slo)
- **Simplified structure** (`kubernetes/infra/` + `kubernetes/apps/`) - refactored 2026-01-12
- No base/overlay pattern (direct manifests with local config inline)

---

## Documentation

- **Setup Guide:** [`docs/guides/SETUP.md`](../docs/guides/SETUP.md)
- **GitOps Migration:** [`specs/active/flux-gitops-migration/IMPLEMENTATION_COMPLETE.md`](../specs/active/flux-gitops-migration/IMPLEMENTATION_COMPLETE.md)
- **Makefile Reference:** [`Makefile`](../Makefile)
