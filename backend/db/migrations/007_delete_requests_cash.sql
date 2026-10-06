-- 007: deleting a paid Gandharva profile needs the agent's approval, and
--      agents can record a registration fee paid in cash (SPEC §9.13).
--
--  * payments.provider gains 'cash'; payments.recorded_by / note (who took the cash)
--  * profile_delete_requests: a customer asks, their agent (or an admin) decides
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/007_delete_requests_cash.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
ALTER TABLE payments ADD CONSTRAINT payments_provider_check
  CHECK (provider IN ('mock','razorpay','waived','cash'));
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS recorded_by INT REFERENCES agents(id),
  ADD COLUMN IF NOT EXISTS note TEXT;

CREATE TABLE IF NOT EXISTS profile_delete_requests (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  profile_name TEXT NOT NULL,               -- kept after the profile is gone
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_delete_pending ON profile_delete_requests(profile_id)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_profile_delete_requests_customer ON profile_delete_requests(customer_id, status);

COMMIT;
