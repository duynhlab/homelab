# PgBouncer Exporter Comparison

This document compares two exporters for PgBouncer monitoring:
1.  **Prometheus Community PgBouncer Exporter** (`prometheus-community/pgbouncer_exporter`) - Currently deployed.
2.  **Pigsty PgExporter** (`pgsty/pg_exporter`) - Proposed alternative.

## 1. Prometheus Community PgBouncer Exporter
*   **Repository**: [prometheus-community/pgbouncer_exporter](https://github.com/prometheus-community/pgbouncer_exporter)
*   **Focus**: Single-purpose tool specifically for exposing PgBouncer metrics.
*   **Status**: Community standard, widely used, simple.
*   **Metrics**: Maps standard `SHOW STATS`, `SHOW POOLS`, etc., to Prometheus metrics (e.g., `pgbouncer_pools_client_active_connections`).
*   **Configuration**:
    *   Minimal configuration needed.
    *   Requires `ignore_startup_parameters = extra_float_digits` in PgBouncer config (as noted by User) if using certain drivers/versions, though often works out-of-the-box with Go lib/pq.
*   **Pros**: Lightweight, focused, "do one thing well", standard Prometheus naming conventions.
*   **Cons**: Limited configurability, hard-coded queries (mostly), less "dynamic".

## 2. Pigsty PgExporter
*   **Repository**: [pgsty/pg_exporter](https://github.com/pgsty/pg_exporter) (fork/evolution of `wrouesnel/postgres_exporter` and others).
*   **Focus**: "Ultimate" monitoring solution for both PostgreSQL and PgBouncer.
*   **Status**: Feature-rich, highly configurable, part of the Pigsty ecosystem.
*   **Metrics**: 600+ metrics, covering extensive internal Postgres stats + PgBouncer.
*   **Configuration**:
    *   **YAML-based**: Heavily relies on `pg_exporter.yml` and collector files (e.g., `0910-pgbouncer_list.yml`).
    *   **Dynamic**: Allows defining custom queries, flexible tags, predicates, and per-db/per-user filtering.
*   **Pros**:
    *   **Unified Binary**: Monitors *both* Postgres and PgBouncer in one go (if configured).
    *   **Declarative**: Metrics defined in YAML, easy to add/modify without rebuilding binary.
    *   **Richness**: Extremely detailed metrics (locks, wait events, bloated tables, etc.).
    *   **Auto-discovery**: Can discover multiple DBs.
*   **Cons**:
    *   **Complexity**: Higher learning curve, more complex configuration management (managing YAML files).
    *   **Overhead**: Potentially heavier if all 600+ metrics are enabled blindly.

## 3. Comparison for Zalando Cluster Context

| Feature | Community Exporter | PgSty Exporter |
| :--- | :--- | :--- |
| **Simplicity** | ✅ High (Plug & Play) | ❌ Low (Requires config management) |
| **Customization** | ❌ Low (Code changes required) | ✅ High (YAML config) |
| **Scope** | PgBouncer Only | PostgreSQL + PgBouncer |
| **Integration** | Easy (Sidecar/Standalone) | Easy (Sidecar/Standalone) |
| **Metric Volume** | Low (~20-50 metrics) | High (600+ capability) |
| **Startup Param Fix** | May need ignoring `extra_float_digits` | Likely handles connection params robustly |

## 4. Recommendation

### Keep `prometheus-community/pgbouncer_exporter` if:
*   You only need standard PgBouncer metrics (pool sizes, client counts, wait times).
*   You want a lightweight, maintenance-free solution.
*   You are already using `postgres_exporter` sidecar for the DB itself (which Zalando operator provides by default). **This is key**: The Zalando pods already have a `postgres_exporter` sidecar. adding `pgsty/pg_exporter` might be redundant unless you replace the default one.

### Switch to `pgsty/pg_exporter` if:
*   You find standard metrics insufficient and need custom queries on PgBouncer (rare).
*   You want to consolidate tooling (use one binary for ALL Postgres monitoring) and replace the Zalando default exporter (complex to orchestrate with Operator).
*   You need extreme granularity or "Pigsty-style" observability.

### Current Decision for Auth-DB
Since we are adding this *on top* of an existing Zalando setup (which already has `postgres-exporter` sidecar), the **Community Exporter** is the logical choice for minimal interference. It fills the specific gap (PgBouncer) without overlapping with the existing DB monitoring.

**Note on `ignore_startup_parameters`**:
The user noted: "The pgbouncer_exporter requires ... `ignore_startup_parameters = extra_float_digits`".
We should verify if our current `auth-db` PgBouncer deployment needs this. If the exporter is crashing or failing to scrape due to "unsupported startup parameter", we must apply this change to the Zalando cluster config (`connectionPooler` section). However, our verification in Step 517 showed successful scraping (`pgbouncer_up 1`), so it might *not* be strictly necessary with the current versions, but it's good practice to be aware of.
