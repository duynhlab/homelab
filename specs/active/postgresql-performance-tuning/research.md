# Research: Top 10 Critical PostgreSQL Tuning Parameters

**Topic:** PostgreSQL Performance Tuning
**Source:** User Recommendation (Expert Best Practices)
**Date:** 2026-01-26
**Status:** Reference

---

## Executive Summary
This document outlines the **Top 10 most critical configuration parameters** for optimizing PostgreSQL performance. These settings control memory usage, checkpointing, caching, and background maintenance. Correct content is crucial for system stability and high throughput.

---

## 🔝 Top 10 Tuning Parameters

### 1️⃣ shared_buffers
**Description**: Determines the amount of RAM dedicated to caching database data (tables & indexes).
*   **Recommendation**: **25-40% of RAM**.
*   **Example**: For a 16GB RAM server, set to `4GB` - `6GB`.
*   **Impact**: Increases read/write speed, reduces physical disk access.
*   **Note**: Setting this too high can starve the OS cache, which PostgreSQL also relies on.

### 2️⃣ work_mem
**Description**: Maximum memory used for *each* query operation (sort, hash, join, etc.) before writing to temporary disk files.
*   **Recommendation**: **4MB - 64MB** (depends on active connections).
*   **Example**: For 100 max connections, `16MB` is often a safe starting point.
*   **Impact**:
    *   **Too Low**: Queries spill to disk (slow).
    *   **Too High**: Risk of OOM (Out Of Memory) crashes if many connections query simultaneously.
    *   *Calculation*: `Total RAM / Max Connections` (approximate safe upper bound).

### 3️⃣ maintenance_work_mem
**Description**: Memory used for maintenance operations like `VACUUM`, `CREATE INDEX`, and foreign key additions.
*   **Recommendation**: **64MB - 512MB** (Usually higher than `work_mem`).
*   **Impact**: Higher values speed up database restoration, index creation, and vacuuming.

### 4️⃣ effective_cache_size
**Description**: A *hint* to the query planner about how much RAM is available for disk caching (including OS filesystem cache). It does not allocate actual memory.
*   **Recommendation**: **50-75% of RAM**.
*   **Example**: `8GB` - `12GB` for a 16GB server.
*   **Impact**: Helps the planner choose between Index Scans (random I/O, better if cache is large) and Sequential Scans.

### 5️⃣ max_connections
**Description**: Maximum number of concurrent client connections allowed.
*   **Recommendation**: **100 - 200**.
*   **Best Practice**: Use a **connection pooler** (e.g., PgBouncer) if you need more clients.
*   **Impact**: Setting this too high increases overhead and lock contention, risking CPU/RAM saturation.

### 6️⃣ wal_buffers
**Description**: Memory used to buffer Write-Ahead Log (WAL) data before writing to disk.
*   **Recommendation**: **8MB - 16MB** (Increase for high-write systems).
*   **Impact**: Reduces transaction latency by grouping disk writes.

### 7️⃣ checkpoint_completion_target
**Description**: Determines how spread out the checkpoint writes are (as a fraction of the checkpoint interval).
*   **Recommendation**: **0.7 - 0.9** (Default is often 0.5).
*   **Impact**: Spreads the I/O load more evenly, preventing "I/O spikes" or "lag" during checkpoints.

### 8️⃣ WAL Size (max_wal_size & min_wal_size)
**Description**: Controls the size of WAL files and checkpoint frequency.
*   **Recommendation**:
    *   `max_wal_size`: **1GB - 4GB**
    *   `min_wal_size`: **80MB - 256MB**
*   **Impact**: Larger values reduce checkpoint frequency (better performance) but increase crash recovery time and disk usage.

### 9️⃣ Cost Constants (random_page_cost & seq_page_cost)
**Description**: Cost estimates used by the planner. `random_page_cost` represents the cost of a non-sequential fetch.
*   **Recommendation**:
    *   `seq_page_cost`: **1.0** (Baseline)
    *   `random_page_cost`: **1.1 - 2.0** (For SSDs). Default `4.0` is for HDDs.
*   **Impact**: Lowering `random_page_cost` encourages the planner to use Index Scans more often, which is appropriate for low-latency SSD storage.

### 🔟 autovacuum
**Description**: Configuration for the background process that cleans up dead tuples and prevents bloat.
*   **Recommendation**:
    *   `autovacuum_vacuum_cost_limit`: **200 - 2000** (Increases limit so vacuum works harder/faster).
    *   `autovacuum_vacuum_scale_factor`: **0.1 - 0.2** (10-20% of table changed triggers vacuum).
    *   `autovacuum_analyze_scale_factor`: **0.05 - 0.1** (5-10% change triggers analyze).
*   **Impact**: Ensures the database remains healthy and compact over time without manual intervention.

---
**Summary Checklist**
- [ ] RAM < 1GB? Watch out for `shared_buffers` and `maintenance_work_mem`.
- [ ] High writes? Increase `wal_buffers` and `max_wal_size`.
- [ ] SSD Storage? Set `random_page_cost = 1.1`.
- [ ] Connection Pool? Keep `max_connections` low (~200).
