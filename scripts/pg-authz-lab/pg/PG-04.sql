-- PG-04 · A NOINHERIT migrator that forgets SET ROLE cannot create anything.
-- Pass: CREATE is refused at the schema and no migrator-owned object exists.
\set ON_ERROR_STOP 1
CREATE ROLE pg04_owner NOLOGIN;
CREATE ROLE pg04_migrator NOLOGIN NOINHERIT;
GRANT pg04_owner TO pg04_migrator WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
ALTER DATABASE lab_pg04 OWNER TO pg04_owner;

SET SESSION AUTHORIZATION pg04_migrator;
SELECT lab_assert(lab_expect_denied('CREATE TABLE public.t (i int)') LIKE '%schema public%',
                  'CREATE without SET ROLE is refused at the schema');
SELECT lab_assert(lab_expect_denied('CREATE SCHEMA mine') LIKE '%database lab_pg04%',
                  'the migrator cannot create a schema of its own either');
RESET SESSION AUTHORIZATION;

SELECT lab_assert(NOT EXISTS (SELECT 1 FROM pg_class WHERE relowner = 'pg04_migrator'::regrole)
                  AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspowner = 'pg04_migrator'::regrole),
                  'no object is owned by the migrator');
