-- Loaded into template1 before any experiment, so every lab database has it.
-- Each experiment calls these as the role under test (SET ROLE /
-- SET SESSION AUTHORIZATION); EXECUTE stays granted to PUBLIC on these two.

-- Run stmt and require "permission denied" (SQLSTATE 42501). Returns the
-- server message so the experiment can check which layer refused.
CREATE FUNCTION public.lab_expect_denied(stmt text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'LAB FAIL: expected permission denied, it succeeded: %', stmt;
EXCEPTION WHEN insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

CREATE FUNCTION public.lab_assert(ok boolean, what text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN
    RAISE EXCEPTION 'LAB FAIL: %', what;
  END IF;
END $$;
