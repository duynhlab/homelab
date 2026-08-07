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
declare -A EXPECT

product_roles=(payment product cart order checkout inventory)
product_dbs=(payment product cart order checkout inventory)
for r in "${product_roles[@]}"; do
  for d in "${product_dbs[@]}"; do
    if [ "$r" = "$d" ]; then EXPECT["product/$r/$d"]=allow; else EXPECT["product/$r/$d"]=reject; fi
  done
done

platform_roles=(auth user notification shipping review temporal vault_rotator)
platform_dbs=(auth user notification shipping review temporal temporal_visibility)
for r in "${platform_roles[@]}"; do
  for d in "${platform_dbs[@]}"; do
    EXPECT["platform/$r/$d"]=reject
  done
done
# the committed allow lines (platform-db instance.yaml): each service to its
# own db, temporal additionally to temporal_visibility, and the RFC-0008
# rotator role to notification.
for p in auth/auth user/user notification/notification shipping/shipping \
         review/review temporal/temporal temporal/temporal_visibility \
         vault_rotator/notification; do
  EXPECT["platform/${p%%/*}/${p##*/}"]=allow
done

sweep() { # $1=cluster-label $2=namespace $3=host $4=roles... (uses EXPECT)
  local label="$1" ns="$2" host="$3"; shift 3
  local pairs=()
  for key in "${!EXPECT[@]}"; do
    case "$key" in "$label"/*) pairs+=("${key#"$label"/}");; esac
  done

  local script=""
  for pair in "${pairs[@]}"; do
    local role="${pair%%/*}" db="${pair##*/}"
    script+="echo \"PAIR $role $db \$(psql 'host=$host user=$role dbname=$db password=wrong-on-purpose connect_timeout=5' -c 'select 1' 2>&1 | head -1)\";"
  done

  # No pipe into while: a piped while runs in a subshell and FAIL=1 would be
  # lost — the sweep would always exit 0 (the exact harness-lies class the
  # e2e traps note warns about).
  local out
  out=$(kubectl run "isolation-sweep-$label" --rm -i --restart=Never -n "$ns" \
    --image="$IMAGE" --command -- sh -c "$script" 2>/dev/null)
  while read -r tag role db verdict; do
    # Only PAIR lines are verdicts; kubectl's own chatter (e.g. the pod
    # deletion notice) must not be parsed as a matrix row.
    [ "$tag" = "PAIR" ] || continue
    [ "$role" ] || continue
    local key="$label/$role/$db" got=""
    case "$verdict" in
      *"pg_hba.conf rejects"*)            got=reject ;;
      *"password authentication failed"*) got=allow ;;
      *"does not exist"*)                 got=missing ;;
      *)                                  got="other($verdict)" ;;
    esac
    if [ "${EXPECT[$key]:-?}" = "$got" ]; then
      printf "PASS  %-9s %-14s -> %-20s %s\n" "$label" "$role" "$db" "$got"
    else
      printf "FAIL  %-9s %-14s -> %-20s got=%s want=%s\n" "$label" "$role" "$db" "$got" "${EXPECT[$key]:-?}"
      FAIL=1
    fi
  done <<<"$out"
}

echo "== product-db (6 allow / 30 reject expected)"
sweep product product "product-db-rw.product.svc.cluster.local"
echo "== platform-db (8 allow / 41 reject expected)"
sweep platform platform "platform-db-rw.platform.svc.cluster.local"

echo
if [ "$FAIL" = 0 ]; then echo "ISOLATION MATRIX: PASS"; else echo "ISOLATION MATRIX: FAIL"; fi
exit $FAIL
