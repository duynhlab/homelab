-- PG-08 · SECURITY DEFINER without a fixed search_path can be hijacked.
-- Phase 4 material; kept so the review rule for definer functions has evidence.
-- Pass: the weak function runs the caller's shadow function with the owner's
-- rights; the hardened one (fixed search_path, qualified names) does not.
\set ON_ERROR_STOP 1
CREATE ROLE pg08_owner NOLOGIN;
CREATE ROLE pg08_runtime NOLOGIN;
ALTER DATABASE lab_pg08 OWNER TO pg08_owner;

SET ROLE pg08_owner;
CREATE SCHEMA app;
CREATE TABLE app.audit (who text);
CREATE FUNCTION app.normalise(t text) RETURNS text LANGUAGE sql AS 'SELECT lower(t)';
-- Weak: unqualified call, no search_path. plpgsql resolves the name at call
-- time, with the caller's search_path.
CREATE FUNCTION app.weak(t text) RETURNS text SECURITY DEFINER LANGUAGE plpgsql
  AS 'BEGIN RETURN normalise(t); END';
-- Hardened: fixed search_path and a qualified call.
CREATE FUNCTION app.hardened(t text) RETURNS text SECURITY DEFINER LANGUAGE sql
  SET search_path = pg_catalog, pg_temp
  AS 'SELECT app.normalise(t)';
REVOKE EXECUTE ON FUNCTION app.weak(text), app.hardened(text) FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO pg08_runtime;
GRANT EXECUTE ON FUNCTION app.weak(text), app.hardened(text), app.normalise(text) TO pg08_runtime;
RESET ROLE;

-- The attacker controls a schema of its own and puts it first.
CREATE SCHEMA attacker AUTHORIZATION pg08_runtime;
SET ROLE pg08_runtime;
CREATE FUNCTION attacker.normalise(t text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO app.audit VALUES (current_user);  -- needs the owner's rights
  RETURN 'hijacked';
END $$;
-- The definer resolves names with ITS rights, so the attacker opens the schema.
GRANT USAGE ON SCHEMA attacker TO PUBLIC;
GRANT EXECUTE ON FUNCTION attacker.normalise(text) TO PUBLIC;
SET search_path = attacker, app, public;
SELECT lab_assert(lab_expect_denied($$INSERT INTO app.audit VALUES ('direct')$$) IS NOT NULL,
                  'the runtime cannot write the audit table directly');
SELECT lab_assert(app.weak('X') = 'hijacked', 'the weak definer function runs the shadow function');
SELECT lab_assert(app.hardened('X') = 'x', 'the hardened function ignores the caller''s search_path');
RESET search_path;
RESET ROLE;
SELECT lab_assert((SELECT array_agg(who) FROM app.audit) = ARRAY['pg08_owner'],
                  'the hijack wrote as the owner, exactly once');
