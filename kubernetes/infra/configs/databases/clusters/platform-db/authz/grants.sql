-- In-database grants for one service (ADR-087), run in database <svc> as
-- authz_admin, which inherits <svc>_owner. pgroles owns this layer for the
-- other services; the statements are the same.
\set owner :svc _owner
\set migrator :svc _migrator
\set runtime :svc _runtime
SELECT set_config('authz.owner', :'owner', false),
       set_config('authz.runtime', :'runtime', false) \g /dev/null

GRANT CONNECT ON DATABASE :"svc" TO :"runtime", :"migrator";
GRANT USAGE ON SCHEMA public TO :"runtime";

-- Every table and sequence a later migration creates.
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"runtime";
-- Global, not IN SCHEMA: only a global entry cancels the built-in PUBLIC
-- EXECUTE on functions.
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Objects that exist already (a migration that ran before the defaults, or
-- drift), and never the migration bookkeeping table.
DO $$
DECLARE
  v_owner   text := current_setting('authz.owner');
  v_runtime text := current_setting('authz.runtime');
  o record;
BEGIN
  FOR o IN
    SELECT c.relname, c.relkind
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'S')
       AND pg_get_userbyid(c.relowner) = v_owner
  LOOP
    -- Exact: revoke, then grant the declared set. One transaction, so the
    -- runtime never sees the gap.
    EXECUTE format('REVOKE ALL ON %s public.%I FROM %I',
                   CASE o.relkind WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, o.relname, v_runtime);
    IF o.relname = 'schema_migrations' THEN
      NULL;
    ELSIF o.relkind = 'S' THEN
      EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO %I', o.relname, v_runtime);
    ELSE
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', o.relname, v_runtime);
    END IF;
  END LOOP;
END $$;
