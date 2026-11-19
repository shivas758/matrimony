-- 016 — Customer passwords, OTP password reset for agents and customers (SPEC §9.24, v2.14).
--
--  * customers.password_hash (bcrypt) / password_set_at: Wedbook Matrimony logs in with mobile +
--    password; the OTP is used once at signup and for "Forgot password?".
--  * otp_codes.purpose gains 'agent_reset' and 'customer_reset'.
--
-- Data, first run only (before customers.password_hash exists): every existing customer gets the
-- password 123456 (the owner's choice; no forced change). The hash below is bcrypt('123456', 10).
-- Customers created later without a password (the agent's web form, apps before 3.5.0) set one
-- through "Forgot password?" — later runs never touch them.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/016_customer_passwords_otp_reset.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

-- deploy/update.sh re-runs every migration: the 123456 backfill happens only the first time.
CREATE TEMP TABLE m016 ON COMMIT DROP AS
SELECT NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = current_schema() AND table_name = 'customers'
                      AND column_name = 'password_hash') AS first_run;

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS password_set_at TIMESTAMPTZ;

UPDATE customers
   SET password_hash = '$2b$10$JdXLuL5UGq9bylvMzetW1ugpK.oLs.x/g1C/pte1MGz2TlNGkxX2e'
 WHERE password_hash IS NULL AND (SELECT first_run FROM m016);

-- ===== otp_codes: the reset purposes (never narrow a later version of the check) =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'otp_codes_purpose_check'
                    AND pg_get_constraintdef(oid) LIKE '%customer_reset%') THEN
    ALTER TABLE otp_codes DROP CONSTRAINT IF EXISTS otp_codes_purpose_check;
    ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
      CHECK (purpose IN ('agent_signup','customer_login','agent_reset','customer_reset'));
  END IF;
END $$;

COMMIT;
