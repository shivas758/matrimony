-- 009: one profile per customer (SPEC §9.17) — replaces 006's "up to 5".
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/009_one_profile_per_customer.sql
-- Fresh installs get the same index from schema.sql. Safe to run twice (deploy/update.sh
-- re-runs every migration on each deploy).
--
-- The API refuses a second profile (409 profile_limit); this index makes a
-- double-tapped "Save" unable to sneak one in. If any customer already owns
-- several profiles the index is skipped with a NOTICE (nothing is deleted) —
-- resolve them by hand, then re-run this file. There were none on 2026-10-19.
-- The name differs from 006's dropped `uq_profiles_customer`, so re-running
-- 006 never removes it.

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM profiles WHERE customer_id IS NOT NULL GROUP BY customer_id HAVING count(*) > 1
  ) THEN
    RAISE NOTICE '009: some customers own several profiles — uq_profiles_one_per_customer NOT created';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_one_per_customer
      ON profiles(customer_id) WHERE customer_id IS NOT NULL;
  END IF;
END $$;

COMMIT;
