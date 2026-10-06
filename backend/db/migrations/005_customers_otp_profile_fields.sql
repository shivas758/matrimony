-- 005: Gandharva customer app, OTP signups, registration-form fields and the
--      new "on request" visibility split (SPEC §9).
--
--  * occupation_types master; countries gains 'India' (nationality / birth /
--    work / education countries all use the countries master now)
--  * agents.city (shown in the customer-facing agent directory) and
--    agents.registration_token (the per-agent public form link /r/:token)
--  * profiles: nationality_id, birth_state, birth_country_id,
--    occupation_type_id, other_income, work_country_id, father_occupation,
--    mother_occupation, elder/younger sisters/brothers, property_share,
--    property_details, customer_id (the Gandharva account that owns it)
--  * profile_education_levels: the registration form's education table
--    (below 10th / 10th / intermediate / graduation / post graduation, each
--    with free text and a country)
--  * customers: Gandharva accounts, attached to one agent, pending until the
--    agent approves
--  * otp_codes: one-time codes for agent signup and customer login
--  * customer_interests: "I'm interested" marks, decided by the target
--    profile's uploader; acceptance unlocks the on-request fields for 15 days
--  * agent_change_requests: a customer asking to move to another agent,
--    approved by the CURRENT agent
--
-- Visibility change (no DDL, see SPEC §3): birth_place, work_place, nri_place,
-- family_details and every siblings column join the PROTECTED set.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/005_customers_otp_profile_fields.sql
-- Fresh installs get the same DDL from schema.sql.

BEGIN;

-- ===== masters =====
CREATE TABLE IF NOT EXISTS occupation_types (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO occupation_types (name, sort_order) VALUES
 ('Private job',1),('Government job',2),('Business',3),('Self-employed',4),
 ('Professional (Doctor / Lawyer / CA)',5),('Farmer / Agriculture',6),('Student',7),
 ('Not working',8),('Other',99)
ON CONFLICT (name) DO NOTHING;

-- India first: nationality, birth country, work country and education
-- country all pick from this list now, not only NRI countries.
INSERT INTO countries (name, sort_order) VALUES ('India', 0)
ON CONFLICT (name) DO NOTHING;

-- ===== agents =====
ALTER TABLE agents
  ADD COLUMN IF NOT EXISTS city TEXT,
  -- Volatile default: Postgres evaluates it per existing row, so every agent
  -- gets a distinct link the moment the column appears.
  ADD COLUMN IF NOT EXISTS registration_token TEXT UNIQUE DEFAULT encode(gen_random_bytes(12), 'hex');
UPDATE agents SET registration_token = encode(gen_random_bytes(12), 'hex') WHERE registration_token IS NULL;

-- ===== customers (Gandharva accounts) =====
CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,               -- login id; verified by OTP
  agent_id INT NOT NULL REFERENCES agents(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','active','rejected','suspended')),
  source TEXT NOT NULL DEFAULT 'app' CHECK (source IN ('app','form')),
  phone_verified_at TIMESTAMPTZ,            -- set on the first successful OTP login
  approved_by INT REFERENCES agents(id),
  approved_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_agent_status ON customers(agent_id, status);

-- ===== profiles =====
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS nationality_id INT REFERENCES countries(id),
  ADD COLUMN IF NOT EXISTS birth_state TEXT,
  ADD COLUMN IF NOT EXISTS birth_country_id INT REFERENCES countries(id),
  ADD COLUMN IF NOT EXISTS occupation_type_id INT REFERENCES occupation_types(id),
  ADD COLUMN IF NOT EXISTS other_income TEXT,
  ADD COLUMN IF NOT EXISTS work_country_id INT REFERENCES countries(id),
  -- PROTECTED, like the parents' names/phones.
  ADD COLUMN IF NOT EXISTS father_occupation TEXT,
  ADD COLUMN IF NOT EXISTS mother_occupation TEXT,
  ADD COLUMN IF NOT EXISTS elder_sisters INT CHECK (elder_sisters IS NULL OR (elder_sisters >= 0 AND elder_sisters <= 20)),
  ADD COLUMN IF NOT EXISTS younger_sisters INT CHECK (younger_sisters IS NULL OR (younger_sisters >= 0 AND younger_sisters <= 20)),
  ADD COLUMN IF NOT EXISTS elder_brothers INT CHECK (elder_brothers IS NULL OR (elder_brothers >= 0 AND elder_brothers <= 20)),
  ADD COLUMN IF NOT EXISTS younger_brothers INT CHECK (younger_brothers IS NULL OR (younger_brothers >= 0 AND younger_brothers <= 20)),
  ADD COLUMN IF NOT EXISTS property_share TEXT,
  ADD COLUMN IF NOT EXISTS property_details TEXT,
  -- The Gandharva account this profile belongs to (one profile per customer).
  ADD COLUMN IF NOT EXISTS customer_id INT REFERENCES customers(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_customer ON profiles(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_work_country ON profiles(work_country_id);
CREATE INDEX IF NOT EXISTS idx_profiles_occupation_type ON profiles(occupation_type_id);

-- Registration form: education by level, each with a country.
CREATE TABLE IF NOT EXISTS profile_education_levels (
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  level TEXT NOT NULL CHECK (level IN ('below_10th','10th','intermediate','graduation','post_graduation')),
  details TEXT,                             -- school / board / degree / college
  country_id INT REFERENCES countries(id),
  PRIMARY KEY (profile_id, level)
);

-- ===== OTP =====
CREATE TABLE IF NOT EXISTS otp_codes (
  id SERIAL PRIMARY KEY,
  phone TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('agent_signup','customer_login')),
  code_hash TEXT NOT NULL,                  -- sha256(secret + phone + purpose + code)
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_otp_codes_phone ON otp_codes(phone, purpose, created_at DESC);

-- ===== interests =====
CREATE TABLE IF NOT EXISTS customer_interests (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','declined','withdrawn','revoked')),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ,
  -- Set on acceptance (decided_at + 15 days): while in the future the
  -- customer sees the profile's on-request fields.
  access_expires_at TIMESTAMPTZ,
  UNIQUE (customer_id, profile_id)
);
CREATE INDEX IF NOT EXISTS idx_customer_interests_profile ON customer_interests(profile_id, status);

-- ===== agent change =====
CREATE TABLE IF NOT EXISTS agent_change_requests (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  from_agent_id INT NOT NULL REFERENCES agents(id),
  to_agent_id INT NOT NULL REFERENCES agents(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_agent_change_requests_customer ON agent_change_requests(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_agent_change_requests_from ON agent_change_requests(from_agent_id, status);

COMMIT;
