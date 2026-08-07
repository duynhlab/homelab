# E2E release audit

This runbook is the mandatory pre-release gate for code exercised by
[local-stack](../README.md). Run it against the exact source commits intended
for release; every Phase A, B, and C row must pass before a tag is created.

| Attribute | Value |
|-----------|-------|
| **Applies to** | Service, `pkg`, frontend, Kong/gateway, and Compose changes |
| **Execution** | Full audit every time; phases are not selectively skipped |
| **Evidence** | Candidate commit SHAs plus the completed pass/fail table |
| **Pass decision** | `ELIGIBLE FOR TAG` only when every required row passes |
| **Failure decision** | `BLOCKED`; fix, rebuild, reset ambiguous state, and rerun the full audit |

## Preconditions

1. Check out every candidate repository at the commit intended for the tag.
2. Start the stack from `homelab/local-stack` with
   `docker compose up -d --build`.
3. Confirm Compose renders and the runtime is ready:

   ```bash
   docker compose config --quiet
   docker compose ps --all
   ```

4. Verify all long-running application dependencies are running or healthy.
   Every migrate and seed job must have exited successfully. Investigate any
   `unhealthy`, restarting, or non-zero exited container before continuing.
5. Install and load the browser automation guidance before Phase B:

   ```bash
   agent-browser skills get core
   ```

6. Record the candidate commit set:

   ```bash
   for repo in ../../*-service ../../frontend ../../pkg; do
     printf '%-32s ' "$(basename "$repo")"
     git -C "$repo" rev-parse HEAD
   done
   ```

The stack builds directly from these sibling worktrees. Uncommitted files are
part of the build but cannot be represented by a release tag; the final audit
therefore requires clean candidate worktrees. Pace bulk API requests at least
0.25 seconds apart because the local Kong rate limit is 5 requests per second.

## Phase A — API contract (curl, ~1 min)

```bash
BASE=http://localhost:8080

# Keep the executable block below Kong's 5 req/s global limit.
audit_curl() {
  curl "$@"
  sleep 0.3
}

# A1. Login returns the JWT pair — and NO opaque `token` field
R=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}')
echo "$R" | python3 -c "import json,sys; d=json.load(sys.stdin); \
  assert 'token' not in d, 'opaque token leaked'; \
  assert d['access_token'].count('.')==2 and d['refresh_token'] and d['expires_in']; \
  print('A1 OK', sorted(d.keys()))"
AT=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
RT=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin)['refresh_token'])")

# A2. Private routes 200 through Kong edge-jwt with a valid JWT
for p in user/v1/private/users/profile cart/v1/private/cart order/v1/private/orders \
         notification/v1/private/notifications; do
  [ "$(audit_curl -s -o /dev/null -w '%{http_code}' $BASE/$p -H "Authorization: Bearer $AT")" = 200 ] \
    && echo "A2 OK /$p" || echo "A2 FAIL /$p"
done

# A3. Bad / missing token → 401 at the Kong edge (WWW-Authenticate header)
audit_curl -s -o /dev/null -w "A3 bad-token: %{http_code} (want 401)\n" \
  $BASE/cart/v1/private/cart -H "Authorization: Bearer x.y.z"
audit_curl -s -o /dev/null -w "A3 no-token:  %{http_code} (want 401)\n" $BASE/cart/v1/private/cart

# A4. Refresh rotates; replaying the OLD token → 401 AND revokes the family
R2=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/refresh -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$RT\"}")
RT2=$(echo "$R2" | python3 -c "import json,sys;print(json.load(sys.stdin)['refresh_token'])")
audit_curl -s -o /dev/null -w "A4 replay-old:      %{http_code} (want 401)\n" \
  -X POST $BASE/auth/v1/public/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$RT\"}"
audit_curl -s -o /dev/null -w "A4 family-revoked:  %{http_code} (want 401)\n" \
  -X POST $BASE/auth/v1/public/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$RT2\"}"

# A5. Logout revokes; idempotent; subsequent refresh dies
R3=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}')
RT3=$(echo "$R3" | python3 -c "import json,sys;print(json.load(sys.stdin)['refresh_token'])")
audit_curl -s -o /dev/null -w "A5 logout:          %{http_code} (want 200)\n" \
  -X POST $BASE/auth/v1/public/auth/logout -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$RT3\"}"
audit_curl -s -o /dev/null -w "A5 refresh-after:   %{http_code} (want 401)\n" \
  -X POST $BASE/auth/v1/public/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$RT3\"}"

# A6. Removed surfaces stay removed
audit_curl -s -o /dev/null -w "A6 /private/me:     %{http_code} (want 404 — route gone at Kong)\n" \
  $BASE/auth/v1/private/me -H "Authorization: Bearer $AT"
docker compose exec -T postgres psql -U postgres -d auth -c '\dt' </dev/null | grep -q sessions \
  && echo "A6 FAIL: sessions table exists" || echo "A6 OK: no sessions table"

# A7. v3 collection-noun paths (ADR-017): new canonical 200 + deprecated
#     aliases still answering during the expand phase (removed at contract)
audit_curl -s -o /dev/null -w "A7 shipments/track:     %{http_code} (want 200)\n" \
  "$BASE/shipping/v1/public/shipments/track?tracking_number=1Z999AA10123456784"
audit_curl -s -o /dev/null -w "A7 shipments/estimate:  %{http_code} (want 200)\n" \
  "$BASE/shipping/v1/public/shipments/estimate?origin=HN&destination=SG&weight=1"
audit_curl -s -o /dev/null -w "A7 alias track:         %{http_code} (want 200 — deprecated)\n" \
  "$BASE/shipping/v1/public/track?tracking_number=1Z999AA10123456784"
audit_curl -s -o /dev/null -w "A7 alias login:         %{http_code} (want 200 — deprecated)\n" \
  -X POST $BASE/auth/v1/public/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}'

# A8. Renamed zero-caller internal paths are gone (no aliases kept):
#     these are cluster-internal, so probe the service containers directly.
docker compose exec -T notification wget -q -O /dev/null -S \
  --post-data '{}' --header 'Content-Type: application/json' \
  http://localhost:8080/notification/v1/internal/notify/email </dev/null 2>&1 | head -1
# want: HTTP/1.1 404 (the /notifications/{email,sms} paths replaced notify/*)
docker compose exec -T shipping wget -q -O /dev/null -S \
  http://localhost:8080/shipping/v1/internal/orders/1 </dev/null 2>&1 | head -1
# want: HTTP/1.1 404 (now /shipping/v1/internal/shipments/orders/:orderId)

# A9. Checkout sessions (RFC-0015 P1) — lifecycle through Kong edge-JWT.
#     Cart must have at least one item (add via the SPA or cart API first).
AT9=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}' | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
audit_curl -s -X POST $BASE/cart/v1/private/cart -H "Authorization: Bearer $AT9" \
  -H 'Content-Type: application/json' \
  -d '{"product_id":"1","product_name":"Wireless Mouse","product_price":29.99,"quantity":1}' -o /dev/null
S9=$(audit_curl -s -X POST $BASE/checkout/v1/private/checkout/sessions -H "Authorization: Bearer $AT9")
SID=$(echo "$S9" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
echo "A9 create:   session $SID ($(echo "$S9" | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])"))"
audit_curl -s -o /dev/null -w "A9 re-create: %{http_code} (want 200 — idempotent, same session)\n" \
  -X POST $BASE/checkout/v1/private/checkout/sessions -H "Authorization: Bearer $AT9"
audit_curl -s -o /dev/null -w "A9 get:       %{http_code} (want 200)\n" \
  $BASE/checkout/v1/private/checkout/sessions/$SID -H "Authorization: Bearer $AT9"
audit_curl -s -o /dev/null -w "A9 address:   %{http_code} (want 200 → address_set)\n" \
  -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/address -H "Authorization: Bearer $AT9" \
  -H 'Content-Type: application/json' \
  -d '{"full_name":"Alice","line1":"1 Main St","city":"HN","country":"VN"}'
audit_curl -s -o /dev/null -w "A9 cancel:    %{http_code} (want 200)\n" \
  -X DELETE $BASE/checkout/v1/private/checkout/sessions/$SID -H "Authorization: Bearer $AT9"
audit_curl -s -o /dev/null -w "A9 no-token:  %{http_code} (want 401 at the edge)\n" \
  -X POST $BASE/checkout/v1/private/checkout/sessions
audit_curl -s -o /dev/null -w "A9 old path:  %{http_code} (want 404 — /api/v1/checkout removed)\n" \
  -X POST $BASE/api/v1/checkout
# Price-change detection (the RFC-0015 P1 exit criterion): bump a catalog
# price, create a fresh session, expect the line flagged.
docker compose exec -T postgres psql -U postgres -d product -c \
  "UPDATE products SET price = price + 1 WHERE id = 1" </dev/null >/dev/null
S9_PRICE=$(audit_curl -s -X POST $BASE/checkout/v1/private/checkout/sessions -H "Authorization: Bearer $AT9")
echo "$S9_PRICE" | python3 -c "import json,sys; s=json.load(sys.stdin); \
  print('A9 price-change:', 'OK' if any(i['price_changed'] for i in s['items']) else 'FAIL', \
  [ (i['product_id'], i['price_changed'], i['unit_price']) for i in s['items'] ]); \
  raise SystemExit(0 if any(i['price_changed'] for i in s['items']) else 1)"
SID9_PRICE=$(echo "$S9_PRICE" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
docker compose exec -T postgres psql -U postgres -d product -c \
  "UPDATE products SET price = price - 1 WHERE id = 1" </dev/null >/dev/null
# The price-change probe populated product:1 with the temporary value. Remove
# both test artifacts so A10 starts with a new session and revalidates against
# the restored catalog price.
docker compose exec -T cache valkey-cli DEL product:1 </dev/null >/dev/null
audit_curl -s -o /dev/null -w "A9 price-session cleanup: %{http_code} (want 200)\n" \
  -X DELETE $BASE/checkout/v1/private/checkout/sessions/$SID9_PRICE -H "Authorization: Bearer $AT9"

# A10. Confirm handoff + abandonment (RFC-0015 P2). Full lifecycle: fresh
#      session → address → shipping → payment → confirm (Idempotency-Key
#      REQUIRED) → order created + fulfillment saga → replay = same order.
AT0=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}' | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
audit_curl -s -X POST $BASE/cart/v1/private/cart -H "Authorization: Bearer $AT0" \
  -H 'Content-Type: application/json' \
  -d '{"product_id":"1","product_name":"Wireless Mouse","product_price":29.99,"quantity":1}' -o /dev/null
S=$(audit_curl -s -X POST $BASE/checkout/v1/private/checkout/sessions -H "Authorization: Bearer $AT0")
SID=$(echo "$S" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
audit_curl -s -o /dev/null -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/address \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"full_name":"Alice","line1":"1 Main St","city":"HN","country":"VN"}'
# P3: the fee is quoted by shipping (standard/VN = $3.00) and the flat tax
# (tax_rules: VN 8%) applies on subtotal + fee — assert the composition.
audit_curl -s -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/shipping \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"shipping_method":"standard"}' | python3 -c "import json,sys; s=json.load(sys.stdin); \
  ok = s['shipping_fee']==3.0 and abs(s['tax']-round((s['subtotal']+3.0)*0.08,2))<0.011 \
       and abs(s['total']-(s['subtotal']+s['shipping_fee']+s['tax']))<0.001; \
  print('A10 shipping:', 'OK' if ok else 'FAIL', \
        f\"fee={s['shipping_fee']} tax={s['tax']} total={s['total']} ({s['status']})\")"
audit_curl -s -o /dev/null -w "A10 bad-method: %{http_code} (want 400 — unknown quote input)\n" \
  -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/shipping \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"shipping_method":"drone"}'
audit_curl -s -o /dev/null -w "A10 payment:  %{http_code} (want 200 → ready)\n" \
  -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/payment \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"payment_method_token":"tok_visa_ok"}'
audit_curl -s -o /dev/null -w "A10 PAN reject: %{http_code} (want 400 — tok_ only, never persisted)\n" \
  -X PUT $BASE/checkout/v1/private/checkout/sessions/$SID/payment \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"payment_method_token":"tok_4111111111111111"}'
audit_curl -s -o /dev/null -w "A10 no-key:   %{http_code} (want 400 IDEMPOTENCY_KEY_REQUIRED)\n" \
  -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/confirm -H "Authorization: Bearer $AT0"
# P4: apply a promo (validated preview — never counts a use) and assert the
# discount line + that the ORDER total equals the SESSION total (the saga
# charges order.Total, so they must be the same number).
audit_curl -s -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/promo \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' \
  -d '{"code":"WELCOME10"}' | python3 -c "import json,sys; s=json.load(sys.stdin); \
  ok = s['promo_code']=='WELCOME10' and abs(s['discount']-round(s['subtotal']*0.10,2))<0.011 \
       and abs(s['total']-(s['subtotal']+s['shipping_fee']+s['tax']-s['discount']))<0.001; \
  print('A10 promo:', 'OK' if ok else 'FAIL', f\"discount={s['discount']} total={s['total']}\")"
audit_curl -s -o /dev/null -w "A10 promo-bad:  %{http_code} (want 404 PROMO_INVALID)\n" \
  -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/promo \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' -d '{"code":"NOPE"}'
audit_curl -s -o /dev/null -w "A10 promo-exp:  %{http_code} (want 409 PROMO_EXPIRED)\n" \
  -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/promo \
  -H "Authorization: Bearer $AT0" -H 'Content-Type: application/json' -d '{"code":"EXPIRED1"}'
KEY="a10-$(date +%s)"
C_RAW=$(audit_curl -s -w '\n%{http_code}' -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/confirm \
  -H "Authorization: Bearer $AT0" -H "Idempotency-Key: $KEY")
C_CODE=${C_RAW##*$'\n'}
C=${C_RAW%$'\n'*}
[ "$C_CODE" = 201 ] || { echo "A10 confirm: FAIL HTTP $C_CODE — $C"; exit 1; }
OID=$(echo "$C" | python3 -c "import json,sys;print(json.load(sys.stdin).get('order_id',''))")
echo "$C" | python3 -c "import json,sys; c=json.load(sys.stdin); \
  assert c.get('order_id'), 'missing order_id'; assert c.get('status')=='completed', c; \
  print('A10 confirm:  order', c['order_id'], '(completed)')"
# Replay with the SAME key → the SAME order, no second saga.
C2_RAW=$(audit_curl -s -w '\n%{http_code}' -X POST $BASE/checkout/v1/private/checkout/sessions/$SID/confirm \
  -H "Authorization: Bearer $AT0" -H "Idempotency-Key: $KEY")
C2_CODE=${C2_RAW##*$'\n'}
C2=${C2_RAW%$'\n'*}
[ "$C2_CODE" = 201 ] || { echo "A10 replay: FAIL HTTP $C2_CODE — $C2"; exit 1; }
[ "$(echo "$C2" | python3 -c "import json,sys;print(json.load(sys.stdin).get('order_id',''))")" = "$OID" ] \
  && echo "A10 replay:   OK same order $OID" || { echo "A10 replay: FAIL different order"; exit 1; }
# The order exists, its saga ran, AND its total equals the session total
# (fee + tax + discount crossed the boundary — the P3 demo-fee gap is closed).
sleep 5
STOTAL=$(echo "$C" | python3 -c "import json,sys;print(json.load(sys.stdin)['total'])")
audit_curl -s $BASE/order/v1/private/orders/$OID -H "Authorization: Bearer $AT0" | \
  python3 -c "import json,sys; o=json.load(sys.stdin); \
  ok=o['status'] in {'confirmed','completed'} and abs(float(o['total'])-float('$STOTAL'))<0.001; \
  print('A10 order:', 'OK' if ok else 'FAIL', o['id'], o['status'], f\"total={o['total']}\"); \
  raise SystemExit(0 if ok else 1)"
# One redemption exactly, order_id backfilled:
docker compose exec -T postgres psql -U postgres -d checkout -t -c \
  "SELECT code, order_id IS NOT NULL AS used FROM promo_redemptions ORDER BY id DESC LIMIT 1" </dev/null
docker compose exec -T temporal temporal workflow list --namespace mop -q "WorkflowId = 'order-fulfillment-$OID'" </dev/null 2>/dev/null | head -3

# Abandonment (ADR-019): the DB deadline is the authority; the workflow timer
# makes expiry proactive. Shorten the DB deadline and verify the outcome.
AT1=$(audit_curl -s -X POST $BASE/auth/v1/public/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}' | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
audit_curl -s -X POST $BASE/cart/v1/private/cart -H "Authorization: Bearer $AT1" -H 'Content-Type: application/json' \
  -d '{"product_id":"2","product_name":"USB Hub","product_price":79.99,"quantity":1}' -o /dev/null
SID2=$(audit_curl -s -X POST $BASE/checkout/v1/private/checkout/sessions -H "Authorization: Bearer $AT1" | \
  python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
docker compose exec -T postgres psql -U postgres -d checkout -c \
  "UPDATE checkout_sessions SET expires_at = now() + interval '5 seconds' WHERE id = '$SID2'" </dev/null >/dev/null
sleep 8
# Any read past the DB deadline answers 410 — the lazy backstop, worker or not:
audit_curl -s -o /dev/null -w "A10 lazy-410: %{http_code} (want 410 once past expires_at)\n" \
  $BASE/checkout/v1/private/checkout/sessions/$SID2 -H "Authorization: Bearer $AT1"
docker compose exec -T postgres psql -U postgres -d checkout -t -c \
  "SELECT status, expired_reason FROM checkout_sessions WHERE id = '$SID2'" </dev/null
# want: expired | lazy (the read got there first) or timer (the worker did)

# A11. Exercise the product-details fan-out so the full audit covers product,
#      inventory, and review before trace coverage is evaluated in C5.
audit_curl -s "$BASE/product/v1/public/products/1/details" | python3 -c "import json,sys; d=json.load(sys.stdin); \
  p=d.get('product') or {}; a=d.get('availability') or {}; reviews=d.get('reviews'); summary=d.get('reviews_summary') or {}; \
  ok=p.get('id')=='1' and a.get('available_to_promise') is not None and isinstance(reviews,list) and len(reviews)>0 and summary.get('total')==len(reviews); \
  print('A11 details:', 'OK full fan-out response' if ok else 'FAIL incomplete inventory/review enrichment'); \
  raise SystemExit(0 if ok else 1)"

```

> Rapid-fire auth calls can trip Kong's rate limit (429). That is the gateway
> working, not a bug — wait a few seconds and retry the step.
>
> A10 abandonment timing: the workflow timer arms for the session's FULL TTL
> (default 30m) at creation; shortening `expires_at` in SQL afterwards only
> moves the LAZY deadline. To watch the timer itself fire quickly, run the
> stack with `SESSION_TTL_SECONDS=15` on `checkout` + `checkout-worker`
> instead, then create a session and leave it untouched — it flips to
> `expired(timer)` in ~15s while the SPA shows 410 on reload.

## Phase B — real browser (agent-browser, ~2 min)

`--args "--no-sandbox"` is required on Linux hosts with user-namespace
restrictions (only needed on the first command of a session).

```bash
S="--session audit"

# B1. Login through the UI, then verify what landed in localStorage
agent-browser $S --args "--no-sandbox" batch "open http://localhost:3001/login" "wait 1500" "snapshot -i"
# read the refs from the snapshot (username @eX, password @eY, Login button @eZ), then:
agent-browser $S batch "fill @e8 alice" "fill @e9 password123" "click @e10" "wait 2000"
agent-browser $S eval --stdin <<'EVALEOF'
JSON.stringify({
  access_is_jwt: (localStorage.getItem('authToken')||'').split('.').length === 3,
  refresh_present: !!localStorage.getItem('authRefreshToken'),
  user: JSON.parse(localStorage.getItem('authUser')||'null')?.username
})
EVALEOF
# want: {"access_is_jwt":true,"refresh_present":true,"user":"alice"}

# B2. SILENT REFRESH under fault injection — corrupt the JWT signature, then
#     load a private page. The interceptor must refresh + retry, not bounce to /login.
agent-browser $S eval --stdin <<'EVALEOF'
(() => { const p = localStorage.getItem('authToken').split('.');
  p[2] = p[2].slice(0,-5) + 'AAAAA'; localStorage.setItem('authToken', p.join('.'));
  return 'token corrupted'; })()
EVALEOF
agent-browser $S batch "open http://localhost:3001/orders" "wait 3000"
agent-browser $S eval --stdin <<'EVALEOF'
JSON.stringify({
  token_recovered: !(localStorage.getItem('authToken')||'').endsWith('AAAAA'),
  bounced_to_login: window.location.pathname.includes('login')
})
EVALEOF
# want: {"token_recovered":true,"bounced_to_login":false}
agent-browser $S network requests --type xhr,fetch | grep -E "refresh|401|200" | tail -8
# want this exact shape (single-flight: N concurrent 401s -> ONE refresh -> retries 200):
#   GET  .../private/...              401
#   GET  .../private/...              401
#   POST /auth/v1/public/auth/refresh      200      <-- exactly one
#   GET  .../private/...              200
#   GET  .../private/...              200

# B3. Logout via the UI revokes server-side and clears the client
agent-browser $S snapshot -i          # find the Logout button ref
agent-browser $S batch "click @e13" "wait 2000"
agent-browser $S eval 'JSON.stringify({cleared: !localStorage.getItem("authToken") && !localStorage.getItem("authRefreshToken"), path: location.pathname})'
agent-browser $S network requests --method POST | grep logout   # want: .../public/auth/logout ... 200

# B4. Cleanup
agent-browser $S close
```

## Phase C — telemetry sanity (curl + PromQL, ~2 min)

The stack ships the full RFC-0014/0017 telemetry pipeline; a change can pass
A+B and still silently break it. Counters lag the flow by **~30–45s**
(15s OTLP export + async saga) — always wait before reading.

```bash
VM=http://localhost:8428

# C1. Pipeline health — the collector must not be dropping data
#     (compose service name — there is no `otel-collector` container_name)
docker compose logs --since 10m otel-collector 2>&1 \
  | grep -ciE 'export.*fail|"level":"error"|\terror\t' \
  | xargs -I{} sh -c '[ {} -eq 0 ] && echo "C1 OK collector clean" || echo "C1 FAIL: {} error lines"'

# C2. Business counters move with the flow (run a checkout first, wait 45s):
#     the three ends of the saga must agree — confirmed = saga = authorized.
for m in checkout_sessions_confirmed_total 'order_saga_outcome_total{outcome="confirmed"}' \
         'payment_authorization_total{result="authorized"}'; do
  curl -s "$VM/api/v1/query" --data-urlencode "query=sum($m)" \
    | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; \
      print('C2', '$m'.split('{')[0], '=', r[0]['value'][1] if r else 'NO SERIES')"
done

# C3. DB client telemetry sane (RFC-0017 W4 — needs pkg >= v0.24.0 in the
#     services): query p95 must be a real number, not bucket-collapse garbage.
curl -s "$VM/api/v1/query" --data-urlencode \
  'query=histogram_quantile(0.95, sum by (le) (rate(db_client_operation_duration_seconds_bucket{pgx_operation_type="query"}[5m])))' \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; \
    v=float(r[0]['value'][1]) if r else None; \
    print('C3 DB p95:', 'OK %.2fms' % (v*1000) if v and v < 0.5 else f'FAIL {v} (collapsed buckets? old pkg?)')"

# C4. Main + ClickHouse-suite dashboards load with no datasource/parse errors
for d in microservices-otel-local business-otel-local \
         clickhouse-otel-sql clickhouse-service-deepdive \
         clickhouse-otel-overview clickhouse-logs-explorer clickhouse-traces-explorer; do
  curl -s -o /dev/null -w "C4 $d: %{http_code} (want 200)\n" \
    http://localhost:3002/api/dashboards/uid/$d
done

# C5. Trace coverage is present for every application service.
curl -s 'http://localhost:10428/select/jaeger/api/services' | python3 -c \
  "import json,sys; actual=set(json.load(sys.stdin)['data']); \
  required={'auth','user','product','inventory','cart','order','review','shipping','notification','payment','checkout'}; \
  missing=sorted(required-actual); print('C5 traced services:', 'OK' if not missing else 'FAIL', \
  'missing='+','.join(missing) if missing else 'all 11 present'); raise SystemExit(1 if missing else 0)"

# C6. ClickHouse (RFC-0019 Phase B) ingested OTLP logs+traces for the flow.
#     otel_logs/otel_traces are auto-created by the collector's clickhouse exporter.
#     Respect the same ~30-45s ingest lag before reading.
for t in otel_traces otel_logs; do
  N=$(curl -s 'http://localhost:8123/' -u default:otel --data-binary "SELECT count() FROM otel.$t" 2>/dev/null | tr -d '[:space:]')
  { [ -n "$N" ] && [ "$N" -gt 0 ] 2>/dev/null && echo "C6 $t: $N rows OK"; } \
    || echo "C6 $t: ${N:-0} rows FAIL (ingest lag? exporter/plugin?)"
done
```

> A brand-new counter has **no series until its first increment** — "NO SERIES"
> for an error/discrepancy counter on a healthy stack is correct, not a failure.
> When a change alters histogram **buckets**, old- and new-grid series coexist
> in one rate window for a few minutes and quantiles read garbage until the old
> grid ages out (~4–5 min) — re-check before declaring failure.

## Pass criteria

| # | Check | Expectation |
|---|-------|-------------|
| A1 | Login payload | `access_token` (JWT) + `refresh_token` + `expires_in`; **no `token`** |
| A2 | Private routes w/ JWT | 200 through Kong edge-jwt |
| A3 | Bad/missing token | 401 **at the edge** (`WWW-Authenticate` from Kong) |
| A4 | Refresh reuse | old token 401 **and** whole family revoked |
| A5 | Logout | 200, idempotent; refresh afterwards 401 |
| A6 | Removed surfaces | `/auth/v1/private/*` 404; no `sessions` table |
| A7 | v3 paths (ADR-017) | new `shipments/*` + `auth/*` paths 200; deprecated aliases still 200 (expand phase) |
| A8 | Renamed internal paths | old `notify/*` + `internal/orders/*` 404 in-container (no aliases) |
| A9 | Checkout sessions (RFC-0015) | lifecycle 201→200→200→200 through edge-JWT; no-token 401; `/api/v1/checkout` 404; price bump flags `price_changed` |
| A10 | Confirm + abandonment (RFC-0015 P2–P4) | fee/tax/promo composition asserted; `Idempotency-Key` required; replay = same order; order reaches `confirmed` or `completed`; order total == session total; lazy-410 past `expires_at` |
| A11 | Full-fleet fan-out | product details returns product, live inventory availability, reviews, and review summary |
| B1 | UI login | JWT + refresh in localStorage |
| B2 | Silent refresh | exactly **one** `POST /refresh` for concurrent 401s; retried 200s; no login bounce |
| B3 | UI logout | `POST /public/auth/logout` 200; storage cleared; redirect to `/login` |
| C1 | Collector | 0 export failures / error lines |
| C2 | Business counters | confirmed = saga = authorized, incremented by the driven flow (after ~45s) |
| C3 | DB client p95 | real ms-scale value (< 500ms), not bucket-collapse garbage |
| C4 | Dashboards | every listed dashboard loads via `/api/dashboards/uid/…` with 200 |
| C5 | Traces | all 11 application service names are present in the Jaeger services list |
| C6 | ClickHouse (RFC-0019) | `otel.otel_traces` and `otel.otel_logs` non-empty after the driven flow (SQL over `:8123`) |

Any failed row blocks the release tag. When a change touches the order-fulfillment
path, additionally run the saga (checkout in the SPA) and watch it complete in
the Temporal UI.

## Release evidence

Copy this block into the service PR or release record and replace every pending
value. Preserve the candidate SHA list with the audit result.

```markdown
### local-stack pre-release evidence

- Candidate repository/tag:
- Candidate commit:
- Supporting repository SHAs:
- Executed at:
- Stack reset before audit: yes / no

| Phase | Checks | Result | Evidence / failure |
|-------|--------|--------|--------------------|
| A | A1–A11 API contract | PASS / FAIL | |
| B | B1–B3 real browser | PASS / FAIL | |
| C | C1–C6 telemetry | PASS / FAIL | |

Decision: ELIGIBLE FOR TAG / BLOCKED
```

The decision is `BLOCKED` when any row fails, evidence is missing, a candidate
worktree is dirty, or the commit to tag differs from the recorded commit. After
a passing decision, continue with the
[semver-to-Kind handoff](../README.md#promote-a-passing-candidate-to-kind).

## Failure and cleanup

- Treat HTTP 429 as an audit pacing error: wait, then restart the affected phase
  from a clean authentication state.
- Treat telemetry lag as pending, not passing. Wait for the documented export
  window and rerun the query.
- Use `docker compose logs --since 10m <service>` to localize failures.
- Use `docker compose down -v` before the next full run when database state or
  cumulative telemetry makes the result ambiguous.
- Always close the named `agent-browser` session, including after a failed
  browser phase.

## References

- [local-stack overview](../README.md)
- [Canonical API contracts](../../docs/api/README.md)
- [Application delivery](../../docs/platform/application-delivery.md)
- [Agent workflow](../../AGENTS.md#engineering-skills-workflow)

_Last updated: 2026-08-07 — mandatory full A/B/C release gate, A11 full-fleet
fan-out, explicit evidence and tag eligibility decision._
