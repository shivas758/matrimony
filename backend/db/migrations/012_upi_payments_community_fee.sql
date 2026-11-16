-- 012 — Direct UPI payments with manual verification, paid extra communities (SPEC §9.20, v2.10).
--
--  * payments: provider 'upi'; status 'submitted' (payer entered the UTR, waiting for an admin);
--    purpose 'extra_community' (an agent's ₹1000 fee for a community beyond the free three);
--    utr / submitted_at / verified_by / verified_at / reject_reason; agent_id and
--    community_request_id for agent payments. A UTR is accepted once.
--  * community_change_requests.fee_paise: 0 = free request, >0 = needs its UPI payment.
--  * account_deletion_requests: the Google Play account-deletion page (SPEC §9.20 F).
--
-- No data changes. Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/012_upi_payments_community_fee.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

-- deploy/update.sh re-runs every migration: only widen the check while it lacks
-- 'upi' — never narrow a later one (015 adds 'gift'; 'gift' rows would fail).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'payments_provider_check'
                    AND pg_get_constraintdef(oid) LIKE '%upi%') THEN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
    ALTER TABLE payments ADD CONSTRAINT payments_provider_check
      CHECK (provider IN ('mock','razorpay','waived','cash','upi'));
  END IF;
END $$;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE payments ADD CONSTRAINT payments_status_check
  CHECK (status IN ('created','submitted','paid','failed','refund_due'));

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_purpose_check;
ALTER TABLE payments ADD CONSTRAINT payments_purpose_check
  CHECK (purpose IN ('profile_registration','extra_community'));

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS agent_id INT REFERENCES agents(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS community_request_id INT REFERENCES community_change_requests(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS utr TEXT,
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by INT REFERENCES agents(id),
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reject_reason TEXT;

-- One UTR per live claim (a rejected row may be corrected with another UTR).
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_utr ON payments(utr)
  WHERE utr IS NOT NULL AND status IN ('submitted','paid');
CREATE INDEX IF NOT EXISTS idx_payments_status_submitted ON payments(submitted_at)
  WHERE status = 'submitted';
CREATE INDEX IF NOT EXISTS idx_payments_agent ON payments(agent_id) WHERE agent_id IS NOT NULL;

ALTER TABLE community_change_requests
  ADD COLUMN IF NOT EXISTS fee_paise INT NOT NULL DEFAULT 0 CHECK (fee_paise >= 0);

-- Account deletion requests from the public page /delete-account (SPEC §9.20 F, Google Play rule).
CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id SERIAL PRIMARY KEY,
  app TEXT NOT NULL CHECK (app IN ('customer','agent')),
  phone TEXT NOT NULL,
  full_name TEXT,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','done','rejected')),
  handled_by INT REFERENCES agents(id) ON DELETE SET NULL,
  handled_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_account_deletion_pending ON account_deletion_requests(created_at)
  WHERE status = 'pending';

COMMIT;
