-- PG-05 · A per-schema revoke cannot cancel the global PUBLIC EXECUTE default.
-- Pass: the per-schema revoke stores no default-ACL row and changes nothing;
-- the global revoke does.
\set ON_ERROR_STOP 1
CREATE ROLE pg05_owner NOLOGIN;
ALTER DATABASE lab_pg05 OWNER TO pg05_owner;

SET ROLE pg05_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE FUNCTION public.f1() RETURNS int LANGUAGE sql AS 'SELECT 1';
RESET ROLE;
SELECT lab_assert((SELECT count(*) = 0 FROM pg_default_acl WHERE defaclrole = 'pg05_owner'::regrole),
                  'the per-schema revoke stores zero default-ACL rows');
SELECT lab_assert(has_function_privilege('public', 'public.f1()', 'EXECUTE'),
                  'after the per-schema revoke PUBLIC still executes new functions');

SET ROLE pg05_owner;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE FUNCTION public.f2() RETURNS int LANGUAGE sql AS 'SELECT 2';
RESET ROLE;
SELECT lab_assert((SELECT count(*) = 1 FROM pg_default_acl WHERE defaclrole = 'pg05_owner'::regrole AND defaclnamespace = 0),
                  'the global revoke stores one global default-ACL row');
SELECT lab_assert(NOT has_function_privilege('public', 'public.f2()', 'EXECUTE'),
                  'after the global revoke PUBLIC cannot execute new functions');
