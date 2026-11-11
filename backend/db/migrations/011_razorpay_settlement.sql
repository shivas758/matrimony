-- 011 — Razorpay settlement (SPEC §9.19 B, v2.9).
--
--  * payments.status gains 'refund_due': real money that arrived for a profile
--    that was already paid (or deleted) — refund it from the Razorpay dashboard.
--  * one payments row per Razorpay order (the webhook and the safety net look
--    payments up by provider_order_id).
--
-- No data changes. Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/011_razorpay_settlement.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE payments ADD CONSTRAINT payments_status_check
  CHECK (status IN ('created','paid','failed','refund_due'));

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_razorpay_order ON payments(provider_order_id)
  WHERE provider = 'razorpay';

COMMIT;
