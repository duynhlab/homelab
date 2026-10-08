#!/usr/bin/env bash
# Kind gate K3.8 / K3.9 (RFC-0029): a converted service's runtime and migrator
# logins behave as docs/databases/authorization.md says, checked as the REAL
# logins through pg_hba rather than by asking the catalog as postgres.
#
#   scripts/db-authz-check.sh            # every converted service
#   scripts/db-authz-check.sh review     # one service
#
# One short-lived pod per service in the cluster's namespace reads the runtime
# and migrator Secrets and prints one CHECK line per assertion; the script
# parses the pod's logs (not an attach, see db-isolation-sweep.sh) and fails
# unless every expected CHECK came back PASS.
set -u

IMAGE="ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie"
# service -> "cluster namespace host table", where table is one table the
# runtime serves from. Add a service when it is converted.
declare_service() {
  case "$1" in
    user)         echo "platform-db platform platform-db-rw.platform.svc.cluster.local user_profiles" ;;
    notification) echo "platform-db platform platform-db-rw.platform.svc.cluster.local notifications" ;;
    shipping)     echo "platform-db platform platform-db-rw.platform.svc.cluster.local shipments" ;;
    review)       echo "platform-db platform platform-db-rw.platform.svc.cluster.local reviews" ;;
    *) return 1 ;;
  esac
}
CONVERTED=(user notification shipping review)
EXPECTED_CHECKS=10
FAIL=0

check_service() {
  local svc="$1" cluster ns host table
  read -r cluster ns host table <<<"$(declare_service "$svc")" || { echo "FAIL  unknown service $svc"; FAIL=1; return; }
  local pod="db-authz-check-$svc-$$"

  # $1 = check name, $2 = role env prefix (RT|MG), $3 = expectation
  # (ok|denied), $4 = SQL. "denied" accepts only a privilege refusal, so a
  # typo or a missing table can never pass as a denial.
  local script
  script=$(cat <<EOF
q() { PGPASSWORD="\$(eval echo \\\$\${2}_PASS)" psql "host=$host dbname=$svc user=\$(eval echo \\\$\${2}_USER) connect_timeout=5" -qAtX -v ON_ERROR_STOP=1 -c "\$4" 2>&1; }
check() {
  out=\$(q "\$@"); rc=\$?
  case "\$3" in
    ok)     [ \$rc -eq 0 ] && echo "CHECK \$1 PASS \$out" || echo "CHECK \$1 FAIL rc=\$rc \$out" ;;
    denied) if [ \$rc -ne 0 ] && echo "\$out" | grep -Eq "permission denied|must be owner"; then echo "CHECK \$1 PASS denied"; else echo "CHECK \$1 FAIL rc=\$rc \$out"; fi ;;
    *)      [ "\$out" = "\$3" ] && echo "CHECK \$1 PASS \$out" || echo "CHECK \$1 FAIL want=\$3 got=\$out" ;;
  esac
}
check K3.8-runtime-reads           RT ok     "SELECT count(*) FROM public.$table"
check K3.8-runtime-no-create       RT denied "CREATE TABLE public.k38_probe (i int)"
check K3.8-runtime-no-alter        RT denied "ALTER TABLE public.$table ADD COLUMN k38_probe int"
check K3.8-runtime-no-drop         RT denied "DROP TABLE public.$table"
check K3.8-runtime-no-owner        RT denied "SET ROLE ${svc}_owner"
check K3.8-runtime-no-migrations   RT denied "SELECT count(*) FROM public.schema_migrations"
check K3.9-migrator-no-create      MG denied "CREATE TABLE public.k39_probe (i int)"
check K3.9-migrator-creates-as-owner MG ok   "BEGIN; SET ROLE ${svc}_owner; CREATE TABLE public.k39_probe (i int); ROLLBACK;"
check K3.9-owner-owns-everything   MG 0      "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relowner <> '${svc}_owner'::regrole AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'e')"
check K3.9-membership-f-f-t        MG f/f/t  "SELECT admin_option::text::char || '/' || inherit_option::text::char || '/' || set_option::text::char FROM pg_auth_members WHERE member = '${svc}_migrator'::regrole AND roleid = '${svc}_owner'::regrole"
EOF
)

  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  namespace: $ns
  labels: {app.kubernetes.io/name: db-authz-check}
spec:
  restartPolicy: Never
  containers:
    - name: check
      image: $IMAGE
      command: ["sh", "-c", $(printf '%s' "$script" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')]
      resources:
        requests: {cpu: 10m, memory: 32Mi}
        limits: {memory: 64Mi}
      env:
        - {name: RT_USER, valueFrom: {secretKeyRef: {name: $cluster-$svc-runtime-secret, key: username}}}
        - {name: RT_PASS, valueFrom: {secretKeyRef: {name: $cluster-$svc-runtime-secret, key: password}}}
        - {name: MG_USER, valueFrom: {secretKeyRef: {name: $cluster-$svc-migrator-secret, key: username}}}
        - {name: MG_PASS, valueFrom: {secretKeyRef: {name: $cluster-$svc-migrator-secret, key: password}}}
EOF
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$pod" -n "$ns" --timeout=120s >/dev/null 2>&1
  local out rows=0
  out=$(kubectl logs "pod/$pod" -n "$ns" 2>/dev/null)
  kubectl delete "pod/$pod" -n "$ns" --wait=false >/dev/null 2>&1

  local tag name verdict rest
  while read -r tag name verdict rest; do
    [ "$tag" = "CHECK" ] || continue
    rows=$((rows + 1))
    printf "%-4s  %-8s %-36s %s\n" "$verdict" "$svc" "$name" "$rest"
    [ "$verdict" = PASS ] || FAIL=1
  done <<<"$out"
  if [ "$rows" -ne "$EXPECTED_CHECKS" ]; then
    printf "FAIL  %-8s parsed %s checks, expected %s\n" "$svc" "$rows" "$EXPECTED_CHECKS"
    FAIL=1
  fi
}

services=("$@")
[ ${#services[@]} -gt 0 ] || services=("${CONVERTED[@]}")
for s in "${services[@]}"; do check_service "$s"; done

echo
if [ "$FAIL" = 0 ]; then echo "DB AUTHORIZATION: PASS"; else echo "DB AUTHORIZATION: FAIL"; fi
exit "$FAIL"
