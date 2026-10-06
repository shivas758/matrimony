-- 006: Gandharva guest mode, the ₹150 registration fee and up to 5 profiles
--      per customer (SPEC §9.12).
--
--  * customers.status gains 'guest' (signed up with phone + OTP, no agent yet);
--    customers.agent_id becomes nullable (NULL only while guest)
--  * profiles: one customer may own up to 5 (the unique index goes);
--    paid_at = when the registration fee for that profile was paid
--  * payments: one row per checkout attempt (mock now, Razorpay later)
--  * customer_interests.from_profile_id: which of the customer's profiles is
--    interested (a customer can have several now)
--
-- Existing customer profiles are grandfathered as paid (a 'waived' payment),
-- so nobody who registered before the fee loses visibility.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/006_guest_mode_payments.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

-- deploy/update.sh re-runs every migration on each deploy: the one-off
-- backfills below must only happen the first time (before paid_at exists),
-- or later unpaid profiles would be grandfathered too.
CREATE TEMP TABLE m006 ON COMMIT DROP AS
SELECT NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = current_schema() AND table_name = 'profiles'
                      AND column_name = 'paid_at') AS first_run;

-- ===== customers =====
ALTER TABLE customers ALTER COLUMN agent_id DROP NOT NULL;
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_status_check;
ALTER TABLE customers ADD CONSTRAINT customers_status_check
  CHECK (status IN ('guest','pending','active','rejected','suspended'));
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_agent_required;
ALTER TABLE customers ADD CONSTRAINT customers_agent_required
  CHECK (status = 'guest' OR agent_id IS NOT NULL);

-- ===== profiles =====
DROP INDEX IF EXISTS uq_profiles_customer;
CREATE INDEX IF NOT EXISTS idx_profiles_customer ON profiles(customer_id) WHERE customer_id IS NOT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- ===== payments =====
CREATE TABLE IF NOT EXISTS payments (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  purpose TEXT NOT NULL DEFAULT 'profile_registration' CHECK (purpose IN ('profile_registration')),
  amount_paise INT NOT NULL CHECK (amount_paise >= 0),
  currency TEXT NOT NULL DEFAULT 'INR',
  provider TEXT NOT NULL CHECK (provider IN ('mock','razorpay','waived')),
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created','paid','failed')),
  provider_order_id TEXT,
  provider_payment_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id, created_at DESC);
-- At most one successful registration payment per profile.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_profile_paid ON payments(profile_id)
  WHERE status = 'paid' AND purpose = 'profile_registration';

-- Grandfather every customer profile that exists now.
INSERT INTO payments (customer_id, profile_id, amount_paise, provider, status, paid_at, created_at)
SELECT p.customer_id, p.id, 0, 'waived', 'paid', p.created_at, p.created_at
  FROM profiles p
 WHERE p.customer_id IS NOT NULL AND p.paid_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM payments x WHERE x.profile_id = p.id AND x.status = 'paid')
   AND (SELECT first_run FROM m006);
UPDATE profiles SET paid_at = created_at
 WHERE customer_id IS NOT NULL AND paid_at IS NULL AND (SELECT first_run FROM m006);

-- ===== interests =====
ALTER TABLE customer_interests
  ADD COLUMN IF NOT EXISTS from_profile_id INT REFERENCES profiles(id) ON DELETE SET NULL;
-- Until now a customer had at most one profile: that is the interested one.
UPDATE customer_interests ci
   SET from_profile_id = p.id
  FROM profiles p
 WHERE ci.from_profile_id IS NULL AND p.customer_id = ci.customer_id AND (SELECT first_run FROM m006);
CREATE INDEX IF NOT EXISTS idx_customer_interests_from ON customer_interests(from_profile_id);

COMMIT;
