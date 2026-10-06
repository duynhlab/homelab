-- PG-06 · Default privileges do not reach existing objects; a backfill does.
-- Reference only on this platform (greenfield cutover), kept because a cluster
-- that already holds data needs it.
-- Pass: an existing table and a new table converge on the same runtime rights.
\set ON_ERROR_STOP 1
CREATE ROLE pg06_owner NOLOGIN;
CREATE ROLE pg06_runtime NOLOGIN;
ALTER DATABASE lab_pg06 OWNER TO pg06_owner;

SET ROLE pg06_owner;
CREATE TABLE public.legacy (i int);
GRANT USAGE ON SCHEMA public TO pg06_runtime;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pg06_runtime;
RESET ROLE;
SELECT lab_assert(NOT has_table_privilege('pg06_runtime', 'public.legacy', 'SELECT'),
                  'a default added later does not reach the existing table');

SET ROLE pg06_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pg06_runtime;
CREATE TABLE public.canary (i int);
RESET ROLE;

SELECT lab_assert(
  (SELECT array_agg(privilege_type ORDER BY privilege_type) FROM information_schema.role_table_grants
    WHERE grantee = 'pg06_runtime' AND table_name = 'legacy')
  = (SELECT array_agg(privilege_type ORDER BY privilege_type) FROM information_schema.role_table_grants
    WHERE grantee = 'pg06_runtime' AND table_name = 'canary'),
  'the backfilled table and the new table carry the same runtime rights');
SELECT lab_assert(
  (SELECT count(*) = 4 FROM information_schema.role_table_grants WHERE grantee = 'pg06_runtime' AND table_name = 'canary'),
  'the runtime has exactly the four CRUD rights');
