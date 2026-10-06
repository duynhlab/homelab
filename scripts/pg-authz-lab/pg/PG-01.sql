-- PG-01 · Privilege ladder: database, schema, table, sequence.
-- Pass: each missing layer is refused at that layer, then the insert works.
\set ON_ERROR_STOP 1
CREATE ROLE pg01_owner NOLOGIN;
CREATE ROLE pg01_runtime NOLOGIN;
ALTER DATABASE lab_pg01 OWNER TO pg01_owner;
REVOKE CONNECT ON DATABASE lab_pg01 FROM PUBLIC;
SET ROLE pg01_owner;
CREATE SCHEMA app;
CREATE TABLE app.items (id bigserial PRIMARY KEY, name text NOT NULL);
RESET ROLE;

-- 1. database: no CONNECT
SELECT lab_assert(NOT has_database_privilege('pg01_runtime', 'lab_pg01', 'CONNECT'),
                  'runtime must not have CONNECT before the grant');
GRANT CONNECT ON DATABASE lab_pg01 TO pg01_runtime;

-- 2. schema: no USAGE
SET ROLE pg01_runtime;
SELECT lab_assert(lab_expect_denied($$INSERT INTO app.items (name) VALUES ('x')$$) LIKE '%schema app%',
                  'first refusal must be at the schema');
RESET ROLE;
GRANT USAGE ON SCHEMA app TO pg01_runtime;

-- 3. table: no INSERT
SET ROLE pg01_runtime;
SELECT lab_assert(lab_expect_denied($$INSERT INTO app.items (name) VALUES ('x')$$) LIKE '%table items%',
                  'second refusal must be at the table');
RESET ROLE;
GRANT INSERT ON app.items TO pg01_runtime;

-- 4. sequence: no USAGE for the bigserial default
SET ROLE pg01_runtime;
SELECT lab_assert(lab_expect_denied($$INSERT INTO app.items (name) VALUES ('x')$$) LIKE '%sequence items_id_seq%',
                  'third refusal must be at the sequence');
RESET ROLE;
GRANT USAGE ON SEQUENCE app.items_id_seq TO pg01_runtime;

SET ROLE pg01_runtime;
INSERT INTO app.items (name) VALUES ('x');
RESET ROLE;
SELECT lab_assert((SELECT count(*) = 1 FROM app.items), 'the insert must land once every layer is granted');
