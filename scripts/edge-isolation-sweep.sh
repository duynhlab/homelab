#!/usr/bin/env bash
# Edge-ingress NetworkPolicy sweep — guards the envoy-gateway allow list.
#
# A missed file is a SILENT traffic blackhole: the route resolves, the pod is
# healthy, and every request times out at the CNI.
#
# Two modes, modeled on db-isolation-sweep.sh:
#   1. manifest mode (always): greps the committed manifests — every
#      edge-reachable namespace must admit ingress from envoy-gateway on its
#      service port, and no namespace may admit the edge on a port without an
#      edge route (inventory: :8080 is edge-routed since RFC-0023, :9090 gRPC
#      must stay closed to the edge).
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
EDGE_ALLOWS="cart:8080 checkout:8080 inventory:8080 notification:8080 order:8080 \
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
    ns="${pair%%:*}" port="${pair##*:}" f="$NP_DIR/$ns.yaml"
    # Port-aware: a namespace may legitimately admit the edge on another port
    # (inventory :8080, RFC-0023) — only an envoy-gateway allow carrying the
    # denied port in the SAME policy document is a violation.
    if awk -v RS='---' -v pat="port: $port" \
        '/kubernetes.io\/metadata.name: envoy-gateway/ && $0 ~ pat {found=1} END{exit !found}' "$f"; then
      fail "$ns: admits envoy-gateway on :$port but no edge route exists — remove the allow"
    else
      pass "$ns does not admit envoy-gateway on :$port (not edge-exposed, as designed)"
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

  # Read the pod's LOGS rather than attaching. `kubectl run -i` streams over an
  # attach, and an attach loses output when the container writes a burst and then
  # exits — measured in db-isolation-sweep.sh, where it silently dropped one
  # verdict per run. No pipe into while either: a piped while runs in a subshell
  # and FAIL=1 would be lost.
  local out pod="edge-isolation-sweep-$$" probes=0 expected=0
  for pair in $EDGE_ALLOWS $EDGE_DENIES; do expected=$((expected + 1)); done
  kubectl run "$pod" --restart=Never -n envoy-gateway \
    --image=busybox:1.37.0 --command -- sh -c "$script" >/dev/null 2>&1
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$pod" -n envoy-gateway --timeout=120s >/dev/null 2>&1
  out=$(kubectl logs "pod/$pod" -n envoy-gateway 2>/dev/null)
  kubectl delete "pod/$pod" -n envoy-gateway --wait=false >/dev/null 2>&1

  # Does this cluster enforce NetworkPolicy at all? Answer that BEFORE reading any
  # deny result, because if it does not, every deny probe reports "open" and the
  # sweep would blame the manifests for the CNI's behaviour.
  #
  # Kind's default CNI is kindnet, which ships no NetworkPolicy controller.
  # Measured on Kind 2026-08-21: a pod in `user` reached `inventory:8080`, which
  # `allow-inventory-protected-http` grants to envoy-gateway ONLY, in a namespace
  # that also carries `deny-all-ingress`. The policies are correct and simply not
  # applied.
  local denies_open=0 cni unenforced=0
  while read -r tag ns port verdict; do
    [ "$tag" = "PROBE" ] || continue
    case " $EDGE_DENIES " in *" $ns:$port "*) [ "$verdict" = open ] && denies_open=1 ;; esac
  done <<<"$out"
  cni=$(kubectl -n kube-system get pods -o name 2>/dev/null | grep -oE 'kindnet|calico|cilium' | head -1)
  if [ "$denies_open" = 1 ] && [ "${cni:-kindnet}" = "kindnet" ]; then
    unenforced=1
    echo "SKIP  live: NetworkPolicy is NOT ENFORCED here (CNI: ${cni:-kindnet})."
    echo "      kindnet ships no NetworkPolicy controller, so every deny probe answers"
    echo "      'open' whatever the manifests say. The allow probes below still mean"
    echo "      something; the deny probes do not. THIS GATE DOES NOT PROVE NETWORK"
    echo "      ISOLATION — manifest mode above is the only isolation evidence Kind"
    echo "      can give. Swap in Calico or Cilium to get more."
  fi

  while read -r tag ns port verdict; do
    [ "$tag" = "PROBE" ] || continue
    probes=$((probes + 1))
    want=open
    case " $EDGE_DENIES " in *" $ns:$port "*) want=closed ;; esac
    if [ "$verdict" = "$want" ]; then
      pass "live: $ns:$port -> $verdict"
    elif [ "$want" = closed ] && [ "$unenforced" = 1 ]; then
      printf "SKIP  live: %s:%s -> open, unenforceable on this CNI\n" "$ns" "$port"
    else
      fail "live: $ns:$port -> got=$verdict want=$want"
    fi
  done <<<"$out"

  # Silence is not success: every probe must come back with a verdict.
  if [ "$probes" -ne "$expected" ]; then
    fail "live: parsed $probes probes, expected $expected — the sweep is not fully verified"
    [ "$probes" -eq 0 ] && echo "      (no output at all: is the kubectl context set and the cluster up?)"
  fi
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
