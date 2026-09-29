-- Applied to EVERY replica individually (no ON CLUSTER, no DDL queue).
-- ENGINE = Replicated is the point: table DDL then replicates through this
-- database's own Keeper log, so a replica added later initialises its own
-- tables. The znode path is stable and shared by all replicas by design;
-- {shard} and {replica} come from the operator-supplied macros.
CREATE DATABASE IF NOT EXISTS otel
    ENGINE = Replicated('/clickhouse/databases/otel', '{shard}', '{replica}');
