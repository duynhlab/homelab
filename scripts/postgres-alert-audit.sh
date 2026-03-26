#!/usr/bin/env bash
set -euo pipefail

echo "=== PostgreSQL Alert Audit ==="
echo

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

echo "[1/5] Flux reconciliation status"
flux get kustomizations -A | rg "monitoring-local|databases-local|controllers-local" || true
echo

echo "[2/5] PostgreSQL PrometheusRule inventory"
kubectl get prometheusrule -A -o json \
  | jq -r '.items[]
    | select(.metadata.name|test("cnpg|zalando|postgres"))
    | [.metadata.namespace,.metadata.name] | @tsv' \
  | sort
echo

echo "[3/5] Duplicate PostgreSQL alert names (should be empty)"
duplicates="$(
  kubectl get prometheusrule -A -o json \
    | jq -r '.items[]
      | select(.metadata.name|test("cnpg|zalando|postgres"))
      | .spec.groups[]?.rules[]?
      | select(.alert!=null)
      | .alert' \
    | sort | uniq -cd || true
)"
if [[ -z "${duplicates}" ]]; then
  echo "OK: no duplicate alert names detected."
else
  echo "${duplicates}"
fi
echo

echo "[4/5] Metric backing quick checks (VictoriaMetrics @ localhost:8428)"
if curl -fsS "http://localhost:8428/health" >/dev/null 2>&1; then
  for q in \
    'count(cnpg_collector_up)' \
    'count(custom_connection_limits_current_connections)' \
    'count(custom_blocking_queries_blocked_queries)' \
    'count(kube_pod_info)' \
    'count(kubelet_volume_stats_available_bytes)'
  do
    printf "query=%s => " "${q}"
    curl -s --get "http://localhost:8428/api/v1/query" --data-urlencode "query=${q}" \
      | jq -r '.data.result[0].value[1] // "0"'
  done
else
  echo "SKIP: VictoriaMetrics is not reachable on localhost:8428."
fi
echo

echo "[5/5] VMAlert runtime rule errors (localhost:18080)"
if curl -fsS "http://localhost:18080/health" >/dev/null 2>&1; then
  err_count="$(
    curl -s "http://localhost:18080/api/v1/rules" \
      | jq '[.data.groups[]?.rules[]? | select((.lastError // "") != "" or .state == "error")] | length'
  )"
  echo "error_rules=${err_count}"
  if [[ "${err_count}" != "0" ]]; then
    curl -s "http://localhost:18080/api/v1/rules" \
      | jq -r '.data.groups[]?.rules[]?
        | select((.lastError // "") != "" or .state == "error")
        | [.group,.name,.state,(.lastError // "")] | @tsv'
  fi
else
  echo "SKIP: VMAlert is not reachable on localhost:18080."
fi

echo
echo "Audit completed."
