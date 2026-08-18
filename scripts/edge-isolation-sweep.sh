#!/usr/bin/env bash
# Edge-ingress NetworkPolicy sweep — guards the envoy-gateway allow list.
#
# A missed file is a SILENT traffic blackhole: the route resolves, the pod is
# healthy, and every request times out at the CNI.
#
# Two modes, modeled on db-isolation-sweep.sh:
#   1. manifest mode (always): greps the committed manifests — every
#      edge-reachable namespace must admit ingress from envoy-gateway on its
#      service port, and inventory (gRPC-only, no edge route) must NOT.
#   2. live mode (--live, kubectl context set): probes TCP connectivity from a
#      pod in the envoy-gateway namespace to each backend service port.
#
# Exit 0 iff every check answers as expected.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NP_DIR="$REPO_ROOT/kubernetes/infra/configs/network-policies"
FAIL=0

# namespace:port pairs the edge must reach (matches configs/network-policies/
# and the HTTPRoutes in configs/envoy-gateway/routes/) — update BOTH when a
# service is added.
EDGE_ALLOWS="auth:8080 cart:8080 checkout:8080 notification:8080 order:8080 \
payment:8080 product:8080 review:8080 shipping:8080 user:8080 identity:8080"
# namespace:port pairs the edge must NOT reach (no edge route exists).
EDGE_DENIES="inventory:9090"

pass() { printf "PASS  %s\n" "$1"; }
fail() { printf "FAIL  %s\n" "$1"; FAIL=1; }

manifest_sweep() {
  echo "== manifest mode: committed NetworkPolicies"

  for pair in $EDGE_ALLOWS; do
    ns="${pair%%:*}" port="${pair##*:}" f="$NP_DIR/$ns.yaml"
    if [ ! -f "$f" ]; then
      fail "$ns: $f missing (edge-reachable namespace without a policy file)"
      continue
    fi
    # The allow must name envoy-gateway AND carry the service port in the same
    # file. (Coarse on purpose: yq-free so it runs anywhere; the live mode is
    # the semantic check.)
    if grep -q "kubernetes.io/metadata.name: envoy-gateway" "$f" \
       && grep -qE "port: $port\b" "$f"; then
      pass "$ns admits envoy-gateway on :$port"
    else
      fail "$ns: no envoy-gateway ingress allow on :$port in $f (blackhole risk)"
    fi
  done

  for pair in $EDGE_DENIES; do
    ns="${pair%%:*}" f="$NP_DIR/$ns.yaml"
    if grep -q "kubernetes.io/metadata.name: envoy-gateway" "$f"; then
      fail "$ns: admits envoy-gateway but has no edge route — remove the allow"
    else
      pass "$ns does not admit envoy-gateway (gRPC-only, as designed)"
    fi
  done
}

live_sweep() {
  echo "== live mode: TCP probes from the envoy-gateway namespace"
  local script=""
  for pair in $EDGE_ALLOWS; do
    ns="${pair%%:*}" port="${pair##*:}"
    host="$ns.$ns.svc.cluster.local"
    [ "$ns" = "identity" ] && host="keycloak.identity.svc.cluster.local"
    script+="nc -z -w 3 $host $port >/dev/null 2>&1 && echo \"PROBE $ns $port open\" || echo \"PROBE $ns $port closed\";"
  done
  for pair in $EDGE_DENIES; do
    ns="${pair%%:*}" port="${pair##*:}"
    script+="nc -z -w 3 $ns.$ns.svc.cluster.local $port >/dev/null 2>&1 && echo \"PROBE $ns $port open\" || echo \"PROBE $ns $port closed\";"
  done

  # No pipe into while: a piped while runs in a subshell and FAIL=1 would be
  # lost (same harness-lies trap db-isolation-sweep.sh guards against).
  local out
  out=$(kubectl run edge-isolation-sweep --rm -i --restart=Never -n envoy-gateway \
    --image=busybox:1.37.0 --command -- sh -c "$script" 2>/dev/null)
  while read -r tag ns port verdict; do
    [ "$tag" = "PROBE" ] || continue
    want=open
    case " $EDGE_DENIES " in *" $ns:$port "*) want=closed ;; esac
    if [ "$verdict" = "$want" ]; then
      pass "live: $ns:$port -> $verdict"
    else
      fail "live: $ns:$port -> got=$verdict want=$want"
    fi
  done <<<"$out"
}

manifest_sweep
if [ "${1:-}" = "--live" ]; then
  if kubectl version >/dev/null 2>&1; then
    live_sweep
  else
    fail "--live requested but kubectl cannot reach a cluster"
  fi
fi

echo
if [ "$FAIL" = 0 ]; then echo "EDGE ISOLATION SWEEP: PASS"; else echo "EDGE ISOLATION SWEEP: FAIL"; fi
exit $FAIL
