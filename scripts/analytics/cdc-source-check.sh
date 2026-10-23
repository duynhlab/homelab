#!/usr/bin/env bash
# CDC source gate on Kind (RFC-0030 phase 3, rows G3.1-G3.4 of the #1266
# gate catalog). Every probe prints PASS/FAIL; one FAIL fails the run.
#
#   G3.1  each publication holds exactly the ADR-067 tables and columns
#   G3.2  replication=database through the CDC pooler with verify-full
#         (IDENTIFY_SYSTEM + a temporary pgoutput slot), from the peerdb
#         namespace; a wrong host name, the wrong CA and plaintext fail; the
#         primary itself is unreachable from peerdb
#   G3.3  peerdb_<db>: LOGIN REPLICATION only, SELECT on the allowlisted
#         tables only, no CREATE anywhere
#   G3.4  three 30-second heartbeat jobs + one cleanup, owned and run by
#         analytics_heartbeat; every heartbeat row younger than 60 s
#
#   scripts/analytics/cdc-source-check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ALLOW=local-stack/analytics/allowlist.json
NS=product
PRIMARY="$(kubectl -n $NS get cluster product-db -o jsonpath='{.status.currentPrimary}')"
POOLER=product-db-pooler-cdc.product.svc
fail=0
ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; fail=1; }
sql() { kubectl -n $NS exec "$PRIMARY" -c postgres -- psql -XAtq -d "$1" -c "$2" 2>&1; }

# A throwaway client in the peerdb namespace with the CA PeerDB trusts.
probe() { # probe <name> <libpq conninfo> <sql> — prints the client's output
  kubectl -n peerdb run "cdc-probe-$1" --rm -i --restart=Never --quiet \
    --image=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":26,"seccompProfile":{"type":"RuntimeDefault"}},
      "containers":[{"name":"p","image":"ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie",
      "command":["psql","-XAtq","'"$2"'","-c","'"$3"'"],
      "env":[{"name":"PGPASSWORD","valueFrom":{"secretKeyRef":{"name":"product-db-peerdb-'"${4:-order}"'-secret","key":"password"}}},
             {"name":"PGCONNECT_TIMEOUT","value":"5"}],
      "volumeMounts":[{"name":"ca","mountPath":"/ca","readOnly":true}],
      "resources":{"requests":{"cpu":"10m","memory":"32Mi"},"limits":{"memory":"64Mi"}},
      "securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}],
      "volumes":[{"name":"ca","secret":{"secretName":"peerdb-ca-trust"}}]}}' 2>&1
}

for db in order checkout payment; do
  # G3.1 — publication = allowlist (+ heartbeat), table and column exact.
  want="$(python3 -c "import json,sys;a=json.load(open('$ALLOW'))['$db'];a['analytics_cdc_heartbeat']=['id','emitted_at'];print(';'.join(sorted(t+':'+','.join(sorted(c)) for t,c in a.items())))")"
  got="$(sql "$db" "SELECT string_agg(tablename||':'||(SELECT string_agg(a,',' ORDER BY a) FROM unnest(attnames) a),';' ORDER BY tablename) FROM pg_publication_tables WHERE pubname='analytics_$db'")"
  [ "$got" = "$want" ] && ok "G3.1 $db publication = allowlist" || bad "G3.1 $db publication: got [$got] want [$want]"

  # G3.3 — role attributes and exact table privileges.
  attrs="$(sql postgres "SELECT rolcanlogin,rolreplication,rolsuper,rolcreatedb,rolcreaterole,rolbypassrls FROM pg_roles WHERE rolname='peerdb_$db'")"
  [ "$attrs" = "t|t|f|f|f|f" ] && ok "G3.3 peerdb_$db LOGIN REPLICATION only" || bad "G3.3 peerdb_$db attributes $attrs"
  extra="$(sql "$db" "SELECT string_agg(c.relname,',') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND has_table_privilege('peerdb_$db',c.oid,'SELECT') AND c.relname NOT IN (SELECT tablename FROM pg_publication_tables WHERE pubname='analytics_$db')")"
  [ -z "$extra" ] && ok "G3.3 peerdb_$db reads only published tables" || bad "G3.3 peerdb_$db also reads: $extra"
  writes="$(sql "$db" "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND (has_table_privilege('peerdb_$db',c.oid,'INSERT,UPDATE,DELETE,TRUNCATE'))")"
  create="$(sql "$db" "SELECT has_schema_privilege('peerdb_$db','public','CREATE') OR has_database_privilege('peerdb_$db','$db','CREATE')")"
  [ "$writes" = 0 ] && [ "$create" = f ] && ok "G3.3 peerdb_$db has no write or CREATE" || bad "G3.3 peerdb_$db writes=$writes create=$create"
done

# G3.2 — through the pooler, verify-full, from the peerdb namespace.
CI="host=$POOLER port=5432 user=peerdb_order dbname=order sslmode=verify-full sslrootcert=/ca/ca.crt replication=database"
out="$(probe ident "$CI" "IDENTIFY_SYSTEM")"
echo "$out" | grep -qE '^[0-9]+\|[0-9]+\|' && ok "G3.2 IDENTIFY_SYSTEM through the pooler (verify-full)" || bad "G3.2 IDENTIFY_SYSTEM: $out"
out="$(probe slot "$CI" "CREATE_REPLICATION_SLOT cdc_gate_probe TEMPORARY LOGICAL pgoutput")"
echo "$out" | grep -q '^cdc_gate_probe|' && ok "G3.2 temporary pgoutput slot through the pooler" || bad "G3.2 slot: $out"
out="$(probe wronghost "host=product-db-pooler-cdc.product port=5432 user=peerdb_order dbname=order sslmode=verify-full sslrootcert=/ca/ca.crt" "SELECT 1")"
echo "$out" | grep -qi 'does not match\|certificate' && ok "G3.2 wrong host name refused" || bad "G3.2 wrong host accepted: $out"
out="$(probe wrongca "host=$POOLER port=5432 user=peerdb_order dbname=order sslmode=verify-full sslrootcert=system" "SELECT 1")"
echo "$out" | grep -qi 'certificate\|verify' && ok "G3.2 wrong CA refused" || bad "G3.2 wrong CA accepted: $out"
out="$(probe plain "host=$POOLER port=5432 user=peerdb_order dbname=order sslmode=disable" "SELECT 1")"
echo "$out" | grep -qiE 'ssl|tls|reject|no pg_hba' && ok "G3.2 plaintext refused" || bad "G3.2 plaintext accepted: $out"
out="$(probe direct "host=product-db-rw.product.svc port=5432 user=peerdb_order dbname=order sslmode=verify-full sslrootcert=/ca/ca.crt" "SELECT 1")"
echo "$out" | grep -qiE 'timeout|timed out' && ok "G3.2 primary unreachable from peerdb" || bad "G3.2 direct primary: $out"

# G3.4 — heartbeat jobs and freshness.
jobs="$(sql postgres "SELECT string_agg(jobname||'@'||database||'@'||username||'@'||schedule,' ' ORDER BY jobname) FROM cron.job")"
want="analytics-checkout@checkout@analytics_heartbeat@30 seconds analytics-history-cleanup@postgres@analytics_heartbeat@0 3 * * * analytics-order@order@analytics_heartbeat@30 seconds analytics-payment@payment@analytics_heartbeat@30 seconds"
[ "$jobs" = "$want" ] && ok "G3.4 three 30 s heartbeat jobs + cleanup, all analytics_heartbeat" || bad "G3.4 cron.job: $jobs"
for db in order checkout payment; do
  age="$(sql "$db" "SELECT extract(epoch FROM clock_timestamp()-emitted_at)::int FROM analytics_cdc_heartbeat WHERE id=1")"
  [ -n "$age" ] && [ "$age" -le 60 ] 2>/dev/null && ok "G3.4 $db heartbeat ${age}s old" || bad "G3.4 $db heartbeat age '$age'"
done
runs="$(sql postgres "SELECT count(*) FILTER (WHERE status='succeeded')||'/'||count(*) FROM cron.job_run_details WHERE start_time > now()-interval '5 minutes'")"
echo "      cron runs in the last 5 min (succeeded/total): $runs"

[ $fail -eq 0 ] && echo "cdc source gate: PASS" || { echo "cdc source gate: FAIL"; exit 1; }
