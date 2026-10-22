#!/bin/sh
# Stands in for the pg_cron → PeerDB heartbeat path (ADR-068) while CDC is not
# deployed: every 30 seconds a new version of the single heartbeat row lands
# in each source's heartbeat table, so analytics-service observes a fresh
# target-side timestamp. Stop this container to drive the stale (>120 s) and
# unavailable (>300 s) states; start it to recover.
set -eu
host="${CLICKHOUSE_HOST:-clickhouse}"
interval="${HEARTBEAT_INTERVAL:-30}"
version=1
while :; do
  version=$((version + 1))
  for db in order checkout payment; do
    clickhouse-client --host "$host" --password "${CLICKHOUSE_PASSWORD:-otel}" --query \
      "INSERT INTO analytics.${db}_analytics_cdc_heartbeat (id, emitted_at, _peerdb_is_deleted, _peerdb_version) VALUES (1, now64(6), 0, ${version})" \
      || echo "heartbeat ${db} failed (version ${version})" >&2
  done
  sleep "$interval"
done
