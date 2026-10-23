#!/bin/bash
# Creates the serving views once PeerDB's raw tables exist (views.sql). The
# database is Replicated, so one CREATE reaches every replica.
set -euo pipefail
cli() { clickhouse-client --host "$CLICKHOUSE_HOST" --password "$CLICKHOUSE_PASSWORD" "$@"; }
want=$(grep -c '^CREATE OR REPLACE VIEW' /views/views.sql)
tables=$(grep -o 'FROM analytics\.[a-z_]*' /views/views.sql | sed 's/FROM analytics\.//' | sort -u | sed "s/.*/'&'/" | paste -sd, -)
for i in $(seq 1 360); do
  have=$(cli -q "SELECT count() FROM system.tables WHERE database='analytics' AND name IN ($tables)")
  [ "$have" -eq "$want" ] && break
  [ $((i % 12)) -eq 1 ] && echo "waiting for raw tables: $have/$want"
  sleep 10
done
[ "$have" -eq "$want" ] || { echo "raw tables still missing ($have/$want)"; exit 1; }
cli --multiquery --queries-file /views/views.sql
echo "views: $(cli -q "SELECT count() FROM system.tables WHERE database='analytics' AND engine='View'")"
