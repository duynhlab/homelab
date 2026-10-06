-- PG-03 · Owner default privileges apply to objects created after SET ROLE.
-- Pass: new table, sequence and function get the policy ACL; PUBLIC has no
-- EXECUTE on the new function.
\set ON_ERROR_STOP 1
CREATE ROLE pg03_owner NOLOGIN;
CREATE ROLE pg03_migrator NOLOGIN NOINHERIT;
CREATE ROLE pg03_runtime NOLOGIN;
GRANT pg03_owner TO pg03_migrator WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
ALTER DATABASE lab_pg03 OWNER TO pg03_owner;

-- The migration, as the migrator: switch, then the 0001_authorization snippet.
SET SESSION AUTHORIZATION pg03_migrator;
SET ROLE pg03_owner;
GRANT USAGE ON SCHEMA public TO pg03_runtime;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pg03_runtime;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO pg03_runtime;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- A later migration:
CREATE TABLE public.orders (id bigserial PRIMARY KEY, total int NOT NULL);
CREATE FUNCTION public.order_total(i bigint) RETURNS int LANGUAGE sql AS 'SELECT total FROM public.orders WHERE id = i';
RESET ROLE;
RESET SESSION AUTHORIZATION;

SELECT lab_assert(pg_get_userbyid((SELECT relowner FROM pg_class WHERE oid = 'public.orders'::regclass)) = 'pg03_owner',
                  'the table belongs to the owner, not the migrator');
SELECT lab_assert(has_table_privilege('pg03_runtime', 'public.orders', 'SELECT,INSERT,UPDATE,DELETE'),
                  'runtime has CRUD on the new table');
SELECT lab_assert(NOT has_table_privilege('pg03_runtime', 'public.orders', 'TRUNCATE')
                  AND NOT has_table_privilege('pg03_runtime', 'public.orders', 'REFERENCES'),
                  'runtime has nothing beyond CRUD');
SELECT lab_assert(has_sequence_privilege('pg03_runtime', 'public.orders_id_seq', 'USAGE,SELECT'),
                  'runtime can use the new sequence');
SELECT lab_assert(NOT has_function_privilege('public', 'public.order_total(bigint)', 'EXECUTE'),
                  'PUBLIC has no EXECUTE on the new function');

SET SESSION AUTHORIZATION pg03_runtime;
INSERT INTO public.orders (total) VALUES (42);
SELECT lab_assert(lab_expect_denied('DROP TABLE public.orders') IS NOT NULL, 'runtime cannot drop the table');
SELECT lab_assert(lab_expect_denied('ALTER TABLE public.orders ADD COLUMN x int') IS NOT NULL, 'runtime cannot alter the table');
SELECT lab_assert(lab_expect_denied('CREATE TABLE public.evil (i int)') IS NOT NULL, 'runtime cannot create in the schema');
RESET SESSION AUTHORIZATION;
