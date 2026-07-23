#!/usr/bin/env bash
# RFC-0021 phase-0 baseline e2e (planning gate §0.7): prove the pre-refactor
# saga behaviors on current main before any inventory work lands. Run against
# a healthy local-stack (docker compose up -d --build in local-stack/, every
# sibling repo on main). Results are archived in
# docs/proposals/rfc/RFC-0021/baseline-e2e-results.md.
#
# Scenarios:
#   S1 happy path            confirm -> saga -> order confirmed, money captured,
#                            shipment created, stock decremented, cart cleared
#   S2 payment decline       total_minor%100==02 -> order failed, stock untouched
#   S3 insufficient @reserve two users race the last unit -> exactly one wins;
#                            the loser's authorization is voided (TOCTOU)
#   S4 duplicate confirm     same Idempotency-Key -> same order, one saga
#   S5 shipment failure      shipping down -> retries exhaust -> compensation
#                            (stock released, payment voided, order failed)
#   S6 worker outage         worker down across confirm -> order pending ->
#                            worker up -> converges confirmed (durable queue)
#   S7 capture failure       SKIPPED: mockpay has no capture-failure knob
#                            (charge-only magic amounts) — phase-7 chaos item
#
# Kong rate-limits 5 req/s: every api call is paced >=0.3s.
set -uo pipefail

BASE=${BASE:-http://localhost:8080}
COMPOSE_DIR=${COMPOSE_DIR:-$(cd "$(dirname "$0")/../local-stack" && pwd)}
PACE=0.3
PASS=0; FAIL=0; declare -a RESULTS

say()  { printf '%s\n' "$*"; }
pace() { sleep "$PACE"; }
ok()   { PASS=$((PASS+1)); RESULTS+=("| $1 | $2 | PASS | $3 |"); say "PASS  $1 $2 — $3"; }
bad()  { FAIL=$((FAIL+1)); RESULTS+=("| $1 | $2 | FAIL | $3 |"); say "FAIL  $1 $2 — $3"; }
skip() { RESULTS+=("| $1 | $2 | SKIP | $3 |"); say "SKIP  $1 $2 — $3"; }

dc()   { docker compose --project-directory "$COMPOSE_DIR" "$@"; }
sql()  { local db=$1; shift; dc exec -T postgres psql -U postgres -d "$db" -tA -c "$*"; }
jqy()  { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

login() { # $1 user $2 pass -> access token
  curl -s -X POST "$BASE/auth/v1/public/auth/login" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$2\"}" | jqy "['access_token']"
}

ensure_user() { # $1 user $2 pass $3 email — register, tolerate existing
  curl -s -o /dev/null -X POST "$BASE/auth/v1/public/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$2\",\"email\":\"$3\"}"
  pace
}

# ready_session AT PRODUCT_ID QTY -> session id on stdout (state=ready).
ready_session() {
  local at=$1 pid=$2 qty=$3 sid
  curl -s -o /dev/null -X DELETE "$BASE/cart/v1/private/cart" -H "Authorization: Bearer $at" || true; pace
  curl -s -o /dev/null -X POST "$BASE/cart/v1/private/cart" -H "Authorization: Bearer $at" \
    -H 'Content-Type: application/json' \
    -d "{\"product_id\":\"$pid\",\"product_name\":\"baseline\",\"product_price\":1,\"quantity\":$qty}"; pace
  sid=$(curl -s -X POST "$BASE/checkout/v1/private/checkout/sessions" -H "Authorization: Bearer $at" | jqy "['id']"); pace
  curl -s -o /dev/null -X PUT "$BASE/checkout/v1/private/checkout/sessions/$sid/address" \
    -H "Authorization: Bearer $at" -H 'Content-Type: application/json' \
    -d '{"full_name":"Baseline","line1":"1 Main St","city":"HN","country":"VN"}'; pace
  curl -s -o /dev/null -X PUT "$BASE/checkout/v1/private/checkout/sessions/$sid/shipping" \
    -H "Authorization: Bearer $at" -H 'Content-Type: application/json' \
    -d '{"shipping_method":"standard"}'; pace
  curl -s -o /dev/null -X PUT "$BASE/checkout/v1/private/checkout/sessions/$sid/payment" \
    -H "Authorization: Bearer $at" -H 'Content-Type: application/json' \
    -d '{"payment_method_token":"tok_visa_ok"}'; pace
  echo "$sid"
}

confirm() { # SID AT KEY -> confirm response body
  local sid=$1 at=$2 key=$3
  curl -s -X POST "$BASE/checkout/v1/private/checkout/sessions/$sid/confirm" \
    -H "Authorization: Bearer $at" -H "Idempotency-Key: $key"
}

order_status() { # OID AT
  curl -s "$BASE/order/v1/private/orders/$1" -H "Authorization: Bearer $2" | jqy "['status']" 2>/dev/null
}

wait_order() { # OID AT WANT TIMEOUT_S -> 0 if reached
  local oid=$1 at=$2 want=$3 t=$4 s
  for _ in $(seq 1 $((t/3))); do
    s=$(order_status "$oid" "$at")
    [ "$s" = "$want" ] && return 0
    sleep 3
  done
  say "  (order $oid stuck at '$s', wanted '$want')"
  return 1
}

payment_status() { sql payment "SELECT status FROM payments WHERE order_id=$1 ORDER BY id DESC LIMIT 1"; }
stock_of()       { sql product "SELECT stock_quantity FROM products WHERE id=$1"; }
set_stock()      { sql product "UPDATE products SET stock_quantity=$2 WHERE id=$1" >/dev/null; }
set_price()      { sql product "UPDATE products SET price=$2 WHERE id=$1" >/dev/null; }

# Product 3 is the baseline guinea pig; capture and restore its row.
PID=3
ORIG_PRICE=$(sql product "SELECT price FROM products WHERE id=$PID")
ORIG_STOCK=$(stock_of $PID)
restore() { set_price $PID "$ORIG_PRICE"; set_stock $PID "$ORIG_STOCK"; }
trap restore EXIT

say "== RFC-0021 baseline e2e ($(date -u +%FT%TZ)) product=$PID price=$ORIG_PRICE stock=$ORIG_STOCK"
AT=$(login alice password123)
[ -n "$AT" ] || { say "ABORT: login failed — is the stack up?"; exit 1; }

# ---------- S1 happy path -------------------------------------------------
set_price $PID 20.00; set_stock $PID 10
SID=$(ready_session "$AT" $PID 2)
C=$(confirm "$SID" "$AT" "bl-s1-$$")
OID=$(echo "$C" | jqy "['order_id']")
if [ -n "$OID" ] && wait_order "$OID" "$AT" confirmed 60; then
  ok S1 confirm "order $OID confirmed"
else
  bad S1 confirm "order '$OID' did not confirm"
fi
[ "$(payment_status "$OID")" = "captured" ] \
  && ok S1 payment "captured" || bad S1 payment "status=$(payment_status "$OID")"
[ "$(sql shipping "SELECT COUNT(*) FROM shipments WHERE order_id='$OID'")" = "1" ] \
  && ok S1 shipment "one shipment row" || bad S1 shipment "shipment row missing"
[ "$(stock_of $PID)" = "8" ] \
  && ok S1 stock "10-2=8" || bad S1 stock "stock=$(stock_of $PID), want 8"
CART=$(curl -s "$BASE/cart/v1/private/cart" -H "Authorization: Bearer $AT" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('items') or []))"); pace
[ "$CART" = "0" ] && ok S1 cart "cleared" || bad S1 cart "items=$CART"
NOTI=$(sql notification "SELECT COUNT(*) FROM notifications WHERE message LIKE '%#$OID %' OR message LIKE '%#$OID.%' OR title LIKE '%#$OID %'")
[ "${NOTI:-0}" -ge 1 ] && ok S1 notify "$NOTI inbox rows" || bad S1 notify "no inbox rows"

# ---------- S2 payment decline (total_minor%100==02) ----------------------
# total = p + 3.00 + round((p+3.00)*.08, 2); pick integer cents p (qty=1)
# whose total ends in .x2. Mirror Go's rounding by avoiding half-cent edges.
P2=$(python3 - <<'EOF'
for p in range(2000, 2400):
    fee = 300
    tax = round((p + fee) * 0.08)
    if abs(((p + fee) * 0.08) - tax - 0.5) < 1e-9:  # half-cent edge, skip
        continue
    if (p + fee + tax) % 100 == 2:
        print(f"{p/100:.2f}"); break
EOF
)
set_price $PID "$P2"; set_stock $PID 10
SID=$(ready_session "$AT" $PID 1)
TOTAL=$(curl -s "$BASE/checkout/v1/private/checkout/sessions/$SID" -H "Authorization: Bearer $AT" | jqy "['total']"); pace
C=$(confirm "$SID" "$AT" "bl-s2-$$")
OID2=$(echo "$C" | jqy "['order_id']")
if [ -n "$OID2" ] && wait_order "$OID2" "$AT" failed 60; then
  ok S2 decline "total=$TOTAL -> order failed"
else
  bad S2 decline "total=$TOTAL order='$OID2' status=$(order_status "$OID2" "$AT")"
fi
[ "$(stock_of $PID)" = "10" ] \
  && ok S2 stock "untouched (authorize declined before reserve)" \
  || bad S2 stock "stock=$(stock_of $PID), want 10"

# ---------- S3 insufficient stock at reserve (two-user race) ---------------
ensure_user bob password123 bob@baseline.local
BT=$(login bob password123)
if [ -z "$BT" ]; then
  skip S3 race "could not provision second user"
else
  set_price $PID 15.00; set_stock $PID 1
  SIDA=$(ready_session "$AT" $PID 1)
  SIDB=$(ready_session "$BT" $PID 1)
  CA=$(confirm "$SIDA" "$AT" "bl-s3a-$$") &
  PA=$!
  CB=$(confirm "$SIDB" "$BT" "bl-s3b-$$")
  wait $PA 2>/dev/null
  # re-issue A's confirm with the SAME key: idempotent read of its outcome
  CA=$(confirm "$SIDA" "$AT" "bl-s3a-$$")
  OA=$(echo "$CA" | jqy "['order_id']"); OB=$(echo "$CB" | jqy "['order_id']")
  wait_order "$OA" "$AT" confirmed 90 >/dev/null 2>&1
  wait_order "$OB" "$BT" confirmed 90 >/dev/null 2>&1
  SA=$(order_status "$OA" "$AT"); SB=$(order_status "$OB" "$BT")
  WINS=0; [ "$SA" = "confirmed" ] && WINS=$((WINS+1)); [ "$SB" = "confirmed" ] && WINS=$((WINS+1))
  if [ "$WINS" = "1" ]; then
    ok S3 race "exactly one winner (alice=$SA bob=$SB)"
  else
    bad S3 race "winners=$WINS (alice=$SA bob=$SB)"
  fi
  LOSER=$OA; [ "$SB" != "confirmed" ] && LOSER=$OB
  [ "$(payment_status "$LOSER")" = "voided" ] \
    && ok S3 void "loser's authorization voided" \
    || bad S3 void "loser payment=$(payment_status "$LOSER"), want voided"
  [ "$(stock_of $PID)" = "0" ] \
    && ok S3 stock "last unit sold once" || bad S3 stock "stock=$(stock_of $PID), want 0"
fi

# ---------- S4 duplicate confirm (same key) --------------------------------
set_price $PID 12.00; set_stock $PID 10
SID=$(ready_session "$AT" $PID 1)
K="bl-s4-$$"
O1=$(confirm "$SID" "$AT" "$K" | jqy "['order_id']"); pace
O2=$(confirm "$SID" "$AT" "$K" | jqy "['order_id']")
if [ -n "$O1" ] && [ "$O1" = "$O2" ]; then
  ok S4 replay "same order $O1 on both confirms"
else
  bad S4 replay "orders '$O1' vs '$O2'"
fi
wait_order "$O1" "$AT" confirmed 60 >/dev/null 2>&1
[ "$(stock_of $PID)" = "9" ] \
  && ok S4 effect "stock decremented exactly once" \
  || bad S4 effect "stock=$(stock_of $PID), want 9"

# ---------- S5 shipment failure -> full compensation ------------------------
set_price $PID 18.00; set_stock $PID 10
SID=$(ready_session "$AT" $PID 1)
dc stop shipping >/dev/null 2>&1
C=$(confirm "$SID" "$AT" "bl-s5-$$")
OID5=$(echo "$C" | jqy "['order_id']")
if [ -n "$OID5" ] && wait_order "$OID5" "$AT" failed 180; then
  ok S5 fail "retries exhausted -> order failed"
else
  bad S5 fail "order '$OID5' status=$(order_status "$OID5" "$AT")"
fi
dc start shipping >/dev/null 2>&1
[ "$(stock_of $PID)" = "10" ] \
  && ok S5 release "stock released by compensation" \
  || bad S5 release "stock=$(stock_of $PID), want 10"
[ "$(payment_status "$OID5")" = "voided" ] \
  && ok S5 void "authorization voided" \
  || bad S5 void "payment=$(payment_status "$OID5"), want voided"

# ---------- S6 worker outage -> durable convergence -------------------------
set_price $PID 14.00; set_stock $PID 10
SID=$(ready_session "$AT" $PID 1)
dc stop order-worker >/dev/null 2>&1
C=$(confirm "$SID" "$AT" "bl-s6-$$")
OID6=$(echo "$C" | jqy "['order_id']")
S=$(order_status "$OID6" "$AT")
[ "$S" = "pending" ] && ok S6 queued "order pending while worker down" \
  || bad S6 queued "status=$S, want pending"
dc start order-worker >/dev/null 2>&1
if wait_order "$OID6" "$AT" confirmed 120; then
  ok S6 heal "worker restart -> converged confirmed"
else
  bad S6 heal "order '$OID6' status=$(order_status "$OID6" "$AT")"
fi

# ---------- S7 capture failure ----------------------------------------------
skip S7 capture "mockpay drives failures from charge amounts only — no capture-failure knob; phase-7 chaos item"

say ""
say "== Summary: $PASS pass, $FAIL fail"
say ""
say "| Scenario | Check | Result | Detail |"
say "|----------|-------|--------|--------|"
printf '%s\n' "${RESULTS[@]}"
exit $((FAIL > 0))
