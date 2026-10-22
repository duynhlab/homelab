#!/bin/sh
# Stands in for the pg_cron → PeerDB heartbeat path (ADR-068) while CDC is not
# deployed: every 30 seconds a new version of the single heartbeat row lands
# in each source's heartbeat table, so analytics-service observes a fresh
# target-side timestamp. Stop this container to drive the stale (>120 s) and
# unavailable (>300 s) states; start it to recover.
set -eu
host="${CLICKHOUSE_HOST:-clickhouse}"
interval="${HEARTBEAT_INTERVAL:-30}"
# Stop at once on SIGTERM: a loop that sits out its grace period writes one
# more heartbeat after "stop", which skews every freshness measurement.
trap 'exit 0' TERM INT
# The version must keep growing across restarts (PeerDB derives it from the
# WAL position): the views pick the row with the highest version, so a
# counter that restarts at 1 leaves the pre-restart row visible until the
# new life overtakes it, and the service never recovers from "unavailable".
while :; do
  for db in order checkout payment; do
    clickhouse-client --host "$host" --password "${CLICKHOUSE_PASSWORD:-otel}" --query \
      "INSERT INTO analytics.${db}_analytics_cdc_heartbeat (id, emitted_at, _peerdb_is_deleted, _peerdb_version) VALUES (1, now64(6), 0, toUnixTimestamp64Milli(now64(3)))" \
      || echo "heartbeat ${db} failed" >&2
  done
  sleep "$interval" &
  wait $!
done
