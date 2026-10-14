#!/bin/bash
# Applies the role catalog and the in-database grants (ADR-087). Idempotent:
# the Job runs it on every change, the CronJob every 10 minutes to undo drift.
#   ROLE_SERVICES   services whose owner/migrator roles this script owns
#   GRANT_SERVICES  services whose in-database grants this script owns
#                   (the rest are pgroles PostgresPolicies)
#   <SVC>_MIGRATOR_PASSWORD  each migrator's password, from its Secret
set -euo pipefail

export PGHOST="${PGHOST:-platform-db-rw.platform.svc.cluster.local}" PGSSLMODE="${PGSSLMODE:-require}"
export PGUSER="$DB_AUTHZ_USER" PGPASSWORD="$DB_AUTHZ_PASSWORD"
# Act as authz_admin from the first statement. Roles it creates grant it SET
# and INHERIT back (PG16+), which ALTER DEFAULT PRIVILEGES FOR ROLE needs.
AUTHZ_OPTIONS="-c role=authz_admin -c createrole_self_grant=set,inherit"
export PGOPTIONS="$AUTHZ_OPTIONS"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

retry() { # retry <tries> <what> <cmd...>
  local n=0 tries=$1 what=$2; shift 2
  until "$@" >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -ge "$tries" ] && { echo "ERROR: $what"; return 1; }
    sleep 5
  done
}

retry 60 "db_authz cannot log in to postgres" "${PSQL[@]}" -d postgres -c 'SELECT 1'

# One service's failure must not stop the others; the run still fails at the
# end so the Job (and its alert) reports it.
failed=()

for svc in $ROLE_SERVICES; do
  echo "roles: $svc"
  if ! "${PSQL[@]}" -d postgres -v svc="$svc" -f "${AUTHZ_DIR:-/authz}"/roles.sql; then
    failed+=("roles/$svc"); continue
  fi

  # Set the password only when it no longer logs in: an ALTER every run would
  # rewrite the verifier and fill the audit log.
  pw_var="${svc^^}_MIGRATOR_PASSWORD"
  if ! PGOPTIONS='' PGUSER="${svc}_migrator" PGPASSWORD="${!pw_var}" \
      psql -X -d "$svc" -Atc 'SELECT 1' >/dev/null 2>&1; then
    echo "  setting ${svc}_migrator password"
    printf "ALTER ROLE %s PASSWORD :'pw';\n" "${svc}_migrator" \
      | "${PSQL[@]}" -d postgres -v pw="${!pw_var}"
  fi
done

for svc in $GRANT_SERVICES; do
  echo "grants: $svc"
  # CNPG creates the database once its owner exists (the roles step above).
  if ! retry 120 "database $svc does not exist" \
      "${PSQL[@]}" -d postgres -Atc "SELECT 1/count(*) FROM pg_database WHERE datname = '$svc'" \
    || ! "${PSQL[@]}" -d "$svc" -v svc="$svc" -f "${AUTHZ_DIR:-/authz}"/grants.sql; then
    failed+=("grants/$svc")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "ERROR: authz failed for: ${failed[*]}"
  exit 1
fi
echo "authz applied: roles [$ROLE_SERVICES] grants [$GRANT_SERVICES]"
