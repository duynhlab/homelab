#!/usr/bin/env bash
# Reader isolation sweep for analytics_reader (RFC-0030 / ADR-069, row K3.12).
# The identity analytics-service logs in with must read exactly the ten
# reviewed serving views and nothing else: no raw table, no other database,
# no write, no DDL, no settings escape. Modeled on db-isolation-sweep.sh:
# every probe is listed, every verdict is printed, a single wrong answer
# fails the run.
#
#   scripts/analytics-reader-sweep.sh            # Kind: reads the ESO Secret
#   CH_HOST=localhost CH_PASSWORD=analytics-reader-local scripts/analytics-reader-sweep.sh   # compose
set -euo pipefail

if [ -z "${CH_PASSWORD:-}" ]; then
  CH_PASSWORD="$(kubectl -n monitoring get secret clickhouse-analytics-reader -o jsonpath='{.data.password}' | base64 -d)"
  runner() { kubectl -n monitoring exec -i clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --host clickhouse-clickhouse.monitoring.svc.cluster.local "$@"; }
else
  runner() { clickhouse-client --host "${CH_HOST:-localhost}" "$@"; }
fi
query() { runner --user analytics_reader --password "$CH_PASSWORD" --query "$1" 2>&1; }

fail=0
expect() {
  # expect <ok|deny> <label> <sql>
  local want="$1" label="$2" sql="$3" out rc
  set +e; out="$(query "$sql")"; rc=$?; set -e
  if [ "$want" = ok ] && [ $rc -eq 0 ]; then echo "PASS  $label"
  elif [ "$want" = deny ] && [ $rc -ne 0 ] && printf '%s' "$out" | grep -qiE 'Not enough privileges|ACCESS_DENIED|readonly|Cannot execute query in readonly mode|UNKNOWN_DATABASE|UNKNOWN_TABLE'; then echo "PASS  $label (refused)"
  else echo "FAIL  $label: rc=$rc $(printf '%s' "$out" | head -c 160)"; fail=1; fi
}

for v in order_orders order_order_items checkout_checkout_sessions payment_payments payment_ledger_transactions payment_ledger_entries payment_ledger_accounts order_analytics_cdc_heartbeat checkout_analytics_cdc_heartbeat payment_analytics_cdc_heartbeat; do
  expect ok   "SELECT from analytics.${v}_live"  "SELECT count() FROM analytics.${v}_live"
  expect deny "SELECT from raw analytics.${v}"   "SELECT count() FROM analytics.${v}"
done
expect deny "INSERT into a raw table"            "INSERT INTO analytics.order_orders (id,status,version,created_at,updated_at,completed_at,_peerdb_is_deleted,_peerdb_version) VALUES (0,'x',0,now(),now(),NULL,0,0)"
expect deny "CREATE TABLE in analytics"          "CREATE TABLE analytics.escape (id Int32) ENGINE = Memory"
expect deny "DROP a view"                        "DROP VIEW analytics.order_orders_live"
expect deny "read otel traces"                   "SELECT count() FROM otel.otel_traces"
expect deny "read pg_stat_ch events"             "SELECT count() FROM pg_stat_ch.events_raw"
expect deny "read system.query_log"              "SELECT count() FROM system.query_log"
expect deny "SHOW other users' grants"           "SHOW GRANTS FOR default"
expect ok   "per-query settings are accepted (readonly=2)" "SELECT count() FROM analytics.order_orders_live SETTINGS max_execution_time=2, max_result_rows=1000, result_overflow_mode='throw'"

if [ $fail -eq 0 ]; then echo "reader sweep: PASS"; else echo "reader sweep: FAIL"; exit 1; fi
