-- PG-02 · INHERIT vs SET vs ADMIN on a membership.
-- Pass: the catalog options and the real session behaviour agree for each.
\set ON_ERROR_STOP 1
CREATE ROLE pg02_owner NOLOGIN;
CREATE ROLE pg02_inherit NOLOGIN;
CREATE ROLE pg02_set NOLOGIN NOINHERIT;
CREATE ROLE pg02_admin NOLOGIN NOINHERIT;
CREATE ROLE pg02_other NOLOGIN;
-- A schema the owner owns; public is not writable by non-owners on PG15+.
CREATE SCHEMA app AUTHORIZATION pg02_owner;
SET ROLE pg02_owner;
CREATE TABLE app.secret (v int);
INSERT INTO app.secret VALUES (1);
RESET ROLE;
GRANT pg02_owner TO pg02_inherit WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT pg02_owner TO pg02_set     WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT pg02_owner TO pg02_admin   WITH INHERIT FALSE, SET FALSE, ADMIN TRUE;

SELECT lab_assert(
  (SELECT array_agg(e ORDER BY e) FROM (
     SELECT pg_get_userbyid(member)::text || ':' || admin_option || inherit_option || set_option AS e
       FROM pg_auth_members WHERE roleid = 'pg02_owner'::regrole) m)
  = ARRAY['pg02_admin:truefalsefalse', 'pg02_inherit:falsetruefalse', 'pg02_set:falsefalsetrue'],
  'catalog options must match the three grants');

-- INHERIT: reads without switching, cannot switch
SET SESSION AUTHORIZATION pg02_inherit;
SELECT lab_assert((SELECT v = 1 FROM app.secret), 'INHERIT member reads the owner''s table directly');
SELECT lab_assert(lab_expect_denied('SET ROLE pg02_owner') IS NOT NULL, 'INHERIT-only member cannot SET ROLE');
RESET SESSION AUTHORIZATION;

-- SET: cannot read until it switches
SET SESSION AUTHORIZATION pg02_set;
SELECT lab_assert(lab_expect_denied('SELECT v FROM app.secret') IS NOT NULL, 'SET-only member cannot read before SET ROLE');
SET ROLE pg02_owner;
SELECT lab_assert((SELECT v = 1 FROM app.secret), 'SET member reads after SET ROLE');
RESET ROLE;
RESET SESSION AUTHORIZATION;

-- ADMIN: can manage the membership, cannot read or switch
SET SESSION AUTHORIZATION pg02_admin;
SELECT lab_assert(lab_expect_denied('SELECT v FROM app.secret') IS NOT NULL, 'ADMIN-only member cannot read');
SELECT lab_assert(lab_expect_denied('SET ROLE pg02_owner') IS NOT NULL, 'ADMIN-only member cannot SET ROLE');
GRANT pg02_owner TO pg02_other;
RESET SESSION AUTHORIZATION;
SELECT lab_assert(pg_has_role('pg02_other', 'pg02_owner', 'MEMBER'), 'ADMIN member granted the role to another');
