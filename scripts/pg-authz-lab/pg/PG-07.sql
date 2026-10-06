-- PG-07 · Row-level security: USING, WITH CHECK, owner bypass, FORCE.
-- Phase 4 material (only with a real multi-tenant need); kept in the lab so the
-- behaviour is known before anyone reaches for it.
-- Pass: the runtime sees and writes only its tenant; the owner bypasses RLS
-- until FORCE ROW LEVEL SECURITY.
\set ON_ERROR_STOP 1
CREATE ROLE pg07_owner NOLOGIN;
CREATE ROLE pg07_runtime NOLOGIN;
ALTER DATABASE lab_pg07 OWNER TO pg07_owner;

SET ROLE pg07_owner;
CREATE TABLE public.notes (tenant text NOT NULL, body text);
INSERT INTO public.notes VALUES ('a', 'a1'), ('b', 'b1');
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.notes
  USING (tenant = current_setting('app.tenant', true))
  WITH CHECK (tenant = current_setting('app.tenant', true));
GRANT USAGE ON SCHEMA public TO pg07_runtime;
GRANT SELECT, INSERT ON public.notes TO pg07_runtime;
RESET ROLE;

SET ROLE pg07_runtime;
SET app.tenant = 'a';
SELECT lab_assert((SELECT array_agg(body) FROM public.notes) = ARRAY['a1'], 'the runtime reads only its tenant');
INSERT INTO public.notes VALUES ('a', 'a2');
DO $$
BEGIN
  INSERT INTO public.notes VALUES ('b', 'forged');
  RAISE EXCEPTION 'LAB FAIL: WITH CHECK let a cross-tenant write through';
EXCEPTION WHEN insufficient_privilege THEN NULL;  -- 42501: new row violates row-level security policy
END $$;
RESET app.tenant;
RESET ROLE;

SET ROLE pg07_owner;
SET app.tenant = 'a';
SELECT lab_assert((SELECT count(*) = 3 FROM public.notes), 'the owner bypasses RLS by default');
RESET ROLE;
ALTER TABLE public.notes FORCE ROW LEVEL SECURITY;
SET ROLE pg07_owner;
SELECT lab_assert((SELECT count(*) = 2 FROM public.notes), 'FORCE applies the policy to the owner too');
RESET app.tenant;
RESET ROLE;
