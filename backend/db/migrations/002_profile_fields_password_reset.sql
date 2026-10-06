-- 002: extra profile fields, two new masters, and the forgot-password flow.
--
--  * complexions master (Very Fair … Dark) → profiles.complexion_id
--  * countries master (NRI countries)        → profiles.nri_country_id
--  * profiles: gothram, work_place, education_details, profession_details,
--              weight_kg, is_nri, nri_place,
--              father_name/phone, mother_name/phone   (PROTECTED, like contact_*)
--    city/state now mean "native place" and are PROTECTED too (SPEC §2).
--  * agents.must_change_password + password_reset_requests (forgot password)
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/002_profile_fields_password_reset.sql
-- Fresh installs get the same DDL from schema.sql.

BEGIN;

-- ===== new masters =====
CREATE TABLE IF NOT EXISTS complexions (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO complexions (name, sort_order) VALUES
 ('Very Fair',1),('Fair',2),('Wheatish',3),('Wheatish Brown',4),('Dark',5)
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS countries (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO countries (name, sort_order) VALUES
 ('United States',1),('United Kingdom',2),('Australia',3),('Canada',4),('Germany',5),
 ('France',6),('Russia',7),('United Arab Emirates',8),('Saudi Arabia',9),('Qatar',10),
 ('Kuwait',11),('Oman',12),('Bahrain',13),('Singapore',14),('Malaysia',15),
 ('New Zealand',16),('Ireland',17),('Netherlands',18),('Switzerland',19),('Sweden',20),
 ('Italy',21),('Japan',22),('South Africa',23),('Other',99)
ON CONFLICT (name) DO NOTHING;

-- ===== profiles =====
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS gothram TEXT,
  ADD COLUMN IF NOT EXISTS work_place TEXT,
  ADD COLUMN IF NOT EXISTS education_details TEXT,
  ADD COLUMN IF NOT EXISTS profession_details TEXT,
  ADD COLUMN IF NOT EXISTS complexion_id INT REFERENCES complexions(id),
  ADD COLUMN IF NOT EXISTS weight_kg INT,
  ADD COLUMN IF NOT EXISTS is_nri BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS nri_country_id INT REFERENCES countries(id),
  ADD COLUMN IF NOT EXISTS nri_place TEXT,
  -- PROTECTED: parents' names and phones follow the contact_* rules.
  ADD COLUMN IF NOT EXISTS father_name TEXT,
  ADD COLUMN IF NOT EXISTS father_phone TEXT,
  ADD COLUMN IF NOT EXISTS mother_name TEXT,
  ADD COLUMN IF NOT EXISTS mother_phone TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_nri ON profiles(is_nri, nri_country_id);
CREATE INDEX IF NOT EXISTS idx_profiles_height ON profiles(height_cm);

-- ===== forgot password =====
ALTER TABLE agents
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS password_reset_requests (
  id SERIAL PRIMARY KEY,
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_password_reset_requests_agent ON password_reset_requests(agent_id, status);

COMMIT;
