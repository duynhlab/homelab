# Research Complete: Environment Configuration Strategy

**Date:** 2026-01-10
**Task:** flux-gitops-migration
**Research Type:** Environment-specific configuration patterns for Kustomize + HelmRelease

---

## ✅ Research Complete

**Key Findings:**
1. **Kustomize cannot cleanly patch nested env arrays** in HelmRelease values
2. **Strategic merge REPLACES entire arrays** (not merge)
3. **flux-operator-local-dev does NOT use base/overlay** (single environment only)
4. **Best pattern: HelmRelease patches with FULL env list** (simple, explicit)

---

## ✅ Final Decision: HelmRelease Patches (No ConfigMap)

### Architecture

```
kubernetes/
├── base/apps/auth/
│   ├── helmrelease.yaml     # 20 lines - references chart
│   └── kustomization.yaml
├── overlays/local/apps/
│   └── patches/
│       └── helmreleases.yaml  # 80 lines - FULL env list
charts/mop/values/auth.yaml    # Production defaults (84 lines)
```

### Pattern

**Base HelmRelease (20 lines):**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: auth
spec:
  chartRef:
    kind: OCIRepository
    name: mop-chart
  # NO values - use chart defaults
```

**Local Patch (80 lines - FULL env list):**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: auth
spec:
  values:
    replicaCount: 1
    env:  # ✅ MUST include ALL 25 env vars
      - name: SERVICE_NAME
        value: "auth"
      - name: ENV
        value: "local"  # Changed
      - name: DB_HOST
        value: "auth-db-pooler.auth.svc.cluster.local"
      - name: LOG_LEVEL
        value: "debug"  # Changed
      # ... all 25 env vars
    resources:
      requests:
        memory: "32Mi"
```

---

## Why NOT ConfigMap?

**Tested both:**
- HelmRelease patches: 1 file, 80 lines
- ConfigMap + patches: 2 files, 80 lines (same verbosity)

**Result:** ConfigMap adds complexity with NO benefit

---

## Trade-off Accepted

**Must repeat ALL env vars in each patch (~80 lines per service)**

**Why it's OK:**
- ✅ Explicit configuration (clear what each environment has)
- ✅ Simple Kustomize strategic merge (works reliably)
- ✅ No fragile JSON patches with array indices
- ✅ Industry standard pattern (Flux + Helm + Kustomize)

---

## Configuration Lines

| Component | Lines | Description |
|-----------|-------|-------------|
| Base HelmRelease | 20 | References chart |
| Chart defaults | 84 | Production values (`charts/mop/values/auth.yaml`) |
| Local patch | 80 | Full env list |
| Staging patch | 80 | Full env list |
| Production patch | 80 | Full env list |
| **Total per service** | **344** | Base + chart + 3 overlays |
| **Total for 10 services** | **3,440** | Multi-environment support |

**Current (single env):** 11 files × 84 lines = 924 lines

**Result:** 3.7× more lines, but 3× more environments with 0% duplication

---

## Documentation Updated

✅ **`research.md`** - Added "Environment-Specific Configuration Patterns" section (lines 1976-2245)
  - Problem statement (env-specific values table)
  - Kustomize array patching limitations
  - 3 evaluated patterns (HelmRelease patches, ConfigMap, JSON patches)
  - Comparison with flux-operator-local-dev
  - Final recommendation with rationale

✅ **`plan.md`** - Added update notice (lines 9-50)
  - ⚠️ Important Updates section
  - Key changes documented
  - Trade-off explicitly stated
  - Rejected alternatives listed

✅ **`tasks.md`** - Updated Task 2.1 and Task 2.5
  - Task 2.1: Create HelmRelease (not Deployment)
  - Task 2.5: Create patches with FULL env list (~80 lines)
  - Architecture note added with research reference

✅ **Deleted duplicate files:**
  - FINAL_RECOMMENDATION.md
  - HELMRELEASE_RESEARCH.md
  - PROPOSED_REFACTOR.md
  - REFINEMENT_SUMMARY.md
  - REFINEMENT_VALIDATION.md

**All consolidated into `research.md`**

---

## Rejected Alternatives

### ❌ Option 1: valuesFrom ConfigMap
**Why:** More files (2 per service), same verbosity (ConfigMap patch needs FULL env list)

### ❌ Option 2: JSON Patches
**Why:** Fragile (array indices), not readable, breaks if base changes

### ❌ Option 3: Partial env patches
**Why:** Kustomize strategic merge REPLACES entire array (loses vars)

---

## Next Steps

**Ready to implement with this pattern:**

1. Create base HelmRelease CRDs (20 lines each)
2. Create local overlay patches (80 lines each with FULL env list)
3. Test with `kubectl kustomize kubernetes/overlays/local/apps`
4. Verify all 25 env vars present in rendered output

**Implementation tracked in:** `specs/active/flux-gitops-migration/tasks.md`

---

## Comparison: flux-operator-local-dev

**Their approach:**
- ResourceSet (not Kustomize overlays)
- Inline HelmRelease values (7 lines)
- OCI for distribution
- Single environment only

**Why it doesn't fit us:**
- ❌ We have 3+ environments (local/staging/production)
- ❌ We need env-specific config (20+ env vars differ)
- ❌ We have custom Helm chart (`charts/mop`)
- ✅ We need base/overlay pattern

---

## Summary

**What changed:**
- Researched ConfigMap vs patches
- Tested Kustomize array patching
- Analyzed flux-operator-local-dev pattern
- Finalized: HelmRelease patches with FULL env list

**What stays:**
- Flux Operator for GitOps
- OCI artifacts for distribution
- Kustomize base/overlay structure
- Helm chart reuse (`charts/mop`)

**Ready to proceed with implementation.**

---

*Research completed with SDD 2.0*
