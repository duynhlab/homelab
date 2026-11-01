#!/usr/bin/env bash
# Derive the alert catalog's counts from what Flux actually applies (#1384).
# Renders the prometheusrules tree and the Temporal rule with kustomize, so a
# rule file left out of a kustomization (gated or replaced) is not counted.
# Prints alert rules per PrometheusRule object and the totals, then fails when
# a deployed alert name has no row in docs/observability/alerting/alert-catalog.md.
set -euo pipefail

cd "$(dirname "$0")/.."
RULES=kubernetes/infra/configs/observability/metrics/prometheusrules
CATALOG=docs/observability/alerting/alert-catalog.md

render() {
  { kubectl kustomize "$RULES"; echo '---'; kubectl kustomize kubernetes/infra/configs/temporal; } |
    yq -N 'select(.kind == "PrometheusRule") | .metadata.name as $n
      | .spec.groups[].rules[] | select(.alert) | $n + " " + .alert'
}

deployed=$(render)

echo "$deployed" | awk '{print $1}' | sort | uniq -c | sort -k2
main=$(echo "$deployed" | grep -vc '^temporal-alerts ' || true)
temporal=$(echo "$deployed" | grep -c '^temporal-alerts ' || true)
echo "main tree: $main  temporal: $temporal  total: $((main + temporal))"

missing=0
for name in $(echo "$deployed" | awk '{print $2}' | sort -u); do
  if ! grep -qE "^\| (\*\*)?\`?${name}\b" "$CATALOG"; then
    echo "MISSING catalog row: $name"
    missing=1
  fi
done
exit "$missing"
