# Local Environment Patches

This directory contains Kustomize patches for overriding Helm chart values in the **local** environment.

## Structure

```
patches/
├── kustomization.yaml           # Master patch configuration
└── services/                    # Individual service patches
    ├── auth.yaml                # Auth service local overrides
    ├── user.yaml                # User service local overrides
    ├── product.yaml             # Product service local overrides
    ├── cart.yaml                # Cart service local overrides
    ├── order.yaml               # Order service local overrides
    ├── review.yaml              # Review service local overrides
    ├── notification.yaml        # Notification service local overrides
    ├── shipping.yaml            # Shipping service (v1) local overrides
    ├── shipping-v2.yaml         # Shipping service (v2) local overrides
    └── k6.yaml                  # K6 load testing local overrides
```

## Patch Pattern

**All patches use the "FULL env array" pattern:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: auth
  namespace: auth
spec:
  values:
    replicaCount: 1  # Override replica count
    resources:       # Override resources
      requests:
        memory: "32Mi"
        cpu: "25m"
    env:             # FULL env array (replaces entire array)
      - name: ENV
        value: "local"  # Changed from chart default
      - name: LOG_LEVEL
        value: "debug"  # Changed from chart default
      # ... ALL other env vars ...
```

**Why FULL env array?**
- Kustomize strategic merge **replaces entire arrays** if a full array is provided
- Cannot selectively override individual env vars
- Must specify complete env list with changes

## Local Environment Overrides

**Common changes for all services:**
1. `replicaCount: 1` (chart default: 2) - Single replica for resource saving
2. `resources.requests.memory: "32Mi"` (chart default: 64Mi) - Reduced memory
3. `resources.requests.cpu: "25m"` (chart default: 50m) - Reduced CPU
4. `ENV: "local"` (chart default: "production")
5. `LOG_LEVEL: "debug"` (chart default: "info") - More verbose logging
6. `OTEL_SAMPLE_RATE: "1.0"` (chart default: "0.1") - 100% sampling
7. `DB_POOL_MAX_CONNECTIONS: "10"` (chart default: 25) - Smaller connection pool
8. `DB_SSLMODE: "require"` - SSL enabled for all databases

## Service-Specific Details

### Backend Services (9 services)

| Service | Namespace | Database | Pooler | Notes |
|---------|-----------|----------|--------|-------|
| auth | auth | auth-db | PgBouncer | Zalando operator |
| user | user | supporting-db | No | Zalando operator |
| product | product | product-db | PgCat | CNPG operator |
| cart | cart | transaction-db | PgCat | CNPG operator |
| order | order | transaction-db | PgCat | CNPG operator |
| review | review | review-db | No | Zalando operator |
| notification | notification | supporting-db | No | Zalando operator |
| shipping | shipping | supporting-db | No | Zalando operator (v1) |
| shipping-v2 | shipping | supporting-db | No | Zalando operator (v2) |

### K6 Load Testing

**Reduced RPS for local:**
- `BASELINE_RPS: "10"` (chart default: 30)
- `PEAK_RPS: "30"` (chart default: 100)
- `BURST_RPS: "50"` (chart default: 200)
- `BURST_DURATION: "2m"` (chart default: 5m)

**Resources:**
- `requests.memory: "1Gi"` (chart default: 2Gi)
- `requests.cpu: "500m"` (chart default: 1000m)

## Adding New Service Patches

1. Create `services/<service-name>.yaml`
2. Copy structure from existing service
3. Update service-specific values
4. Add to `kustomization.yaml`:
   ```yaml
   - path: services/<service-name>.yaml
     target:
       kind: HelmRelease
       name: <service-name>
       namespace: <namespace>
   ```

## Verification

**Build locally:**
```bash
kustomize build kubernetes/overlays/local/apps/ | grep -A 5 "kind: HelmRelease"
```

**Check applied patches:**
```bash
kubectl get helmrelease -A -o yaml | grep -A 10 "replicaCount"
```

---

**Related:**
- Base manifests: [`kubernetes/base/apps/`](../../../base/apps/)
- Helm chart: [`charts/mop/`](../../../../charts/mop/)
- Research: [`specs/active/flux-gitops-migration/research.md`](../../../../specs/active/flux-gitops-migration/research.md#environment-specific-configuration-patterns)
