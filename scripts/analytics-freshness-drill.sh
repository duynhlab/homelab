#!/usr/bin/env bash
# Freshness drill for analytics-service (RFC-0030 / ADR-069): stop the source
# heartbeats and watch the API move through its three states on the clock the
# contract names -- healthy at age <=120 s, `stale=true` above 120 s, 503
# ANALYTICS_UNAVAILABLE above 300 s -- then restart them and watch it recover.
#
#   GATE=compose scripts/analytics-freshness-drill.sh    # row A25 (second half)
#   GATE=kind    scripts/analytics-freshness-drill.sh    # row K4.12 / K4.13
#
# compose: the heartbeats are the `analytics-heartbeat` container; the API is
# reached through the edge with a staff token minted by scripts/keycloak-token.sh.
# kind: the heartbeats are the fixture Deployment `analytics-heartbeat` in
# `monitoring` (scripts/analytics/serving-fixture.sh); the API is reached
# through ANALYTICS_URL (a port-forward, or the edge once the route exists).
#
# The clock is the heartbeat's own: the last heartbeat may have landed up to
# 30 s before the container stopped, so ages are measured from the response's
# `data_through` (the oldest source timestamp) rather than from the stop. The
# two transitions are sampled every 10 s and the first sample past each
# threshold is what the evidence records. "Exact 120 is healthy, exact 300 is
# stale" is the unit tests' job (fake clock); a wall-clock drill shows >120/>300.
set -euo pipefail
GATE="${GATE:-compose}"
cd "$(dirname "$0")/.."

case "$GATE" in
  compose)
    ANALYTICS_URL="${ANALYTICS_URL:-http://localhost:8080}"
    token() { (cd local-stack && KC_REALM=duynhlab-staff KC_CLIENT_ID=admin-portal KC_REDIRECT=http://localhost:3009/ USERNAME=duyne PASSWORD='p@ss1234' bash scripts/keycloak-token.sh); }
    stop_heartbeat()  { docker compose -f local-stack/compose.yaml stop analytics-heartbeat >/dev/null; }
    start_heartbeat() { docker compose -f local-stack/compose.yaml start analytics-heartbeat >/dev/null; }
    ;;
  kind)
    ANALYTICS_URL="${ANALYTICS_URL:?set ANALYTICS_URL (port-forward or edge)}"
    token() { KC_URL=https://id.duynh.me KC_REALM=duynhlab-staff KC_CLIENT_ID=admin-portal KC_REDIRECT=https://backoffice.duynh.me/ USERNAME=duyne PASSWORD='p@ss1234' bash local-stack/scripts/keycloak-token.sh; }
    stop_heartbeat()  { kubectl -n monitoring scale deploy/analytics-heartbeat --replicas=0 >/dev/null; }
    start_heartbeat() { kubectl -n monitoring scale deploy/analytics-heartbeat --replicas=1 >/dev/null; }
    ;;
  *) echo "GATE must be compose or kind" >&2; exit 2 ;;
esac

TOKEN="$(token)"
URL="$ANALYTICS_URL/analytics/v1/protected/commerce/overview?currency=USD&from=$(date -u -d '7 days ago' +%F)&to=$(date -u +%F)"
probe() { curl -sk -H "Authorization: Bearer $TOKEN" "$URL" -w '\n%{http_code}' ${CURL_EXTRA:-}; }
state() {
  local out code body
  out="$(probe)"; code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [ "$code" = 200 ]; then
    echo "200 stale=$(printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin)["meta"]["stale"])')"
  else
    echo "$code $(printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("code",""))' 2>/dev/null)"
  fi
}

fail() { echo "FAIL: $*" >&2; start_heartbeat || true; exit 1; }

echo "baseline: $(state)"
[ "$(state)" = "200 stale=False" ] || fail "baseline is not healthy"

stop_heartbeat; echo "heartbeats stopped at $(date -u +%T)"
# The last heartbeat's timestamp is the origin of every age below.
T0=$(probe | head -n -1 | python3 -c 'import json,sys,datetime; d=json.load(sys.stdin); t=d["meta"]["data_through"].replace("Z","+00:00"); print(int(datetime.datetime.fromisoformat(t).timestamp()))')
echo "last heartbeat (data_through) at $(date -u -d @"$T0" +%T)"
stale_at=""; unavailable_at=""
while :; do
  sleep 10
  s="$(state)"; age=$(( $(date +%s) - T0 ))
  echo "+${age}s $s"
  if [ -z "$stale_at" ] && [ "$s" = "200 stale=True" ]; then stale_at=$age; fi
  if [ "$s" = "503 ANALYTICS_UNAVAILABLE" ]; then unavailable_at=$age; break; fi
  if [ "$age" -le 120 ] && [ "$s" != "200 stale=False" ]; then fail "left healthy at or before 120 s ($s at +${age}s)"; fi
  if [ "$age" -gt 320 ]; then fail "still not unavailable at +${age}s"; fi
done
[ -n "$stale_at" ] && [ "$stale_at" -gt 120 ] && [ "$stale_at" -le 140 ] || fail "stale transition at +${stale_at:-never}s, want >120 and <=140"
[ "$unavailable_at" -gt 300 ] && [ "$unavailable_at" -le 320 ] || fail "unavailable transition at +${unavailable_at}s, want >300 and <=320"

start_heartbeat; T1=$(date +%s); echo "heartbeats started at $(date -u +%T)"
while :; do
  sleep 5
  s="$(state)"; age=$(( $(date +%s) - T1 ))
  echo "recovery +${age}s $s"
  [ "$s" = "200 stale=False" ] && break
  [ "$age" -gt 60 ] && fail "not healthy 60 s after restart"
done
echo "PASS: stale at +${stale_at}s, unavailable at +${unavailable_at}s, healthy again +${age}s after restart"
