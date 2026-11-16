-- 014 — Report, block, terms consent (SPEC §9.22, v2.12 — Google Play UGC policy).
--
--  * reports: a customer or agent reports a profile; admins dismiss / hide / suspend.
--  * blocks: a customer or agent blocks a profile (customers: both ways).
--  * customers.terms_accepted_at / agents.terms_accepted_at: consent at signup.
--
-- No data changes. Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/014_reports_blocks_terms.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

ALTER TABLE customers ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS reports (
  id SERIAL PRIMARY KEY,
  reporter_agent_id INT REFERENCES agents(id) ON DELETE CASCADE,
  reporter_customer_id INT REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  profile_label TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN
    ('fake_profile','inappropriate_photo','offensive_content','scam_or_fraud','harassment','other')),
  details TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','actioned','dismissed')),
  action TEXT CHECK (action IN ('profile_hidden','account_suspended')),
  handled_by INT REFERENCES agents(id) ON DELETE SET NULL,
  handled_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT reports_one_reporter CHECK ((reporter_agent_id IS NULL) <> (reporter_customer_id IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_reports_open ON reports(created_at) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_reports_profile ON reports(profile_id);

CREATE TABLE IF NOT EXISTS blocks (
  id SERIAL PRIMARY KEY,
  blocker_agent_id INT REFERENCES agents(id) ON DELETE CASCADE,
  blocker_customer_id INT REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  profile_label TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT blocks_one_blocker CHECK ((blocker_agent_id IS NULL) <> (blocker_customer_id IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_blocks_agent ON blocks(blocker_agent_id, profile_id) WHERE blocker_agent_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_blocks_customer ON blocks(blocker_customer_id, profile_id) WHERE blocker_customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_blocks_profile ON blocks(profile_id);

COMMIT;
