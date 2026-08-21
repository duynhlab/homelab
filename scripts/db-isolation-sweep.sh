#!/usr/bin/env bash
# RFC-0012 P4: the (role x database) isolation matrix, as a scripted sweep.
#
# ADR-015 promised "a scripted psql sweep at each bring-up"; this is that
# script. It proves pg_hba isolation WITHOUT any credentials: a pair the
# matrix forbids is rejected by the `host all all all reject` line BEFORE
# authentication ("pg_hba.conf rejects connection"), while an allowed pair
# probed with a wrong password fails AT authentication ("password
# authentication failed"). The error message is the verdict.
#
# Run against a live cluster (kubectl context set). Exit 0 iff every pair
# answers exactly as the matrix expects. ~1 pod per cluster, one psql loop.
set -u

IMAGE="ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie"
FAIL=0

# expected verdict per pair: "allow" (auth-level failure expected) | "reject"
# (pg_hba-level rejection expected). Derived from the committed pg_hba in
# kubernetes/infra/configs/databases/clusters/*/instance.yaml — update BOTH
# when a service is added.
#
# Held as newline-delimited "label/role/db=verdict" rather than an associative
# array. `declare -A` needs bash 4, macOS ships bash 3.2, and this was the only
# script in the repo that required bash 4 — so on the machine that actually runs
# the audit it died at this line with `declare: -A: invalid option` followed by
# an unbound-variable cascade. A sweep whose green line is meant to be proof of
# isolation must at least start.
EXPECT=""
expect_put() { EXPECT="${EXPECT}$1=$2
"; }
# prints the verdict for a key, or nothing when the key is absent.
# LAST match wins, because the builders below deliberately write a broad
# `reject` for every pair and then overwrite the committed allow lines — the
# same overwrite an associative array gave for free. Taking the first match
# would silently expect `reject` on all eight allow pairs.
expect_get() {
  local hit
  hit=$(printf '%s' "$EXPECT" | grep -- "^$1=" | tail -1) || return 0
  [ -n "$hit" ] || return 0
  printf '%s' "${hit#*=}"
}
# prints the role/db pairs registered under a label, once each — an overwritten
# key appears twice in EXPECT and would otherwise be probed twice
expect_pairs() {
  printf '%s' "$EXPECT" | sed -n "s|^$1/\([^=]*\)=.*|\1|p" | sort -u
}

product_roles=(payment product cart order checkout inventory)
product_dbs=(payment product cart order checkout inventory)
for r in "${product_roles[@]}"; do
  for d in "${product_dbs[@]}"; do
    if [ "$r" = "$d" ]; then expect_put "product/$r/$d" allow; else expect_put "product/$r/$d" reject; fi
  done
done

platform_roles=(user notification shipping review temporal vault_rotator)
platform_dbs=(user notification shipping review temporal temporal_visibility)
for r in "${platform_roles[@]}"; do
  for d in "${platform_dbs[@]}"; do
    expect_put "platform/$r/$d" reject
  done
done
# the committed allow lines (platform-db instance.yaml): each service to its
# own db, temporal additionally to temporal_visibility, and the RFC-0008
# rotator role to notification.
#
# NOT in the matrix, and deliberately so rather than forgotten: the pg_hba also
# carries `host keycloak keycloak`. Keycloak connects direct to :5432 (its
# Agroal pool needs long-lived connections and server-side prepared statements,
# ADR-041), so the pair is real and currently untested — untested coverage, not
# a failure. Adding it means deciding its full allow/reject row against every
# other platform role, which is its own change.
for p in user/user notification/notification shipping/shipping \
         review/review temporal/temporal temporal/temporal_visibility \
         vault_rotator/notification; do
  expect_put "platform/${p%%/*}/${p##*/}" allow
done

sweep() { # $1=cluster-label $2=namespace $3=host $4=roles... (uses EXPECT)
  local label="$1" ns="$2" host="$3"; shift 3
  local pairs=()
  local pr
  while read -r pr; do [ -n "$pr" ] && pairs+=("$pr"); done <<<"$(expect_pairs "$label")"

  local script=""
  for pair in "${pairs[@]}"; do
    local role="${pair%%/*}" db="${pair##*/}"
    script+="echo \"PAIR $role $db \$(psql 'host=$host user=$role dbname=$db password=wrong-on-purpose connect_timeout=5' -c 'select 1' 2>&1 | head -1)\";"
  done

  # No pipe into while: a piped while runs in a subshell and FAIL=1 would be
  # lost — the sweep would always exit 0 (the exact harness-lies class the
  # e2e traps note warns about).
  local out rows=0 pod="isolation-sweep-$label-$$"
  # Read the pod's LOGS, do not attach to it. `kubectl run -i` streams over an
  # attach, and an attach loses output when the container writes a burst and exits
  # immediately: measured on Kind, the pod emitted all 36 PAIR lines while the
  # parser saw 35 — a different pair each run, sometimes one in each cluster.
  # Before the row-count assertion below existed, that printed
  # "ISOLATION MATRIX: PASS" on 35 of 36 pairs, which is the worst possible
  # outcome for a script whose green line is the isolation evidence. Logs are
  # written by the kubelet and are not subject to that race.
  kubectl run "$pod" --restart=Never -n "$ns" \
    --image="$IMAGE" --command -- sh -c "$script" >/dev/null 2>&1
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$pod" -n "$ns" --timeout=180s >/dev/null 2>&1
  out=$(kubectl logs "pod/$pod" -n "$ns" 2>/dev/null)
  kubectl delete "pod/$pod" -n "$ns" --wait=false >/dev/null 2>&1
  while read -r tag role db verdict; do
    # Only PAIR lines are verdicts; kubectl's own chatter (e.g. the pod
    # deletion notice) must not be parsed as a matrix row.
    [ "$tag" = "PAIR" ] || continue
    [ "$role" ] || continue
    local key="$label/$role/$db" got="" want=""
    want=$(expect_get "$key"); [ -n "$want" ] || want="?"
    case "$verdict" in
      *"pg_hba.conf rejects"*)            got=reject ;;
      *"password authentication failed"*) got=allow ;;
      *"does not exist"*)                 got=missing ;;
      *)                                  got="other($verdict)" ;;
    esac
    rows=$((rows + 1))
    if [ "$want" = "$got" ]; then
      printf "PASS  %-9s %-14s -> %-20s %s\n" "$label" "$role" "$db" "$got"
    else
      printf "FAIL  %-9s %-14s -> %-20s got=%s want=%s\n" "$label" "$role" "$db" "$got" "$want"
      FAIL=1
    fi
  done <<<"$out"

  # Silence is not success. With no cluster reachable, kubectl fails, $out is
  # empty, the loop above runs zero times and FAIL stays 0 — so the sweep would
  # print "ISOLATION MATRIX: PASS" having verified nothing. That is the exact
  # harness-lies class this script's header warns about, so the row count is
  # itself an assertion: every pair in the matrix must come back with a verdict.
  if [ "$rows" -ne "${#pairs[@]}" ]; then
    printf "FAIL  %-9s parsed %s verdicts, expected %s — the matrix is not fully verified\n" \
      "$label" "$rows" "${#pairs[@]}"
    [ "$rows" -eq 0 ] && printf "      (no output at all: is the kubectl context set and the cluster up?)\n"
    FAIL=1
  fi
}

echo "== product-db (6 allow / 30 reject expected)"
sweep product product "product-db-rw.product.svc.cluster.local"
echo "== platform-db (7 allow / 29 reject expected)"
sweep platform platform "platform-db-rw.platform.svc.cluster.local"

echo
if [ "$FAIL" = 0 ]; then echo "ISOLATION MATRIX: PASS"; else echo "ISOLATION MATRIX: FAIL"; fi
exit $FAIL
