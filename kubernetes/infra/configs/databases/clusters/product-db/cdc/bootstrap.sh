#!/bin/bash
# CDC source bootstrap on product-db (RFC-0030 / ADR-068). Idempotent; the Job
# runs it on change, the CronJob every 10 minutes to undo drift.
#   1. as db_authz -> authz_admin -> <db>_owner: the heartbeat table and its
#      single row in each source database (the owner owns every object there);
#   2. as analytics_heartbeat in `postgres`: one 30-second pg_cron job per
#      source database plus a daily cleanup of its own run history.
set -euo pipefail
export PGHOST=product-db-rw.product.svc.cluster.local PGSSLMODE=verify-full
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

for db in $SOURCES; do
  echo "heartbeat table: $db"
  PGUSER="$DB_AUTHZ_USER" PGPASSWORD="$DB_AUTHZ_PASSWORD" \
  PGOPTIONS="-c role=authz_admin" "${PSQL[@]}" -d "$db" <<SQL
SET ROLE ${db}_owner;
CREATE TABLE IF NOT EXISTS public.analytics_cdc_heartbeat (
  id smallint PRIMARY KEY CHECK (id = 1),
  emitted_at timestamptz NOT NULL
);
INSERT INTO public.analytics_cdc_heartbeat VALUES (1, clock_timestamp())
  ON CONFLICT (id) DO NOTHING;
SQL
done

echo "cron jobs as analytics_heartbeat"
export PGUSER="$HEARTBEAT_USER" PGPASSWORD="$HEARTBEAT_PASSWORD"
for db in $SOURCES; do
  # Upserts by job name for the same user. No username argument: pg_cron
  # 1.6.8 demands a superuser whenever one is passed, even our own; the job
  # belongs to the caller, analytics_heartbeat.
  "${PSQL[@]}" -d postgres -v db="$db" <<'SQL'
SELECT cron.schedule_in_database('analytics-' || :'db', '30 seconds',
  'INSERT INTO public.analytics_cdc_heartbeat VALUES (1, clock_timestamp()) '
  || 'ON CONFLICT (id) DO UPDATE SET emitted_at = EXCLUDED.emitted_at',
  :'db') \g /dev/null
SQL
done
"${PSQL[@]}" -d postgres <<'SQL'
SELECT cron.schedule('analytics-history-cleanup', '0 3 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$) \g /dev/null
SELECT jobname, schedule, database, username, active FROM cron.job ORDER BY jobname;
SQL
