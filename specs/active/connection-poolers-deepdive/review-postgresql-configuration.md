# Deep Dive Review: Database Pooler Connections & PostgreSQL Configuration

**Date:** 2026-01-26
**Reviewer:** Antigravity Agent
**Scope:** Connection Poolers (PgBouncer, PgCat, PgDog) and PostgreSQL Configuration (Parameters, Resources).

---

## 1. Executive Summary

The architectural diagrams in `docs/databases/DATABASE.md` accurately reflect the intended design for the connection poolers. However, a **critical misconfiguration** was found in the PostgreSQL resource tuning for `review-db` and `supporting-db`, where memory parameters (`shared_buffers`) significantly exceed the container memory limits, which would lead to immediate OOM kills or startup failures.

## 2. PostgreSQL Configuration Deep Dive & Findings

### 🔴 Critical Findings (Action Required)

The following clusters have `shared_buffers` configured larger than their Kubernetes memory limits. This is invalid.

| Cluster | Configured `shared_buffers` | Kubernetes Memory Limit | Status | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **review-db** | **64MB** | **256Mi** | ✅ **FIXED** | Decrease `shared_buffers` to **64MB** (25% of limit) |
| **supporting-db** | **64MB** | **256Mi** | ✅ **FIXED** | Decrease `shared_buffers` to **64MB** (25% of limit) |

**Root Cause:** It appears these values were copied from a high-performance production configuration (likely `auth-db`'s *config map* or a template) without checking the specific resource limits defined in `instance.yaml`.

### 🟢 Healthy Clusters

| Cluster | Configured `shared_buffers` | Kubernetes Memory Limit | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **auth-db** | 128MB | 2Gi | ✅ OK | Conservative sizing (6.25% of limit). |
| **transaction-db** | 256MB | 1Gi | ✅ OK | 25% of limit (Standard recommendation). |
| **product-db** | 64MB | 128Mi | ✅ OK | 50% of limit (Aggressive but valid). |

---

## 3. Connection Pooler Configuration Review

### 3.1 Auth Database (`auth-db`)
*   **Architecture Matches Diagram?** ✅ Yes
*   **Type:** Built-in PgBouncer (Sidecar)
*   **Service:** `auth-db-pooler` (Port 5432)
*   **Mode:** `transaction`
*   **Max Connections:** 240 (per pooler instance) implies ~480 total max db connections.
*   **PostgreSQL:** `max_connections: 500`.
*   **Review:** Configuration is consistent. `max_connections` (500) > Pooler Max (480), ensuring DB handles the pooler load.

### 3.2 Review Database (`review-db`)
*   **Architecture Matches Diagram?** ✅ Yes
*   **Type:** None (Direct Connection)
*   **Service:** `review-db` (Port 5432)
*   **Review:** Correctly configured without pooler section.

### 3.3 Supporting Database (`supporting-db`)
*   **Architecture Matches Diagram?** ✅ Yes
*   **Type:** Built-in PgBouncer (Sidecar)
*   **Service:** `supporting-db-pooler` (Port 5432)
*   **Mode:** `transaction`
*   **Databases:** Shared (`user`, `notification`, `shipping`)
*   **Review:** Configuration consistent with Shared Database pattern.

### 3.4 Transaction Database (`transaction-db`)
*   **Architecture Matches Diagram?** ✅ Yes
*   **Type:** PgCat (Standalone Deployment)
*   **Deployment:** `poolers/configmap.yaml` defines routing logic.
*   **Service:** `pgcat` (Port 5432 app / 9930 admin)
*   **Routing:**
    *   **Writes** -> `transaction-db-rw`
    *   **Reads** -> `transaction-db-r`
*   **Sharding:** Configured for `cart` and `order` databases.
*   **Review:** Complex routing logic is correctly defined in TOML.

### 3.5 Product Database (`product-db`)
*   **Architecture Matches Diagram?** ✅ Yes
*   **Type:** PgDog (Helm Release)
*   **Service:** `pgdog-product` (Port 6432)
*   **Mode:** `transaction`
*   **HA:** Single replica configured for dev env.
*   **Review:** Helm values correctly map to CloudNativePG service endpoints (`product-db-rw`).

---

## 4. Recommendations

1.  **Fix Review/Supporting DB Memory**: Immediately update `instance.yaml` for `review-db` and `supporting-db` to set `shared_buffers` to `64MB`.
2.  **Standardize Parameters**: `auth-db` uses `128MB` shared buffers for a `2Gi` container. This is very conservative. Consider increasing to `512MB` (25%) for better performance if cache hit ratio is low.
3.  **Documentation**: Update `DATABASE.md` to reflect the corrected resource values once applied.
