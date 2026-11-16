-- 015 — Gift codes, approved agents (10 live clients), profiles without an agent (SPEC §9.23, v2.13).
--
--  * agents.approved_at / approved_by: an agent is "approved" (sees every profile shown to their
--    communities, listed in the customers' agents directory) once they have 10 live clients or an
--    admin approves them by hand. agents.gift_codes_granted_at: the free ten were issued.
--  * gift_codes: each agent's free codes; a customer's code publishes their profile free.
--  * payments.provider gains 'gift'.
--  * profiles.uploaded_by becomes nullable: a customer fills in their profile before choosing an
--    agent (it gets its uploader and its ID when they link one). The demo flag then comes from
--    the customer.
--
-- Data, first run only: remaining 'pending' agents become 'active' (no admin activation any
-- more). Every run: admins, demo agents and agents that already have 10 live clients are approved.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/015_gift_codes_agent_approval.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

-- deploy/update.sh re-runs every migration: one-off data changes only happen
-- the first time (before agents.approved_at exists).
CREATE TEMP TABLE m015 ON COMMIT DROP AS
SELECT NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = current_schema() AND table_name = 'agents'
                      AND column_name = 'approved_at') AS first_run;

-- ===== agents =====
ALTER TABLE agents
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by INT REFERENCES agents(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS gift_codes_granted_at TIMESTAMPTZ;

-- ===== payments: provider 'gift' (never narrow a later version of the check) =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'payments_provider_check'
                    AND pg_get_constraintdef(oid) LIKE '%gift%') THEN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
    ALTER TABLE payments ADD CONSTRAINT payments_provider_check
      CHECK (provider IN ('mock','razorpay','waived','cash','upi','gift'));
  END IF;
END $$;

-- ===== gift codes =====
CREATE TABLE IF NOT EXISTS gift_codes (
  id SERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,                       -- WB-K7M2QX
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'unused' CHECK (status IN ('unused','used')),
  granted_by INT REFERENCES agents(id) ON DELETE SET NULL,   -- admin; NULL = the free ten
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at TIMESTAMPTZ,
  customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  payment_id INT REFERENCES payments(id) ON DELETE SET NULL,
  customer_name TEXT,                              -- kept after the customer / profile is gone
  profile_name TEXT
);
CREATE INDEX IF NOT EXISTS idx_gift_codes_agent ON gift_codes(agent_id, status);

-- ===== profiles without an agent =====
ALTER TABLE profiles ALTER COLUMN uploaded_by DROP NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_owner_check') THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_owner_check
      CHECK (uploaded_by IS NOT NULL OR customer_id IS NOT NULL);
  END IF;
END $$;

-- The demo flag (SPEC §9.21): the uploader's, else (no agent yet) the customer's.
-- Re-created here after 013 re-runs its older version.
CREATE OR REPLACE FUNCTION profiles_inherit_demo() RETURNS trigger AS $$
BEGIN
  NEW.is_demo := COALESCE((SELECT a.is_demo FROM agents a WHERE a.id = NEW.uploaded_by),
                          (SELECT cu.is_demo FROM customers cu WHERE cu.id = NEW.customer_id),
                          FALSE);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- ===== data =====
UPDATE agents SET status = 'active' WHERE status = 'pending' AND (SELECT first_run FROM m015);

UPDATE agents a SET approved_at = now()
 WHERE a.approved_at IS NULL
   AND (a.role = 'admin' OR a.is_demo
        OR (SELECT count(*) FROM customers cu
             WHERE cu.agent_id = a.id AND cu.status = 'active'
               AND EXISTS (SELECT 1 FROM profiles lp
                            WHERE lp.customer_id = cu.id AND lp.paid_at IS NOT NULL
                              AND lp.status <> 'hidden')) >= 10);

COMMIT;
