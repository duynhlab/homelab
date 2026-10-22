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
# the Deployment at a port nothing listens on. The rollout (maxUnavailable 0)
# never promotes that replacement pod -- its readiness probe answers 503 -- so
# the healthy pod keeps serving the Service; the "down" probes therefore go to
# the broken pod through their own port-forward, and the env is restored
# afterwards.
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
    token() { KC_URL=https://id.duynh.me KC_REALM=duynhlab-staff KC_CLIENT_ID=admin-portal KC_REDIRECT=https://backoffice.duynh.me/ USERNAME=duyne PASSWORD='p@ss1234' bash local-stack/scripts/keycloak-token.sh; }
    DRILL_PORT="${DRILL_PORT:-18099}"; PF=""
    break_dep() {
      kubectl -n analytics set env deploy/analytics CLICKHOUSE_ADDR=clickhouse-clickhouse.monitoring.svc.cluster.local:9999 >/dev/null
      local pod=""
      for _ in $(seq 1 30); do
        pod="$(kubectl -n analytics get pods -l app.kubernetes.io/name=analytics --field-selector=status.phase=Running \
          -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].ready}{"\n"}{end}' | awk '$2=="false"{print $1; exit}')"
        [ -n "$pod" ] && break; sleep 2
      done
      [ -n "$pod" ] || { echo "no replacement pod appeared" >&2; return 1; }
      kubectl -n analytics port-forward "pod/$pod" "$DRILL_PORT:8080" >/dev/null 2>&1 & PF=$!; sleep 2
      echo "replacement pod $pod (never Ready) probed on :$DRILL_PORT"
      DOWN_URL="http://127.0.0.1:$DRILL_PORT"
    }
    restore_dep() {
      [ -n "$PF" ] && { kill "$PF" 2>/dev/null || true; PF=""; }
      kubectl -n analytics set env deploy/analytics CLICKHOUSE_ADDR=clickhouse-clickhouse.monitoring.svc.cluster.local:9000 >/dev/null
      kubectl -n analytics rollout status deploy/analytics --timeout=120s >/dev/null
    }
    ;;
  *) echo "GATE must be compose or kind" >&2; exit 2 ;;
esac

TOKEN="$(token)"
PATHQ="/analytics/v1/protected/commerce/overview?currency=USD&from=$(date -u -d '7 days ago' +%F)&to=$(date -u +%F)"
URL="$ANALYTICS_URL$PATHQ"
DOWN_URL=""   # kind: the broken pod's own port-forward; compose: the same URL
timed() { curl -sk -o "$1" -w '%{http_code} %{time_total}\n' "${@:2}"; }

fail() { echo "FAIL: $*" >&2; restore_dep || true; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

read -r code secs < <(timed "$tmp/base" -H "Authorization: Bearer $TOKEN" "$URL")
echo "baseline: $code in ${secs}s"; [ "$code" = 200 ] || fail "baseline is $code"

break_dep; echo "dependency broken at $(date -u +%T)"
down_base="${DOWN_URL:-$ANALYTICS_URL}"; down_ready="${DOWN_URL:-$READY_URL}"
read -r code secs < <(timed "$tmp/down" -H "Authorization: Bearer $TOKEN" "$down_base$PATHQ")
echo "overview while down: $code in ${secs}s ($(python3 -c 'import json;print(json.load(open("'"$tmp/down"'")).get("code"))' 2>/dev/null))"
[ "$code" = 503 ] || fail "overview is $code, want 503"
python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1])).get("code")=="ANALYTICS_UNAVAILABLE" else 1)' "$tmp/down" || fail "503 without ANALYTICS_UNAVAILABLE"
awk "BEGIN{exit !($secs <= 5.5)}" || fail "overview took ${secs}s, want <=5 s"
down_secs="$secs"
if [ -n "$down_ready" ]; then
  read -r rcode rsecs < <(timed "$tmp/ready" "$down_ready/ready")
  read -r hcode _ < <(timed "$tmp/health" "$down_ready/health")
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
echo "PASS: 503 ANALYTICS_UNAVAILABLE in ${down_secs}s while down, 200 again +${age}s after restore"
