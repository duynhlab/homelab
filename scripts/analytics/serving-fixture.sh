#!/usr/bin/env bash
# Fixture-backed serving layer for analytics-service on Kind (RFC-0030 dark
# launch, G8). CDC is not deployed, so this applies, OUTSIDE Flux, the same
# serving.sql local-stack uses: raw tables in PeerDB's shape, the *_live views
# and representative facts, plus a Deployment that refreshes the three source
# heartbeats every 30 s. Nothing here is a platform resource: remove it with
# `scripts/analytics/serving-fixture.sh down`, and the mirrors phase replaces
# it with real tables.
#
#   scripts/analytics/serving-fixture.sh up [ORDERS]   # default 2000; 500000 ≈ 1M ledger facts (G8.5)
#   scripts/analytics/serving-fixture.sh down
#
# The seed Job runs clickhouse-client against the load-balancer Service as
# `default` (clickhouse-credentials); the views are DEFINER
# analytics_view_owner, which the SQL creates. The CHI already declares
# analytics_reader with its view grants, so the fixture never touches that
# identity.
set -euo pipefail
cd "$(dirname "$0")/../.."
action="${1:-up}"
orders="${2:-2000}"
ns=monitoring

case "$action" in
  up)
    kubectl -n "$ns" create configmap analytics-fixture \
      --from-file=serving.sql=local-stack/analytics/fixture/serving.sql \
      --from-file=heartbeat.sh=local-stack/analytics/fixture/heartbeat.sh \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl -n "$ns" delete job analytics-fixture-seed --ignore-not-found >/dev/null
    sed "s/__ORDERS__/$orders/" scripts/analytics/fixture.yaml | kubectl apply -f - >/dev/null
    echo "seed Job started (orders=$orders); waiting..."
    kubectl -n "$ns" wait --for=condition=complete job/analytics-fixture-seed --timeout=15m
    kubectl -n "$ns" rollout status deploy/analytics-heartbeat --timeout=2m
    echo "fixture up: $(kubectl -n "$ns" exec -i clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --password "$(kubectl -n "$ns" get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)" -q 'SELECT count() FROM analytics.payment_ledger_entries_live') ledger entries visible through the views"
    ;;
  down)
    sed "s/__ORDERS__/0/" scripts/analytics/fixture.yaml | kubectl delete -f - --ignore-not-found >/dev/null
    kubectl -n "$ns" delete configmap analytics-fixture --ignore-not-found >/dev/null
    echo "fixture removed (the analytics database and its tables stay until the next make up)"
    ;;
  *) echo "usage: $0 up [ORDERS] | down" >&2; exit 2 ;;
esac
