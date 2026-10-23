#!/usr/bin/env bash
# CDC target gate on Kind (RFC-0030 phase 6, rows G6.2 and G6.4 of the #1266
# gate catalog). Every probe prints PASS/FAIL; one FAIL fails the run.
#
#   G6.2  every mirror STATUS_RUNNING; each slot active, wal_status reserved,
#         retained WAL < 1 GB
#   G6.4  (--pii, mutating) marker rows carrying RFC0030_FORBIDDEN_PII in
#         non-allowlisted columns reach neither the raw tables, nor the
#         retained Avro staging, nor PeerDB's logs; every raw table's columns
#         are the allowlist plus _peerdb_*. Staging cleanup is switched off for
#         the run (mirror env) and back on afterwards; the markers are deleted.
#
#   scripts/analytics/cdc-target-check.sh          # G6.2 only
#   scripts/analytics/cdc-target-check.sh --pii    # G6.2 + G6.4
set -uo pipefail
cd "$(dirname "$0")/../.."
ALLOW=local-stack/analytics/allowlist.json
MARK=RFC0030_FORBIDDEN_PII
PRIMARY="$(kubectl -n product get cluster product-db -o jsonpath='{.status.currentPrimary}')"
CHPOD="$(kubectl -n monitoring get pods -l clickhouse.altinity.com/chi=clickhouse -o jsonpath='{.items[0].metadata.name}')"
CHPW="$(kubectl -n monitoring get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)"
S3KEY="$(kubectl -n peerdb get secret peerdb-rustfs-credentials -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)"
S3SECRET="$(kubectl -n peerdb get secret peerdb-rustfs-credentials -o jsonpath='{.data.ACCESS_SECRET_KEY}' | base64 -d)"
S3=http://rustfs-svc.rustfs.svc.cluster.local:9000/analytics-service-cdc
fail=0
ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; fail=1; }
pg()  { kubectl -n product exec "$PRIMARY" -c postgres -- psql -XAtq -d "$1" -c "$2" 2>&1; }
ch()  { kubectl -n monitoring exec "$CHPOD" -c clickhouse -- clickhouse-client --password "$CHPW" -q "$1" 2>&1; }

kubectl -n peerdb port-forward svc/flow-api 18114:8113 >/dev/null 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null' EXIT
sleep 3
api() { curl -s -X POST "http://127.0.0.1:18114$1" -H 'Content-Type: application/json' -d "$2"; }
state() { curl -s http://127.0.0.1:18114/v1/mirrors/list | python3 -c "import json,sys;print({m['name']:m['status'] for m in json.load(sys.stdin)['mirrors']}.get('$1','missing'))"; }

# ---- G6.2 ----------------------------------------------------------------
for db in order checkout payment; do
  m=analytics_service_$db
  s="$(state $m)"; [ "$s" = STATUS_RUNNING ] && ok "G6.2 $m $s" || bad "G6.2 $m $s"
  row="$(pg postgres "SELECT active, wal_status, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::bigint FROM pg_replication_slots WHERE slot_name='peerflow_slot_$m'")"
  IFS='|' read -r active wal lag <<<"$row"
  [ "$active" = t ] && [ "$wal" = reserved ] && [ "${lag:-0}" -lt 1073741824 ] 2>/dev/null \
    && ok "G6.2 slot $m active, reserved, retains $((lag/1024)) KiB" || bad "G6.2 slot $m: '$row'"
done

if [ "${1:-}" = --pii ]; then
  setenv() { # setenv <mirror> <true|false> — pause, update env, resume
    api /v1/mirrors/state_change "{\"flowJobName\":\"$1\",\"requestedFlowState\":\"STATUS_PAUSED\"}" >/dev/null
    for _ in $(seq 1 30); do [ "$(state "$1")" = STATUS_PAUSED ] && break; sleep 5; done
    api /v1/mirrors/state_change "{\"flowJobName\":\"$1\",\"requestedFlowState\":\"STATUS_RUNNING\",\"flowConfigUpdate\":{\"cdcFlowConfigUpdate\":{\"updatedEnv\":{\"PEERDB_CLICKHOUSE_SKIP_STAGING_CLEANUP\":\"$2\"}}}}" >/dev/null
    for _ in $(seq 1 30); do [ "$(state "$1")" = STATUS_RUNNING ] && break; sleep 5; done
  }
  for db in order checkout payment; do setenv "analytics_service_$db" true; done
  echo "      staging retained; inserting marker rows"
  pg order "INSERT INTO orders(id,user_id,subtotal,shipping,total,status) VALUES (-30000,'$MARK',1000,0,1000,'pending') ON CONFLICT DO NOTHING;
            INSERT INTO order_items(id,order_id,product_id,product_name,quantity,price,subtotal) VALUES (-30000,-30000,1,'gate product',1,1000,1000) ON CONFLICT DO NOTHING" >/dev/null
  pg checkout "INSERT INTO checkout_sessions(id,user_id,status,currency,expires_at,payment_method_token) VALUES ('00300000-0000-0000-0000-000000000001','$MARK','open','USD',now()+interval '1 day','$MARK') ON CONFLICT DO NOTHING" >/dev/null
  pg payment "INSERT INTO payments(id,user_id,order_id,amount_minor,currency,payment_method) OVERRIDING SYSTEM VALUE VALUES (-30000,'$MARK',-30000,1000,'USD','$MARK') ON CONFLICT DO NOTHING;
              INSERT INTO ledger_transactions(id,payment_id,kind,external_ref) OVERRIDING SYSTEM VALUE VALUES (-30000,-30000,'capture','$MARK') ON CONFLICT DO NOTHING" >/dev/null
  for _ in $(seq 1 36); do
    [ "$(ch "SELECT count() FROM analytics.payment_ledger_transactions WHERE id=-30000")" = 1 ] \
      && [ "$(ch "SELECT count() FROM analytics.checkout_checkout_sessions WHERE id='00300000-0000-0000-0000-000000000001'")" = 1 ] \
      && [ "$(ch "SELECT count() FROM analytics.order_orders WHERE id=-30000")" = 1 ] && break
    sleep 5
  done
  [ "$(ch "SELECT count() FROM analytics.order_orders WHERE id=-30000")" = 1 ] && ok "G6.4 marker rows reached ClickHouse (allowlisted columns)" || bad "G6.4 marker rows never arrived"

  # Raw tables: no marker anywhere, columns = allowlist + _peerdb_*.
  for t in $(ch "SELECT name FROM system.tables WHERE database='analytics' AND engine LIKE '%MergeTree' AND name NOT LIKE '\_peerdb%'"); do
    hits="$(ch "SELECT count() FROM analytics.\`$t\` WHERE position(toString(tuple(*)), '$MARK') > 0")"
    [ "$hits" = 0 ] || bad "G6.4 $t holds the marker ($hits rows)"
    cols="$(ch "SELECT arrayStringConcat(arraySort(groupArray(name)),',') FROM system.columns WHERE database='analytics' AND table='$t' AND name NOT LIKE '\_peerdb%'")"
    want="$(python3 -c "import json;a=json.load(open('$ALLOW'));db,_,tb='$t'.partition('_');c=a.get(db,{}).get(tb) or (['emitted_at','id'] if tb=='analytics_cdc_heartbeat' else None);print(','.join(sorted(c)) if c else '?')")"
    [ "$cols" = "$want" ] || bad "G6.4 $t columns [$cols] want [$want]"
  done
  [ $fail -eq 0 ] && ok "G6.4 raw tables: no marker, columns = allowlist + _peerdb_*"
  rawhits="$(ch "SELECT count() FROM merge('analytics','^_peerdb_raw') WHERE position(_peerdb_data, '$MARK') > 0")"
  [ "$rawhits" = 0 ] && ok "G6.4 _peerdb_raw_* staging tables: no marker" || bad "G6.4 _peerdb_raw_* holds the marker ($rawhits)"

  # Retained Avro in the bucket.
  avro="$(ch "SELECT count() FROM s3('$S3/**.avro','$S3KEY','$S3SECRET','One')" )"
  hits="$(ch "SELECT count() FROM s3('$S3/**.avro','$S3KEY','$S3SECRET','RawBLOB') WHERE position(raw_blob, '$MARK') > 0")"
  [ "${avro:-0}" -gt 0 ] 2>/dev/null && [ "$hits" = 0 ] && ok "G6.4 retained Avro staging: $avro files, no marker" || bad "G6.4 Avro staging: files=$avro marker-hits=$hits"

  # PeerDB logs.
  hits=0; for w in deploy/flow-worker deploy/flow-api deploy/peerdb-server sts/flow-snapshot-worker; do
    n="$(kubectl -n peerdb logs "$w" --since=30m 2>/dev/null | grep -c "$MARK")"; hits=$((hits+n)); done
  [ "$hits" = 0 ] && ok "G6.4 PeerDB logs: no marker" || bad "G6.4 PeerDB logs hold the marker ($hits lines)"

  # Clean up: marker rows (tombstones flow through) and staging retention.
  pg payment "DELETE FROM ledger_transactions WHERE id=-30000; DELETE FROM payments WHERE id=-30000" >/dev/null
  pg checkout "DELETE FROM checkout_sessions WHERE id='00300000-0000-0000-0000-000000000001'" >/dev/null
  pg order "DELETE FROM order_items WHERE id=-30000; DELETE FROM orders WHERE id=-30000" >/dev/null
  for db in order checkout payment; do setenv "analytics_service_$db" false; done
  echo "      markers deleted, staging cleanup restored"
fi

[ $fail -eq 0 ] && echo "cdc target gate: PASS" || { echo "cdc target gate: FAIL"; exit 1; }
