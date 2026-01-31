# Deep Dive: pgsty/pg_exporter

## 1. Executive Summary
`pgsty/pg_exporter` is an advanced, high-density Prometheus exporter for PostgreSQL ecosystem monitoring. It is the core monitoring engine of the **Pigsty** (PostgreSQL in Graphic STYle) observability stack, known for its extreme granularity (600+ default metrics) and "Infrastructure as Code" approach to metric definition.

Unlike standard exporters that focus on basic uptake, `pgsty/pg_exporter` enables deep observability into database internals, making it a powerful tool for DBAs and performance engineers.

## 2. Architecture & Design Philosophy

### 2.1 Unified Monitoring Model
`pgsty/pg_exporter` simplifies the monitoring stack by acting as a comprehensive agent:
*   **Auto-Discovery**: It can automatically detect multiple databases within a single PostgreSQL instance (e.g., distinguishing between the `postgres` system DB and business DBs) and apply relevant queries to each.
*   **Self-Monitoring**: It exposes rich telemetry about its own performance and scrape durations.

### 2.2 Declarative Configuration (Infrastructure as Code)
The exporter's logic is almost entirely defined in **YAML**, not Go code.
*   **Collector Files**: Metrics are defined in modular files (e.g., `0460-pg_query.yml`, `0310-pg_size.yml`).
*   **Hot Reload**: You can modify metric definitions on the fly without recompiling.
*   **Dynamic Planning**: It queries the database version and installed extensions *before* scraping regarding which queries to run. For example, it only runs `pg_stat_statements` queries if the extension is detected.

## 3. Key Capabilities for PostgreSQL

### 3.1 Advanced Internal Statistics
It goes far beyond basic CPU/Memory/Connection counts to expose critical internal states:
*   **Bloat Analysis**: Estimates generic table and index bloat, essential for planning `VACUUM FULL` or `pg_repack` operations.
*   **WAL & Replication**: Detailed LSN differences, replication lag calculation, and replication slot status.
*   **Vacuum Progress**: Tracks dead tuple generation rates, autovacuum freeze age, and emergency vacuum triggers.
*   **Shared Buffers**: Usage analysis of PostgreSQL's shared memory.
*   **Checkpointing**: Checkpoint timing, frequency, and write overhead.

### 3.2 Wait Event Sampling
Crucially, it integrates with `pg_wait_sampling` (if installed) to provide high-frequency wait event analysis. This allows you to visualize exactly what the database is waiting for (Lock, IO, IPC, LWLock) over time, which is the gold standard for performance tuning.

### 3.3 Lock Monitoring
It provides detailed visibility into the locking subsystem:
*   **Blocking Trees**: Identifying which transaction is blocking others.
*   **Lock Types**: Breaking down locks by type (RowExclusive, AccessShare, etc.) and mode.

### 3.4 Dynamic Feature Detection
*   **Extension Detection**: Automatically enables `citus`, `timescaledb`, or `pgrpc` metrics if these extensions are present in the target database.
*   **Version Compatibility**: Automatically adjusts queries based on the PostgreSQL major version (10 through 17+).

## 4. Integration Guide

### 4.1 Running with Docker
The standard way to run it is as a sidecar or standalone container:

```bash
docker run -d \
  --name pg_exporter \
  -p 9630:9630 \
  -e PG_EXPORTER_URL="postgres://user:pass@host:5432/postgres" \
  pgsty/pg_exporter
```

### 4.2 CLI Flags
*   `--auto-discovery`: Scrape all DBs found on the target instance.
*   `--exclude-database`: Skip internal templates or specific DBs.
*   `--config`: Path to the YAML directory containing collector definitions.

## 5. Metrics Deep Dive

`pgsty/pg_exporter` organizes metrics into logical categories map to its collector files:

*   **0xxx**: Core Postgres (Version, Uptime, Settings)
*   **02xx**: Replication (Lag, Slots, Standbys)
*   **03xx**: Resource Usage (WAL, Checkpoints, BGWriter, Shared Buffers)
*   **04xx**: Activity (Backends, Wait Events, Locks, Transactions)
*   **05xx**: Progress (Vacuuming, Indexing, Clustering)
*   **06xx**: Database Objects (DB Stats, Publications)
*   **07xx**: Tables & Indexes (Row counts, Scans, Hit Ratios)

## 6. Comparison: Why use it?

| Feature | `prometheus-community/postgres_exporter` | `pgsty/pg_exporter` |
| :--- | :--- | :--- |
| **Philosophy** | Minimalist, stable core metrics. | Maximalist, "observe everything". |
| **Configuration** | Static queries (mostly), some custom query support. | **Fully Dynamic YAML** collectors. |
| **Metric Count** | ~50-100 default. | **600+** default. |
| **Overhead** | Very Low. | Medium (careful with expensive bloat queries on large DBs). |
| **Use Case** | General purpose K8s monitoring (Zalando default). | Deep DB Analysis, DBA-centric monitoring, Tuning. |

## 7. Conclusion
`pgsty/pg_exporter` is the "Power User" choice. It is ideal when you need deep visibility into *why* a database is slow (locks, bloat, wait events) rather than just *if* it is up. It transforms Prometheus into a comprehensive DBA dashboard.
