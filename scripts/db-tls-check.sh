#!/usr/bin/env bash
# ADR-089: prove each PostgreSQL hop (pooled, and migrate's direct hop to the
# primary) verifies its server and refuses plaintext. For every hop below, one pod in the client's namespace mounts the
# hop's CA Secret and runs four psql logins with a deliberately wrong password:
#
#   ok         verify-full, DNS name, right CA -> fails at authentication
#   wronghost  verify-full, Service ClusterIP  -> host name mismatch
#   wrongca    verify-full, system CA bundle   -> certificate verify failed
#   plaintext  sslmode=disable                 -> refused before auth
#
# An authentication error on "ok" (PgDog: "password ... is wrong", PgBouncer:
# "SASL authentication failed") means the TLS handshake and the host-name
# check both passed; the other three must fail before authentication. No
# Secret value is read. Same harness shape as db-isolation-sweep.sh: logs,
# not attach, and the row count is an assertion.
set -u

IMAGE="ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie"
FAIL=0

# label|client namespace|service|service namespace|port|database|user|CA Secret|plaintext refusal text|optional
# An optional hop is skipped when its Service does not exist: the DR replica is
# absent when the databases-cnpg-dr wave is turned off.
HOPS="
pgdog|product|pgdog-product|product|6432|product|product_runtime|product-db-ca-trust|only TLS connections are allowed|
pgbouncer|user|platform-db-pooler-rw|platform|5432|user|user_runtime|platform-db-ca-trust|SSL required|
product-rw|product|product-db-rw|product|5432|product|product_migrator|product-db-ca-trust|pg_hba.conf rejects connection|
platform-rw|user|platform-db-rw|platform|5432|user|user_migrator|platform-db-ca-trust|pg_hba.conf rejects connection|
product-rep|product|product-db-replica-rw|product|5432|product|product_migrator|product-db-ca-trust|pg_hba.conf rejects connection|optional
"

check_hop() {
  local label="$1" ns="$2" svc="$3" svcns="$4" port="$5" db="$6" user="$7" ca="$8" plain="$9" optional="${10}"
  local host="$svc.$svcns.svc.cluster.local" ip
  ip=$(kubectl get svc "$svc" -n "$svcns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [ -z "$ip" ] && [ "$optional" = optional ]; then
    printf "SKIP  %-11s Service %s/%s not found (optional hop)\n" "$label" "$svcns" "$svc"; return
  fi
  if [ -z "$ip" ]; then
    printf "FAIL  %-11s Service %s/%s not found\n" "$label" "$svcns" "$svc"; FAIL=1; return
  fi
  # 15 s: PgDog (passthrough) answers a wrong password only after its
  # checkout_timeout (5 s) runs out while it tries the password on PostgreSQL.
  local base="port=$port dbname=$db user=$user password=wrong-on-purpose connect_timeout=15"
  local script=""
  script+="echo \"CASE ok \$(psql 'host=$host sslmode=verify-full sslrootcert=/ca/ca.crt $base' -c 'select 1' 2>&1 | head -1)\";"
  script+="echo \"CASE wronghost \$(psql 'host=$ip sslmode=verify-full sslrootcert=/ca/ca.crt $base' -c 'select 1' 2>&1 | head -1)\";"
  script+="echo \"CASE wrongca \$(psql 'host=$host sslmode=verify-full sslrootcert=system $base' -c 'select 1' 2>&1 | head -1)\";"
  script+="echo \"CASE plaintext \$(psql 'host=$host sslmode=disable $base' -c 'select 1' 2>&1 | head -1)\";"

  local pod="db-tls-check-$label-$$" overrides out rows=0
  overrides=$(jq -nc --arg pod "$pod" --arg image "$IMAGE" --arg ca "$ca" --arg script "$script" '{spec: {
    volumes: [{name: "ca", secret: {secretName: $ca, items: [{key: "ca.crt", path: "ca.crt"}]}}],
    containers: [{name: $pod, image: $image, command: ["sh", "-c", $script],
      volumeMounts: [{name: "ca", mountPath: "/ca", readOnly: true}],
      resources: {requests: {cpu: "10m", memory: "32Mi"}, limits: {memory: "64Mi"}}}]}}')
  kubectl run "$pod" --restart=Never -n "$ns" --image="$IMAGE" --overrides="$overrides" >/dev/null 2>&1
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$pod" -n "$ns" --timeout=120s >/dev/null 2>&1
  out=$(kubectl logs "pod/$pod" -n "$ns" 2>/dev/null)
  kubectl delete "pod/$pod" -n "$ns" --wait=false >/dev/null 2>&1

  local tag case verdict want
  while read -r tag case verdict; do
    [ "$tag" = "CASE" ] || continue
    case "$case" in
      ok)        want="password" ;;
      wronghost) want="does not match host name" ;;
      wrongca)   want="certificate verify failed" ;;
      plaintext) want="$plain" ;;
      *)         continue ;;
    esac
    rows=$((rows + 1))
    if [[ "$verdict" == *"$want"* ]] || { [ "$case" = ok ] && [[ "$verdict" == *"authentication failed"* ]]; }; then
      printf "PASS  %-11s %-9s %s\n" "$label" "$case" "$verdict"
    else
      printf "FAIL  %-11s %-9s want=\"%s\" got=\"%s\"\n" "$label" "$case" "$want" "$verdict"
      FAIL=1
    fi
  done <<<"$out"

  # Silence is not success: no cluster or a pod that never ran yields 0 rows.
  if [ "$rows" -ne 4 ]; then
    printf "FAIL  %-11s parsed %s of 4 cases (is the cluster up, and does %s exist in %s?)\n" "$label" "$rows" "$ca" "$ns"
    FAIL=1
  fi
}

while IFS='|' read -r label ns svc svcns port db user ca plain optional; do
  [ -n "$label" ] || continue
  echo "== $label ($svc.$svcns:$port from ns $ns)"
  check_hop "$label" "$ns" "$svc" "$svcns" "$port" "$db" "$user" "$ca" "$plain" "$optional"
done <<<"$HOPS"

echo
if [ "$FAIL" = 0 ]; then echo "DB TLS: PASS"; else echo "DB TLS: FAIL"; fi
exit $FAIL
