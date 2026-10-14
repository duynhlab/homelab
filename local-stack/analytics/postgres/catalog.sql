-- This script runs only on a fresh, disposable Phase 0 database.
CREATE ROLE peerdb_catalog LOGIN PASSWORD 'peerdb-catalog-local'
  NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE peerdb_catalog OWNER peerdb_catalog;
REVOKE CONNECT ON DATABASE peerdb_catalog FROM PUBLIC;
CREATE EXTENSION pg_cron;
CREATE ROLE analytics_heartbeat LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT CONNECT ON DATABASE postgres TO analytics_heartbeat;
GRANT USAGE ON SCHEMA cron TO analytics_heartbeat;
-- Background workers need LOGIN but no password or remote heartbeat connection.
