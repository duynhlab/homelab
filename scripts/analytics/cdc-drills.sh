#!/usr/bin/env bash
# RFC-0030 phase 7 drills on Kind (gate rows G7.1-G7.7 of the #1266 catalog).
# Each drill prints PASS/FAIL with what it measured. Drill rows use negative
# ids and are deleted afterwards. Disruptive drills (failover, WAL
# invalidation, outages) touch product-db, RustFS or ClickHouse for minutes:
# run them one at a time, never alongside another gate.
#
#   scripts/analytics/cdc-drills.sh crud          # G7.1
#   scripts/analytics/cdc-drills.sh heartbeat 30  # G7.2 (minutes)
#   scripts/analytics/cdc-drills.sh failover      # G7.3 (+U7)
#   scripts/analytics/cdc-drills.sh schema        # G7.4
#   scripts/analytics/cdc-drills.sh walloss       # G7.5
#   scripts/analytics/cdc-drills.sh rotate        # G7.6 (needs BAO_TOKEN)
#   scripts/analytics/cdc-drills.sh outage        # G7.7
# G7.8 is scripts/analytics-freshness-drill.sh (GATE=kind).
set -uo pipefail
cd "$(dirname "$0")/../.."
NS=product
CHPOD="$(kubectl -n monitoring get pods -l clickhouse.altinity.com/chi=clickhouse -o jsonpath='{.items[0].metadata.name}')"
CHPW="$(kubectl -n monitoring get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)"
fail=0
ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; fail=1; }
primary() { kubectl -n $NS get cluster product-db -o jsonpath='{.status.currentPrimary}'; }
pg()  { kubectl -n $NS exec "$(primary)" -c postgres -- psql -XAtq -d "$1" -c "$2" 2>&1; }
ch()  { kubectl -n monitoring exec "$CHPOD" -c clickhouse -- clickhouse-client --password "$CHPW" -q "$1" 2>&1; }
api_up() { kubectl -n peerdb port-forward svc/flow-api 18115:8113 >/dev/null 2>&1 & PF=$!; sleep 3; }
api() { curl -s -X POST "http://127.0.0.1:18115$1" -H 'Content-Type: application/json' -d "$2"; }
mstate() { curl -s http://127.0.0.1:18115/v1/mirrors/list | python3 -c "import json,sys;print({m['name']:m['status'] for m in json.load(sys.stdin)['mirrors']}.get('$1','missing'))"; }
until_ch() { # until_ch <sql> <want> <timeout s> — prints seconds taken, 999 on timeout
  local t0=$SECONDS
  while [ $((SECONDS - t0)) -le "$3" ]; do [ "$(ch "$1")" = "$2" ] && { echo $((SECONDS - t0)); return 0; }; sleep 3; done
  echo 999; return 1
}
hb_age() { ch "SELECT max(dateDiff('second', emitted_at, now64(6))) FROM (SELECT max(emitted_at) emitted_at FROM analytics.order_analytics_cdc_heartbeat_live UNION ALL SELECT max(emitted_at) FROM analytics.checkout_analytics_cdc_heartbeat_live UNION ALL SELECT max(emitted_at) FROM analytics.payment_analytics_cdc_heartbeat_live)"; }

crud() { # G7.1
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-31000,'drill',100,0,100,'pending')" >/dev/null
  t="$(until_ch "SELECT status FROM analytics.order_orders_live WHERE id=-31000" pending 180)"; [ "$t" -le 120 ] && ok "G7.1 insert visible in ${t}s" || bad "G7.1 insert ${t}s"
  pg order "UPDATE orders SET status='completed', completed_at=now() WHERE id=-31000" >/dev/null
  t="$(until_ch "SELECT status||'/'||toString(completed_at IS NOT NULL) FROM analytics.order_orders_live WHERE id=-31000" completed/1 180)"; [ "$t" -le 120 ] && ok "G7.1 update + NULL→value visible in ${t}s" || bad "G7.1 update ${t}s"
  pg order "UPDATE orders SET completed_at=NULL WHERE id=-31000" >/dev/null
  t="$(until_ch "SELECT toString(completed_at IS NULL) FROM analytics.order_orders_live WHERE id=-31000" 1 180)"; [ "$t" -le 120 ] && ok "G7.1 value→NULL visible in ${t}s" || bad "G7.1 value→NULL ${t}s"
  pg order "DELETE FROM orders WHERE id=-31000" >/dev/null
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-31000" 0 180)"; [ "$t" -le 120 ] && ok "G7.1 delete gone from the view in ${t}s (tombstone kept in raw: $(ch "SELECT count() FROM analytics.order_orders WHERE id=-31000 AND _peerdb_is_deleted=1"))" || bad "G7.1 delete ${t}s"
}

heartbeat() { # G7.2
  local mins="${1:-30}" max=0 n=0 a
  local end=$((SECONDS + mins * 60))
  while [ $SECONDS -lt $end ]; do a="$(hb_age)"; n=$((n+1)); [ "${a:-999}" -gt "$max" ] && max=$a; sleep 15; done
  [ "$max" -le 120 ] && ok "G7.2 heartbeat age max ${max}s over ${mins} min ($n samples)" || bad "G7.2 heartbeat age reached ${max}s"
}

failover() { # G7.3 + U7
  local before after old new
  old="$(primary)"; new="$(kubectl -n $NS get pods -l cnpg.io/cluster=product-db,cnpg.io/instanceRole=replica -o jsonpath='{.items[0].metadata.name}')"
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) SELECT -32000-g,'drill',1,0,1,'pending' FROM generate_series(0,49) g" >/dev/null
  echo "      promoting $new (was $old)"
  kubectl cnpg promote product-db "$new" -n $NS >/dev/null
  for _ in $(seq 1 60); do [ "$(primary)" = "$new" ] && [ "$(kubectl -n $NS get cluster product-db -o jsonpath='{.status.phase}')" = "Cluster in healthy state" ] && break; sleep 5; done
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) SELECT -32100-g,'drill',1,0,1,'pending' FROM generate_series(0,49) g" >/dev/null
  slot="$(pg postgres "SELECT active FROM pg_replication_slots WHERE slot_name='peerflow_slot_analytics_service_order'")"
  t="$(until_ch "SELECT toString(count())||'/'||toString(uniqExact(id)) FROM analytics.order_orders WHERE id <= -32000 AND id > -32200" 100/100 600)"
  [ "$t" -le 600 ] && ok "G7.3 100/100 rows across the promotion in ${t}s, no duplicates; slot on new primary active=$slot" || bad "G7.3 rows after promotion (slot active=$slot)"
  pg order "DELETE FROM orders WHERE id <= -32000 AND id > -32200" >/dev/null
}

schema() { # G7.4
  api_up
  pg order "ALTER TABLE orders ADD COLUMN drill_note text" >/dev/null
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status,drill_note) VALUES (-33000,'drill',1,0,1,'pending','RFC0030_FORBIDDEN_PII')" >/dev/null
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-33000" 1 180)"
  col="$(ch "SELECT count() FROM system.columns WHERE database='analytics' AND table='order_orders' AND name='drill_note'")"
  [ "$t" -le 120 ] && [ "$col" = 0 ] && ok "G7.4 added column stays out of the target (row in ${t}s, column absent)" || bad "G7.4 add column: t=$t column=$col"
  pg order "DELETE FROM orders WHERE id=-33000; ALTER TABLE orders DROP COLUMN drill_note" >/dev/null
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-33001,'drill',1,0,1,'pending')" >/dev/null
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-33001" 1 180)"
  [ "$t" -le 120 ] && [ "$(mstate analytics_service_order)" = STATUS_RUNNING ] && ok "G7.4 dropped non-allowlisted column: mirror RUNNING, rows flow (${t}s)" || bad "G7.4 after drop: t=$t state=$(mstate analytics_service_order)"
  pg order "DELETE FROM orders WHERE id=-33001" >/dev/null
  kill $PF 2>/dev/null
}

resync() { # terminate + drop + re-bootstrap one mirror (the runbook step)
  local m=analytics_service_$1
  api /v1/mirrors/state_change "{\"flowJobName\":\"$m\",\"requestedFlowState\":\"STATUS_TERMINATING\"}" >/dev/null
  for _ in $(seq 1 60); do [ "$(mstate $m)" = missing ] && break; sleep 5; done
  for t in $(ch "SELECT name FROM system.tables WHERE database='analytics' AND (name LIKE '$1\\_%' OR name='_peerdb_raw_$m') AND engine NOT IN ('View')"); do ch "DROP TABLE analytics.\`$t\` SYNC" >/dev/null; done
  kubectl -n peerdb delete job peerdb-bootstrap --ignore-not-found >/dev/null
  flux reconcile kustomization cdc-local -n flux-system >/dev/null 2>&1
  kubectl -n peerdb wait --for=condition=complete job/peerdb-bootstrap --timeout=900s >/dev/null 2>&1
}

walloss() { # G7.5
  api_up
  local m=analytics_service_order
  api /v1/mirrors/state_change "{\"flowJobName\":\"$m\",\"requestedFlowState\":\"STATUS_PAUSED\"}" >/dev/null
  for _ in $(seq 1 30); do [ "$(mstate $m)" = STATUS_PAUSED ] && break; sleep 5; done
  echo "      mirror paused; writing ~1.2 GB of WAL"
  for _ in $(seq 1 12); do pg order "SELECT count(pg_logical_emit_message(false,'rfc0030-drill',repeat('x',1048576))) FROM generate_series(1,100)" >/dev/null; pg postgres "CHECKPOINT" >/dev/null; done
  ws="$(pg postgres "SELECT wal_status FROM pg_replication_slots WHERE slot_name='peerflow_slot_$m'")"
  disk="$(kubectl -n $NS exec "$(primary)" -c postgres -- df -h /var/lib/postgresql/data | tail -1 | awk '{print $5}')"
  [ "$ws" = lost ] && ok "G7.5 slot invalidated (wal_status=lost) at the 1 GB cap; primary data volume $disk used" || bad "G7.5 slot wal_status=$ws"
  local t0=$SECONDS; resync order
  want="$(pg order "SELECT count(*) FROM orders")"
  t="$(until_ch "SELECT toString(uniqExact(id)) FROM analytics.order_orders FINAL WHERE _peerdb_is_deleted=0" "$want" 600)"
  [ "$(mstate $m)" = STATUS_RUNNING ] && [ "$t" != 999 ] && ok "G7.5 resync: mirror RUNNING, $want orders in $((SECONDS - t0))s" || bad "G7.5 resync: state=$(mstate $m) want=$want"
  kill $PF 2>/dev/null
}

rotate() { # G7.6 — writes a new peerdb_order password through OpenBAO ($BAO_TOKEN, $BAO_CA)
  api_up
  local old new
  old="$(kubectl -n peerdb get secret product-db-peerdb-order-secret -o jsonpath='{.data.password}' | base64 -d)"
  new="$(head -c 32 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=')"
  curl -s --cacert "$BAO_CA" -H "X-Vault-Token: $BAO_TOKEN" -X POST https://openbao.duynh.me/v1/secret/data/local/databases/product-db/peerdb-order \
    -d "{\"data\":{\"username\":\"peerdb_order\",\"password\":\"$new\"}}" >/dev/null
  for ns in product peerdb; do kubectl -n $ns annotate externalsecret product-db-peerdb-order-secret force-sync="$(date +%s)" --overwrite >/dev/null; done
  for _ in $(seq 1 24); do [ "$(kubectl -n peerdb get secret product-db-peerdb-order-secret -o jsonpath='{.data.password}' | base64 -d)" = "$new" ] && break; sleep 5; done
  sleep 20  # CNPG reconciles the DatabaseRole password
  kubectl -n peerdb delete job peerdb-bootstrap --ignore-not-found >/dev/null
  flux reconcile kustomization cdc-local -n flux-system >/dev/null 2>&1
  kubectl -n peerdb wait --for=condition=complete job/peerdb-bootstrap --timeout=600s >/dev/null 2>&1
  # Force a reconnect: pause and resume.
  api /v1/mirrors/state_change '{"flowJobName":"analytics_service_order","requestedFlowState":"STATUS_PAUSED"}' >/dev/null
  for _ in $(seq 1 30); do [ "$(mstate analytics_service_order)" = STATUS_PAUSED ] && break; sleep 5; done
  api /v1/mirrors/state_change '{"flowJobName":"analytics_service_order","requestedFlowState":"STATUS_RUNNING"}' >/dev/null
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-34000,'drill',1,0,1,'pending')" >/dev/null
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-34000" 1 300)"
  oldok="$(kubectl -n $NS exec "$(primary)" -c postgres -- env PGPASSWORD="$old" psql -XAtq "host=localhost user=peerdb_order dbname=order sslmode=require" -c 'SELECT 1' 2>&1 | head -1)"
  [ "$t" -le 300 ] && [[ "$oldok" == *"password authentication failed"* ]] && ok "G7.6 rotated: mirror flows after reconnect (${t}s), old password refused" || bad "G7.6 rotate: t=$t old-login='$oldok'"
  pg order "DELETE FROM orders WHERE id=-34000" >/dev/null
  kill $PF 2>/dev/null
}

outage() { # G7.7
  local t
  echo "      RustFS down for 5 min"
  kubectl -n rustfs scale statefulset --all --replicas=0 >/dev/null 2>&1; kubectl -n rustfs scale deploy --all --replicas=0 >/dev/null 2>&1
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-35000,'drill',1,0,1,'pending')" >/dev/null
  sleep 300; echo "      heartbeat age during the outage: $(hb_age)s"
  kubectl -n rustfs scale statefulset --all --replicas=1 >/dev/null 2>&1; kubectl -n rustfs scale deploy --all --replicas=1 >/dev/null 2>&1
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-35000" 1 600)"
  [ "$t" -le 600 ] && ok "G7.7 RustFS outage: queued row landed ${t}s after restore" || bad "G7.7 RustFS: not recovered in 10 min"
  echo "      ClickHouse unreachable from peerdb for 5 min"
  kubectl apply -f - >/dev/null <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: drill-block-peerdb, namespace: monitoring}
spec:
  podSelector: {matchLabels: {clickhouse.altinity.com/chi: clickhouse}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchExpressions: [{key: kubernetes.io/metadata.name, operator: NotIn, values: [peerdb]}]}
EOF
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-35001,'drill',1,0,1,'pending')" >/dev/null
  sleep 300; echo "      heartbeat age during the outage: $(hb_age)s"
  kubectl -n monitoring delete networkpolicy drill-block-peerdb >/dev/null
  t="$(until_ch "SELECT count() FROM analytics.order_orders_live WHERE id=-35001" 1 600)"
  [ "$t" -le 600 ] && ok "G7.7 ClickHouse outage: queued row landed ${t}s after restore" || bad "G7.7 ClickHouse: not recovered in 10 min"
  pg order "DELETE FROM orders WHERE id IN (-35000,-35001)" >/dev/null
}

"$@"
[ $fail -eq 0 ] && echo "cdc drill $1: PASS" || { echo "cdc drill $1: FAIL"; exit 1; }
