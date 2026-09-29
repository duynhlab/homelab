-- TO-style view: it owns no storage, which is what keeps it legal inside a
-- Replicated database. The declared Start/End are DateTime64(9) while the
-- target columns are DateTime; ClickHouse casts on insert. That asymmetry is
-- reproduced from as-built on purpose — do not 'fix' it.
-- Must be created AFTER otel_traces and otel_traces_trace_id_ts: a missing
-- MV loses trace-id lookups with no error anywhere.
CREATE MATERIALIZED VIEW IF NOT EXISTS otel.otel_traces_trace_id_ts_mv TO otel.otel_traces_trace_id_ts
(
    `TraceId` String,
    `Start` DateTime64(9),
    `End` DateTime64(9)
)
AS SELECT
    TraceId,
    min(Timestamp) AS Start,
    max(Timestamp) AS End
FROM otel.otel_traces
WHERE TraceId != ''
GROUP BY TraceId;
