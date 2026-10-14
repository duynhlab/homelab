-- Role catalog for one service (ADR-088), run in `postgres` as authz_admin.
--   <svc>_owner     NOLOGIN; owns the database and every object in it
--   <svc>_migrator  LOGIN NOINHERIT; becomes the owner at login (role=)
-- The runtime login is a CNPG DatabaseRole and is not touched here.
\set owner :svc _owner
\set migrator :svc _migrator
SELECT set_config('authz.owner', :'owner', false),
       set_config('authz.migrator', :'migrator', false) \g /dev/null

SELECT format('CREATE ROLE %I', :'owner')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'owner') \gexec
SELECT format('CREATE ROLE %I', :'migrator')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'migrator') \gexec

-- CREATEDB, REPLICATION and BYPASSRLS default to false and only a holder of
-- the attribute (a superuser) can change them, so they are not restated.
ALTER ROLE :"owner" NOLOGIN INHERIT NOCREATEROLE CONNECTION LIMIT -1;
ALTER ROLE :"migrator" LOGIN NOINHERIT NOCREATEROLE CONNECTION LIMIT -1;
COMMENT ON ROLE :"owner" IS 'Owns the service schema; nobody logs in (ADR-088)';
COMMENT ON ROLE :"migrator" IS 'Runs migrations; becomes the owner at login (ADR-088)';

-- The migrator acts as the owner without any SET ROLE in service code.
ALTER ROLE :"migrator" RESET ALL;
ALTER ROLE :"migrator" SET role = :'owner';
GRANT :"owner" TO :"migrator" WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

-- Exact membership: only migrator -> owner and authz_admin's creator edges.
DO $$
DECLARE
  v_owner    text := current_setting('authz.owner');
  v_migrator text := current_setting('authz.migrator');
  e record;
BEGIN
  FOR e IN
    SELECT r.rolname AS role, m.rolname AS member, g.rolname AS grantor
      FROM pg_auth_members a
      JOIN pg_roles r ON r.oid = a.roleid
      JOIN pg_roles m ON m.oid = a.member
      JOIN pg_roles g ON g.oid = a.grantor
     WHERE (r.rolname IN (v_owner, v_migrator) OR m.rolname IN (v_owner, v_migrator))
       AND m.rolname <> 'authz_admin'
       AND NOT (r.rolname = v_owner AND m.rolname = v_migrator AND g.rolname = 'authz_admin')
  LOOP
    RAISE WARNING 'revoking undeclared membership % -> % (granted by %)', e.member, e.role, e.grantor;
    EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', e.role, e.member, e.grantor);
  END LOOP;

  -- Fail loudly when the state still differs: a revoke that PostgreSQL
  -- skipped (grantor out of reach) or options GRANT did not rewrite.
  IF EXISTS (
    SELECT FROM pg_auth_members a
      JOIN pg_roles r ON r.oid = a.roleid JOIN pg_roles m ON m.oid = a.member
     WHERE (r.rolname IN (v_owner, v_migrator) OR m.rolname IN (v_owner, v_migrator))
       AND m.rolname <> 'authz_admin'
       AND NOT (r.rolname = v_owner AND m.rolname = v_migrator
                AND NOT a.admin_option AND NOT a.inherit_option AND a.set_option))
  OR NOT EXISTS (
    SELECT FROM pg_auth_members a
      JOIN pg_roles r ON r.oid = a.roleid JOIN pg_roles m ON m.oid = a.member
     WHERE r.rolname = v_owner AND m.rolname = v_migrator)
  THEN
    RAISE EXCEPTION 'membership of % / % is not the declared shape', v_owner, v_migrator;
  END IF;
END $$;
