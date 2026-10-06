# shellcheck shell=bash
# CNPG-01..07 against the live Kind platform-db. Sourced by ../run.sh.
#
# Every object it creates is named lab_* / lab-* and labelled
# platform.duynhlab.dev/lab=pg-authz; cnpg_cleanup removes the CRs, Secrets,
# PostgreSQL roles and the one table it made, also when an experiment fails.

KCTX="${KCTX:-kind-homelab}"
NS=platform
CLUSTER=platform-db
LAB_LABEL="platform.duynhlab.dev/lab=pg-authz"
# CNPG-06: how long manual drift is left alone before the spec is touched.
DRIFT_WAIT="${DRIFT_WAIT:-120}"

k() { kubectl --context "$KCTX" -n "$NS" "$@"; }

primary() {
  k get pod -l "cnpg.io/cluster=$CLUSTER,role=primary" -o jsonpath='{.items[0].metadata.name}'
}

# psql as postgres on the primary, unaligned and quiet.
sql() { k exec -i "$PRIMARY" -c postgres -- psql -U postgres -d postgres -qAtX -v ON_ERROR_STOP=1 -c "$1"; }

# role <cr-name> <pg-name> <login> <inherit> <inRoles yaml list> [reclaim] [secret]
role() {
  local secret_block=""
  [ -n "${7:-}" ] && secret_block="  passwordSecret:
    name: $7"
  k apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: DatabaseRole
metadata:
  name: $1
  labels: {platform.duynhlab.dev/lab: pg-authz}
spec:
  cluster: {name: $CLUSTER}
  name: $2
  comment: "pg-authz-lab"
  login: $3
  superuser: false
  createdb: false
  createrole: false
  inherit: $4
  replication: false
  bypassrls: false
  connectionLimit: -1
  inRoles: $5
  databaseRoleReclaimPolicy: ${6:-retain}
$secret_block
EOF
}

# Wait until the operator has reconciled the current generation.
reconciled() {
  local gen i
  for i in $(seq 1 60); do
    gen="$(k get databaserole "$1" -o jsonpath='{.metadata.generation}')"
    [ "$(k get databaserole "$1" -o jsonpath='{.status.observedGeneration}/{.status.applied}')" = "$gen/true" ] && return 0
    sleep 2
  done
  return 1
}

# A spec change is what triggers a reconcile (CNPG-06).
touch_spec() { k patch databaserole "$1" --type merge -p "{\"spec\":{\"comment\":\"pg-authz-lab $(date +%s%N)\"}}" >/dev/null; }

membership() {
  sql "SELECT admin_option::int || '/' || inherit_option::int || '/' || set_option::int
         FROM pg_auth_members WHERE member = '$1'::regrole AND roleid = '$2'::regrole"
}

attr() { sql "SELECT $2 FROM pg_roles WHERE rolname = '$1'"; }

cnpg_cleanup() {
  k delete databaserole -l "$LAB_LABEL" --wait=false >/dev/null 2>&1
  sql "DROP TABLE IF EXISTS public.lab_owned" >/dev/null 2>&1
  local i
  for i in $(seq 1 30); do
    [ -z "$(k get databaserole -l "$LAB_LABEL" -o name 2>/dev/null)" ] && break
    sleep 2
  done
  k delete secret -l "$LAB_LABEL" >/dev/null 2>&1
  local r
  for r in $(sql "SELECT rolname FROM pg_roles WHERE rolname LIKE 'lab\_%'" 2>/dev/null); do
    sql "DROP ROLE IF EXISTS $r" >/dev/null 2>&1
  done
}

cnpg_01() {
  sql "CREATE ROLE lab_adopt LOGIN CREATEDB CONNECTION LIMIT 5" >/dev/null
  role lab-adopt lab_adopt true true "[]"
  reconciled lab-adopt || { row CNPG-01 FAIL "adoption never reconciled"; return; }
  if [ "$(attr lab_adopt 'rolcreatedb::int || rolconnlimit::text')" = "0-1" ]; then
    row CNPG-01 PASS "Adoption is authoritative: CREATEDB and CONNECTION LIMIT left out of the spec were reset"
  else
    row CNPG-01 FAIL "omitted attributes survived adoption: $(attr lab_adopt 'rolcreatedb, rolconnlimit')"
  fi
}

cnpg_02() {
  local pw
  pw="$(head -c 24 /dev/urandom | base64 | tr -d '/+=')"
  k create secret generic lab-pw --type kubernetes.io/basic-auth --save-config \
    --from-literal=username=lab_pw --from-literal=password="$pw" >/dev/null
  k label secret lab-pw cnpg.io/reload=true platform.duynhlab.dev/lab=pg-authz >/dev/null
  role lab-pw lab_pw true true "[]" retain lab-pw
  reconciled lab-pw || { row CNPG-02 FAIL "role with a password never reconciled"; return; }
  local v1 rv1 v2 rv2 i
  v1="$(sql "SELECT md5(rolpassword) FROM pg_authid WHERE rolname = 'lab_pw'")"
  rv1="$(k get databaserole lab-pw -o jsonpath='{.status.secretResourceVersion}')"
  pw="$(head -c 24 /dev/urandom | base64 | tr -d '/+=')"
  k create secret generic lab-pw --type kubernetes.io/basic-auth \
    --from-literal=username=lab_pw --from-literal=password="$pw" --dry-run=client -o yaml \
    | k apply -f - >/dev/null
  unset pw
  for i in $(seq 1 60); do
    rv2="$(k get databaserole lab-pw -o jsonpath='{.status.secretResourceVersion}')"
    [ "$rv2" != "$rv1" ] && break
    sleep 2
  done
  v2="$(sql "SELECT md5(rolpassword) FROM pg_authid WHERE rolname = 'lab_pw'")"
  if [ "$rv2" != "$rv1" ] && [ -n "$v1" ] && [ "$v1" != "$v2" ]; then
    row CNPG-02 PASS "A Secret change is applied: status secret version and the SCRAM verifier both changed"
  else
    row CNPG-02 FAIL "rv $rv1 -> $rv2, verifier changed: $([ "$v1" != "$v2" ] && echo yes || echo no)"
  fi
}

cnpg_03() {
  local out
  if out="$(k patch databaserole lab-adopt --type merge -p '{"spec":{"name":"lab_renamed"}}' 2>&1)"; then
    row CNPG-03 FAIL "the API accepted a role rename"
  elif grep -qi "immutable" <<<"$out"; then
    row CNPG-03 PASS "spec.name is immutable: the API rejects a rename"
  else
    row CNPG-03 FAIL "rename refused for another reason: $(head -c 120 <<<"$out")"
  fi
}

cnpg_04() {
  role lab-parent lab_parent false true "[]"
  reconciled lab-parent || { row CNPG-04 FAIL "parent never reconciled"; return; }
  role lab-member lab_member false true "[lab_parent]"
  reconciled lab-member || { row CNPG-04 FAIL "member never reconciled"; return; }
  sql "GRANT lab_parent TO lab_member WITH ADMIN TRUE" >/dev/null
  touch_spec lab-member; reconciled lab-member
  local kept; kept="$(membership lab_member lab_parent)"
  sql "REVOKE lab_parent FROM lab_member" >/dev/null
  touch_spec lab-member; reconciled lab-member
  local back; back="$(membership lab_member lab_parent)"
  if [ "$kept" = "1/1/1" ] && [ "$back" = "0/1/1" ]; then
    row CNPG-04 PASS "CNPG ignores membership options: ADMIN survived a reconcile, a recreated edge came back 0/1/1"
  else
    row CNPG-04 FAIL "after reconcile $kept, after recreate $back (admin/inherit/set)"
  fi
}

cnpg_05() {
  role lab-keep lab_keep false true "[]" retain
  role lab-gone lab_gone false true "[]" delete
  reconciled lab-keep && reconciled lab-gone || { row CNPG-05 FAIL "roles never reconciled"; return; }
  sql "CREATE TABLE public.lab_owned (i int); ALTER TABLE public.lab_owned OWNER TO lab_gone" >/dev/null
  k delete databaserole lab-keep lab-gone --wait=false >/dev/null
  local i
  for i in $(seq 1 15); do
    [ -z "$(k get databaserole lab-keep -o name 2>/dev/null)" ] && break
    sleep 2
  done
  local keep_role gone_cr gone_role
  keep_role="$(attr lab_keep "count(*)")"
  gone_cr="$(k get databaserole lab-gone -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)"
  gone_role="$(attr lab_gone "count(*)")"
  sql "DROP TABLE public.lab_owned" >/dev/null
  for i in $(seq 1 30); do
    [ -z "$(k get databaserole lab-gone -o name 2>/dev/null)" ] && break
    sleep 2
  done
  local gone_after; gone_after="$(sql "SELECT count(*) FROM pg_roles WHERE rolname = 'lab_gone'")"
  if [ "$keep_role" = 1 ] && [ -n "$gone_cr" ] && [ "$gone_role" = 1 ] && [ "$gone_after" = 0 ]; then
    row CNPG-05 PASS "retain keeps the role; delete blocks on the finalizer while the role owns objects, then drops it"
  else
    row CNPG-05 FAIL "retain kept=$keep_role, delete blocked=$([ -n "$gone_cr" ] && echo yes || echo no), role while owning=$gone_role, after=$gone_after"
  fi
}

cnpg_06() {
  role lab-drift lab_drift false true "[]"
  reconciled lab-drift || { row CNPG-06 FAIL "role never reconciled"; return; }
  sql "ALTER ROLE lab_drift CREATEDB" >/dev/null
  sleep "$DRIFT_WAIT"
  local survived; survived="$(attr lab_drift 'rolcreatedb::int')"
  local t0 i; t0=$(date +%s)
  touch_spec lab-drift
  for i in $(seq 1 30); do
    [ "$(attr lab_drift 'rolcreatedb::int')" = 0 ] && break
    sleep 1
  done
  local repaired=$(( $(date +%s) - t0 ))
  if [ "$survived" = 1 ] && [ "$(attr lab_drift 'rolcreatedb::int')" = 0 ]; then
    row CNPG-06 PASS "Manual drift survived ${DRIFT_WAIT}s untouched and was repaired ${repaired}s after a spec change"
  else
    row CNPG-06 FAIL "drift survived=$survived, repaired=$(attr lab_drift 'rolcreatedb::int')"
  fi
}

cnpg_07() {
  role lab-owner lab_owner false true "[]"
  reconciled lab-owner || { row CNPG-07 FAIL "owner never reconciled"; return; }
  role lab-migrator lab_migrator true false "[lab_owner]"
  reconciled lab-migrator || { row CNPG-07 FAIL "migrator never reconciled"; return; }
  local first; first="$(membership lab_migrator lab_owner)"
  sql "REVOKE lab_owner FROM lab_migrator" >/dev/null
  touch_spec lab-migrator; reconciled lab-migrator
  local again; again="$(membership lab_migrator lab_owner)"
  if [ "$first" = "0/0/1" ] && [ "$again" = "0/0/1" ]; then
    row CNPG-07 PASS "inherit: false on the member: CNPG creates and recreates the owner edge as ADMIN f / INHERIT f / SET t"
  else
    row CNPG-07 FAIL "created $first, recreated $again (admin/inherit/set)"
  fi
}

cnpg_main() {
  [ "$(kubectl config get-contexts -o name | grep -cx "$KCTX")" = 1 ] || { row "CNPG-*" FAIL "no kube context $KCTX"; return; }
  PRIMARY="$(primary)"
  [ -n "$PRIMARY" ] || { row "CNPG-*" FAIL "no $CLUSTER primary"; return; }
  echo "CNPG $(k get cluster "$CLUSTER" -o jsonpath='{.status.image}') on $KCTX/$NS/$CLUSTER (primary $PRIMARY)"
  trap cnpg_cleanup EXIT
  cnpg_cleanup
  cnpg_01; cnpg_02; cnpg_03; cnpg_04; cnpg_05; cnpg_06; cnpg_07
  cnpg_cleanup
  trap - EXIT
  [ -z "$(k get databaserole,secret -l "$LAB_LABEL" -o name 2>/dev/null)" ] \
    && [ "$(sql "SELECT count(*) FROM pg_roles WHERE rolname LIKE 'lab\_%'")" = 0 ] \
    || row cleanup FAIL "lab objects left behind"
}
