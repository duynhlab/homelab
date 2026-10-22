#!/usr/bin/env bash
# Dependency-failure drill for analytics-service (RFC-0030 / ADR-069): freeze
# ClickHouse and assert the API fails closed within its query budget -- 503
# ANALYTICS_UNAVAILABLE on the overview and 503 on /ready, both inside 5 s --
# then unfreeze it and assert recovery within 30 s. /health must stay 200: the
# process is alive, its dependency is not.
#
#   GATE=compose scripts/analytics-failure-drill.sh      # row A25 (third part)
#   GATE=kind    scripts/analytics-failure-drill.sh      # row K4.12
#
# compose pauses the `clickhouse` container (connections hang, which is the
# harder case than a refused connection). kind cannot pause a pod, so it points
# the Deployment at a port nothing listens on and restores the env afterwards.
set -euo pipefail
GATE="${GATE:-compose}"
cd "$(dirname "$0")/.."

case "$GATE" in
  compose)
    ANALYTICS_URL="${ANALYTICS_URL:-http://localhost:8080}"
    READY_URL="${READY_URL:-}"   # the edge does not route /ready; set a direct URL to assert it
    token() { (cd local-stack && KC_REALM=duynhlab-staff KC_CLIENT_ID=admin-portal KC_REDIRECT=http://localhost:3009/ USERNAME=duyne PASSWORD='p@ss1234' bash scripts/keycloak-token.sh); }
    break_dep()   { docker compose -f local-stack/compose.yaml pause clickhouse >/dev/null; }
    restore_dep() { docker compose -f local-stack/compose.yaml unpause clickhouse >/dev/null; }
    ;;
  kind)
    ANALYTICS_URL="${ANALYTICS_URL:?set ANALYTICS_URL}"
    READY_URL="${READY_URL:-$ANALYTICS_URL}"
    token() { KC_URL=https://id.duynh.me KC_REALM=duynhlab-staff KC_CLIENT_ID=admin-portal KC_REDIRECT=https://admin.duynh.me/ USERNAME=duyne PASSWORD='p@ss1234' bash local-stack/scripts/keycloak-token.sh; }
    break_dep()   { kubectl -n analytics set env deploy/analytics CLICKHOUSE_ADDR=clickhouse-clickhouse.monitoring.svc.cluster.local:9999 >/dev/null; kubectl -n analytics rollout status deploy/analytics --timeout=120s >/dev/null; }
    restore_dep() { kubectl -n analytics set env deploy/analytics CLICKHOUSE_ADDR=clickhouse-clickhouse.monitoring.svc.cluster.local:9000 >/dev/null; kubectl -n analytics rollout status deploy/analytics --timeout=120s >/dev/null; }
    ;;
  *) echo "GATE must be compose or kind" >&2; exit 2 ;;
esac

TOKEN="$(token)"
URL="$ANALYTICS_URL/analytics/v1/protected/commerce/overview?currency=USD&from=$(date -u -d '7 days ago' +%F)&to=$(date -u +%F)"
timed() { curl -sk -o "$1" -w '%{http_code} %{time_total}' "${@:2}"; }

fail() { echo "FAIL: $*" >&2; restore_dep || true; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

read -r code secs < <(timed "$tmp/base" -H "Authorization: Bearer $TOKEN" "$URL")
echo "baseline: $code in ${secs}s"; [ "$code" = 200 ] || fail "baseline is $code"

break_dep; echo "dependency broken at $(date -u +%T)"
read -r code secs < <(timed "$tmp/down" -H "Authorization: Bearer $TOKEN" "$URL")
echo "overview while down: $code in ${secs}s ($(python3 -c 'import json;print(json.load(open("'"$tmp/down"'")).get("code"))' 2>/dev/null))"
[ "$code" = 503 ] || fail "overview is $code, want 503"
python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1])).get("code")=="ANALYTICS_UNAVAILABLE" else 1)' "$tmp/down" || fail "503 without ANALYTICS_UNAVAILABLE"
awk "BEGIN{exit !($secs <= 5.5)}" || fail "overview took ${secs}s, want <=5 s"
if [ -n "$READY_URL" ]; then
  read -r rcode rsecs < <(timed "$tmp/ready" "$READY_URL/ready")
  read -r hcode _ < <(timed "$tmp/health" "$READY_URL/health")
  echo "/ready $rcode in ${rsecs}s, /health $hcode"
  [ "$rcode" = 503 ] || fail "/ready is $rcode while the dependency is down"
  [ "$hcode" = 200 ] || fail "/health is $hcode, want 200 (liveness is not readiness)"
fi

restore_dep; T1=$(date +%s); echo "dependency restored at $(date -u +%T)"
while :; do
  read -r code secs < <(timed "$tmp/up" -H "Authorization: Bearer $TOKEN" "$URL")
  age=$(( $(date +%s) - T1 )); echo "recovery +${age}s $code"
  [ "$code" = 200 ] && break
  [ "$age" -gt 30 ] && fail "not recovered 30 s after restore"
  sleep 2
done
echo "PASS: 503 ANALYTICS_UNAVAILABLE in ${secs}s while down, 200 again +${age}s after restore"
