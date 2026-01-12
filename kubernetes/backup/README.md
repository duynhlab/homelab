# Backup: Old Base/Overlay Structure

This directory contains the **old base/overlay Kustomize structure** that was refactored on 2026-01-12.

## Why Moved?

The project was refactored to use a **simplified structure** following the reference project pattern (`flux-operator-local-dev`):

- **Old:** `base/` + `overlays/local/` (complex, over-engineered for personal learning project)
- **New:** `infra/` + `apps/` (direct manifests, simpler, easier to maintain)

## Contents

- `base/` - Old base manifests (infrastructure + apps)
- `overlays/` - Old overlay patches (local/staging/production)

## Migration

All manifests have been consolidated:
- Infrastructure → `../infra/*.yaml` (consolidated from `base/infrastructure/`)
- Applications → `../apps/*.yaml` (merged base + patches with local config inline)

## When to Delete

You can safely delete this backup directory after:
1. ✅ Verifying new structure works (`make flux-push`, `flux get kustomizations`)
2. ✅ Testing reconciliation successfully
3. ✅ Confirming all services deploy correctly

**Date:** 2026-01-12  
**Refactor:** Simplified structure (no base/overlay)
