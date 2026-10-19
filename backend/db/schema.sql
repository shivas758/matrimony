-- Matrimony Agents App — PostgreSQL 16 schema
-- Applied automatically on first container start (mounted into docker-entrypoint-initdb.d)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ===== Master tables =====
CREATE TABLE communities (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE professions (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE educations (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE marital_statuses (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE zodiac_signs (
  id SERIAL PRIMARY KEY,
  english_name TEXT NOT NULL UNIQUE,
  indian_name TEXT NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE nakshatrams (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Skin complexion (Indian matrimony convention). Also in db/migrations/002_*.sql.
CREATE TABLE complexions (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Countries an NRI profile can live in. Admin extends the list from the app.
CREATE TABLE countries (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Religion. Also in db/migrations/004_*.sql.
CREATE TABLE religions (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Languages: one list serves both mother tongue and known languages.
CREATE TABLE languages (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Food habit (Vegetarian, Non-Vegetarian, Eggetarian, ...).
CREATE TABLE food_habits (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Occupation type (Private job, Government job, Business, ...). Also in db/migrations/005_*.sql.
CREATE TABLE occupation_types (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Subcastes belong to exactly one community. Agents create them by typing on
-- the profile form (find-or-create, case-insensitive); admins manage them from
-- the master editor. Not seeded. (Also in db/migrations/001_subcastes.sql.)
CREATE TABLE subcastes (
  id SERIAL PRIMARY KEY,
  community_id INT NOT NULL REFERENCES communities(id),
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (community_id, name)
);
CREATE UNIQUE INDEX uq_subcastes_community_lower_name ON subcastes (community_id, lower(name));

-- ===== Agents =====
CREATE TABLE agents (
  id SERIAL PRIMARY KEY,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  agency_name TEXT,
  role TEXT NOT NULL DEFAULT 'agent' CHECK (role IN ('agent','admin')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended')),
  -- Set when an admin hands out a temporary password; every data route is
  -- blocked (403 password_change_required) until the agent picks a new one.
  must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
  city TEXT,                   -- shown in the customer-facing agent directory (SPEC §9)
  -- Per-agent public registration link: /r/:token (SPEC §9.3).
  registration_token TEXT UNIQUE DEFAULT encode(gen_random_bytes(12), 'hex'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===== Customers (Gandharva app accounts, SPEC §9) =====
-- A customer signs up as a 'guest' (phone + OTP, no agent), links one agent
-- and is 'pending' until that agent approves (SPEC §9.12). Login is phone +
-- OTP (no password). One profile per customer (profiles.customer_id; SPEC §9.17).
CREATE TABLE customers (
  id SERIAL PRIMARY KEY,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  agent_id INT REFERENCES agents(id),        -- NULL only while guest
  status TEXT NOT NULL DEFAULT 'pending'
    CONSTRAINT customers_status_check CHECK (status IN ('guest','pending','active','rejected','suspended')),
  source TEXT NOT NULL DEFAULT 'app' CHECK (source IN ('app','form')),
  phone_verified_at TIMESTAMPTZ,
  approved_by INT REFERENCES agents(id),
  approved_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT customers_agent_required CHECK (status = 'guest' OR agent_id IS NOT NULL)
);
CREATE INDEX idx_customers_agent_status ON customers(agent_id, status);

-- One-time codes for agent signup and customer login (SPEC §9.1).
CREATE TABLE otp_codes (
  id SERIAL PRIMARY KEY,
  phone TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('agent_signup','customer_login')),
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_codes_phone ON otp_codes(phone, purpose, created_at DESC);

-- "Forgot password" (SPEC §4 Auth). The agent asks from the login screen; an
-- admin sees the name + phone, verifies out of band, and sets a temporary
-- password (POST /admin/password-resets/:id/approve).
CREATE TABLE password_reset_requests (
  id SERIAL PRIMARY KEY,
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ
);
CREATE INDEX idx_password_reset_requests_agent ON password_reset_requests(agent_id, status);

CREATE TABLE agent_communities (
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  community_id INT NOT NULL REFERENCES communities(id),
  PRIMARY KEY (agent_id, community_id)
);

CREATE TABLE community_change_requests (
  id SERIAL PRIMARY KEY,
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  community_id INT NOT NULL REFERENCES communities(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===== Profiles =====
CREATE TABLE profiles (
  id SERIAL PRIMARY KEY,
  uploaded_by INT NOT NULL REFERENCES agents(id),
  full_name TEXT NOT NULL,
  gender TEXT NOT NULL CHECK (gender IN ('bride','groom')),
  dob DATE NOT NULL,
  height_cm INT,
  marital_status_id INT REFERENCES marital_statuses(id),
  community_id INT NOT NULL REFERENCES communities(id),
  subcaste_id INT REFERENCES subcastes(id),  -- must belong to community_id (API-enforced)
  gothram TEXT,
  education_id INT REFERENCES educations(id),
  education_details TEXT,      -- free text, e.g. "B.Tech CSE, JNTU 2018"
  profession_id INT REFERENCES professions(id),
  profession_details TEXT,     -- free text, e.g. "Senior developer at TCS"
  work_place TEXT,             -- PROTECTED since 005: the exact work place is "on request"
  work_country_id INT REFERENCES countries(id),   -- public coarse location (with nri_country)
  occupation_type_id INT REFERENCES occupation_types(id),
  income_text TEXT,
  other_income TEXT,
  nationality_id INT REFERENCES countries(id),
  weight_kg INT,
  complexion_id INT REFERENCES complexions(id),
  is_nri BOOLEAN NOT NULL DEFAULT FALSE,
  nri_country_id INT REFERENCES countries(id),
  nri_place TEXT,              -- city / area abroad, only when is_nri
  zodiac_id INT REFERENCES zodiac_signs(id),
  nakshatram_id INT REFERENCES nakshatrams(id),
  birth_time TIME,             -- horoscope: time of birth (public, like star/rasi)
  birth_place TEXT,            -- PROTECTED since 005 (with birth_state / birth_country_id)
  birth_state TEXT,
  birth_country_id INT REFERENCES countries(id),
  religion_id INT REFERENCES religions(id),
  mother_tongue_id INT REFERENCES languages(id),
  food_habit_id INT REFERENCES food_habits(id),
  about TEXT,
  -- PROTECTED FIELDS ("on request", SPEC §3.2): never in list APIs, shares,
  -- downloads, or public pages. Shown in-app only to the uploader, admins, an
  -- approved contact request, or (Gandharva) a customer whose interest was accepted.
  has_siblings BOOLEAN,        -- NULL = not recorded, FALSE = none, TRUE = see below
  siblings_count INT CHECK (siblings_count IS NULL OR (siblings_count >= 0 AND siblings_count <= 20)),
  siblings_details TEXT,
  elder_sisters INT CHECK (elder_sisters IS NULL OR (elder_sisters >= 0 AND elder_sisters <= 20)),
  younger_sisters INT CHECK (younger_sisters IS NULL OR (younger_sisters >= 0 AND younger_sisters <= 20)),
  elder_brothers INT CHECK (elder_brothers IS NULL OR (elder_brothers >= 0 AND elder_brothers <= 20)),
  younger_brothers INT CHECK (younger_brothers IS NULL OR (younger_brothers >= 0 AND younger_brothers <= 20)),
  family_details TEXT,
  property_share TEXT,
  property_details TEXT,
  city TEXT,                   -- native place (city / town / village)
  state TEXT,                  -- native place (state)
  father_name TEXT,
  father_occupation TEXT,
  father_phone TEXT,
  mother_name TEXT,
  mother_occupation TEXT,
  mother_phone TEXT,
  contact_name TEXT,
  contact_phone TEXT,
  -- The Gandharva account this profile belongs to (one profile per customer).
  customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
  -- When the ₹150 registration fee for this customer profile was paid
  -- (SPEC §9.12). Unpaid customer profiles stay 'hidden'.
  paid_at TIMESTAMPTZ,
  -- 'on_hold' = talks in progress: hidden from other agents like engaged/married,
  -- except the agent whose hold request was approved (see hold_requests).
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','engaged','married','hidden','on_hold')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_profiles_community_status ON profiles(community_id, status);
CREATE INDEX idx_profiles_gender_dob ON profiles(gender, dob);
CREATE INDEX idx_profiles_subcaste ON profiles(subcaste_id);
CREATE INDEX idx_profiles_nri ON profiles(is_nri, nri_country_id);
CREATE INDEX idx_profiles_height ON profiles(height_cm);
CREATE INDEX idx_profiles_religion ON profiles(religion_id);
CREATE INDEX idx_profiles_mother_tongue ON profiles(mother_tongue_id);
CREATE INDEX idx_profiles_food_habit ON profiles(food_habit_id);
CREATE INDEX idx_profiles_customer ON profiles(customer_id) WHERE customer_id IS NOT NULL;
-- One profile per customer (SPEC §9.17, migration 009).
CREATE UNIQUE INDEX uq_profiles_one_per_customer ON profiles(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_profiles_work_country ON profiles(work_country_id);
CREATE INDEX idx_profiles_occupation_type ON profiles(occupation_type_id);

-- Registration form: education by level, each with a country (SPEC §9).
CREATE TABLE profile_education_levels (
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  level TEXT NOT NULL CHECK (level IN ('below_10th','10th','intermediate','graduation','post_graduation')),
  details TEXT,
  country_id INT REFERENCES countries(id),
  PRIMARY KEY (profile_id, level)
);

-- Languages a person knows (M:N). Mother tongue is the single column above.
CREATE TABLE profile_languages (
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  language_id INT NOT NULL REFERENCES languages(id),
  PRIMARY KEY (profile_id, language_id)
);

CREATE TABLE profile_photos (
  id SERIAL PRIMARY KEY,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0
);

-- ===== Contact access workflow =====
CREATE TABLE contact_requests (
  id SERIAL PRIMARY KEY,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  requester_id INT NOT NULL REFERENCES agents(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','revoked','expired')),
  note TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ  -- set to decided_at + interval '15 days' on approval
);
CREATE INDEX idx_contact_requests_profile ON contact_requests(profile_id, requester_id, status);

-- ===== Hold workflow =====
-- Any agent may ask to put a profile on hold (their client is in talks). The
-- uploader or an admin approves/rejects; the uploader, an admin or the holder
-- releases it. Holds placed by the uploader/admin themselves are approved at
-- once. Rows are never deleted — they are the hold log (CLAUDE.md rule 5).
CREATE TABLE hold_requests (
  id SERIAL PRIMARY KEY,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  requester_id INT NOT NULL REFERENCES agents(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled','released')),
  note TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ,
  released_by INT REFERENCES agents(id),
  released_at TIMESTAMPTZ
);
CREATE INDEX idx_hold_requests_profile ON hold_requests(profile_id, status);
CREATE INDEX idx_hold_requests_requester ON hold_requests(requester_id, status);

-- ===== Sharing =====
CREATE TABLE share_tokens (
  id SERIAL PRIMARY KEY,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
  created_by INT NOT NULL REFERENCES agents(id),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE share_logs (
  id SERIAL PRIMARY KEY,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  agent_id INT NOT NULL REFERENCES agents(id),
  method TEXT NOT NULL CHECK (method IN ('whatsapp','download','link','pdf')),
  shared_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===== Shortlists =====
CREATE TABLE shortlists (
  id SERIAL PRIMARY KEY,
  agent_id INT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  client_label TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (agent_id, profile_id, client_label)
);

-- ===== Customer interests (SPEC §9.4) =====
-- A customer marks "interested"; the target profile's uploader (or an admin)
-- accepts or declines. Acceptance unlocks the on-request fields for the
-- customer for 15 days (access_expires_at) and auto-grants contact access to
-- the customer's agent (a contact_requests row, so the log stays complete).
CREATE TABLE customer_interests (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','declined','withdrawn','revoked')),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ,
  access_expires_at TIMESTAMPTZ,
  -- Which of the customer's profiles is interested (SPEC §9.12).
  from_profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  UNIQUE (customer_id, profile_id)
);
CREATE INDEX idx_customer_interests_profile ON customer_interests(profile_id, status);
CREATE INDEX idx_customer_interests_from ON customer_interests(from_profile_id);

-- ===== Payments (SPEC §9.12) =====
-- One row per checkout attempt for the per-profile registration fee.
-- provider: 'mock' (default, nothing charged), 'razorpay', or 'waived'
-- (profiles grandfathered by migration 006).
CREATE TABLE payments (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  purpose TEXT NOT NULL DEFAULT 'profile_registration' CHECK (purpose IN ('profile_registration')),
  amount_paise INT NOT NULL CHECK (amount_paise >= 0),
  currency TEXT NOT NULL DEFAULT 'INR',
  provider TEXT NOT NULL CHECK (provider IN ('mock','razorpay','waived','cash')),
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created','paid','failed')),
  provider_order_id TEXT,
  provider_payment_id TEXT,
  recorded_by INT REFERENCES agents(id),     -- 'cash': the agent who took it (SPEC §9.13)
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ
);
CREATE INDEX idx_payments_customer ON payments(customer_id, created_at DESC);
CREATE UNIQUE INDEX uq_payments_profile_paid ON payments(profile_id)
  WHERE status = 'paid' AND purpose = 'profile_registration';

-- ===== Deleting a paid customer profile (SPEC §9.13) =====
-- The customer asks; their agent (or an admin) approves, which deletes it.
CREATE TABLE profile_delete_requests (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  profile_id INT REFERENCES profiles(id) ON DELETE SET NULL,
  profile_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by INT REFERENCES agents(id),
  decided_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_profile_delete_pending ON profile_delete_requests(profile_id)
  WHERE status = 'pending';
CREATE INDEX idx_profile_delete_requests_customer ON profile_delete_requests(customer_id, status);

-- ===== Push notification devices (SPEC §9.16) =====
CREATE TABLE push_devices (
  id SERIAL PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  app TEXT NOT NULL CHECK (app IN ('mediator','gandharva')),
  agent_id INT REFERENCES agents(id) ON DELETE CASCADE,
  customer_id INT REFERENCES customers(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cursor_at TIMESTAMPTZ NOT NULL DEFAULT now(),   -- feed items newer than this get pushed
  CONSTRAINT push_devices_one_owner CHECK ((agent_id IS NULL) <> (customer_id IS NULL))
);
CREATE INDEX idx_push_devices_agent ON push_devices(agent_id);
CREATE INDEX idx_push_devices_customer ON push_devices(customer_id);

-- ===== Agent change (SPEC §9.6) =====
-- The customer picks a new agent; the CURRENT agent (or an admin) approves,
-- which moves the customer and their profile to the new agent.
CREATE TABLE agent_change_requests (
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
CREATE INDEX idx_agent_change_requests_customer ON agent_change_requests(customer_id, status);
CREATE INDEX idx_agent_change_requests_from ON agent_change_requests(from_agent_id, status);

-- =====================================================================
-- SEED DATA (starter lists; admin will expand from the app)
-- =====================================================================

INSERT INTO zodiac_signs (english_name, indian_name, sort_order) VALUES
 ('Aries','Mesha',1), ('Taurus','Vrishabha',2), ('Gemini','Mithuna',3),
 ('Cancer','Karka',4), ('Leo','Simha',5), ('Virgo','Kanya',6),
 ('Libra','Tula',7), ('Scorpio','Vrischika',8), ('Sagittarius','Dhanu',9),
 ('Capricorn','Makara',10), ('Aquarius','Kumbha',11), ('Pisces','Meena',12);

INSERT INTO nakshatrams (name, sort_order) VALUES
 ('Ashwini',1),('Bharani',2),('Krittika',3),('Rohini',4),('Mrigashira',5),
 ('Ardra',6),('Punarvasu',7),('Pushya',8),('Ashlesha',9),('Magha',10),
 ('Purva Phalguni',11),('Uttara Phalguni',12),('Hasta',13),('Chitra',14),
 ('Swati',15),('Vishakha',16),('Anuradha',17),('Jyeshtha',18),('Mula',19),
 ('Purva Ashadha',20),('Uttara Ashadha',21),('Shravana',22),('Dhanishta',23),
 ('Shatabhisha',24),('Purva Bhadrapada',25),('Uttara Bhadrapada',26),('Revati',27);

INSERT INTO marital_statuses (name, sort_order) VALUES
 ('Unmarried',1),('Widowed',2),('Divorced',3),('Awaiting Divorce',4),('Second Marriage',5);

INSERT INTO complexions (name, sort_order) VALUES
 ('Very Fair',1),('Fair',2),('Wheatish',3),('Wheatish Brown',4),('Dark',5);

INSERT INTO countries (name, sort_order) VALUES
 ('India',0),('United States',1),('United Kingdom',2),('Australia',3),('Canada',4),('Germany',5),
 ('France',6),('Russia',7),('United Arab Emirates',8),('Saudi Arabia',9),('Qatar',10),
 ('Kuwait',11),('Oman',12),('Bahrain',13),('Singapore',14),('Malaysia',15),
 ('New Zealand',16),('Ireland',17),('Netherlands',18),('Switzerland',19),('Sweden',20),
 ('Italy',21),('Japan',22),('South Africa',23),('Other',99);

INSERT INTO religions (name, sort_order) VALUES
 ('Hindu',1),('Muslim',2),('Christian',3),('Sikh',4),('Jain',5),('Buddhist',6),
 ('Parsi',7),('Jewish',8),('Other',99);

INSERT INTO languages (name, sort_order) VALUES
 ('Telugu',1),('Hindi',2),('English',3),('Tamil',4),('Kannada',5),('Malayalam',6),
 ('Marathi',7),('Gujarati',8),('Bengali',9),('Punjabi',10),('Urdu',11),('Odia',12),
 ('Konkani',13),('Tulu',14),('Rajasthani',15),('Bhojpuri',16),('Assamese',17),
 ('Sanskrit',18),('Other',99);

INSERT INTO food_habits (name, sort_order) VALUES
 ('Vegetarian',1),('Non-Vegetarian',2),('Eggetarian',3),('Fish only (Pescatarian)',4),
 ('Occasionally Non-Veg',5),('Jain',6),('Vegan',7);

INSERT INTO occupation_types (name, sort_order) VALUES
 ('Private job',1),('Government job',2),('Business',3),('Self-employed',4),
 ('Professional (Doctor / Lawyer / CA)',5),('Farmer / Agriculture',6),('Student',7),
 ('Not working',8),('Other',99);

INSERT INTO educations (name, sort_order) VALUES
 ('Below 10th',1),('10th',2),('Intermediate / 12th',3),('Diploma',4),('Graduate',5),
 ('Post Graduate',6),('B.Tech / B.E.',7),('M.Tech / M.E.',8),('MBBS',9),('MD / MS',10),
 ('BDS',11),('B.Pharm',12),('CA / CS / ICWA',13),('LLB / LLM',14),('MBA',15),('PhD',16);

INSERT INTO professions (name, sort_order) VALUES
 ('Software Engineer',1),('Government Employee',2),('Private Employee',3),('Business',4),
 ('Doctor',5),('Teacher / Lecturer',6),('Engineer (Non-IT)',7),('Lawyer',8),
 ('Chartered Accountant',9),('Banker',10),('Agriculture',11),('Working Abroad',12),
 ('Homemaker',13),('Not Working',14),('Other',15);

-- Communities: placeholder starters; admin will add real ones from the app.
INSERT INTO communities (name, sort_order) VALUES
 ('Community A',1),('Community B',2),('Community C',3);

-- Default admin (phone: 9999999999, password: ChangeMe@123 — CHANGE IMMEDIATELY).
-- Hash below is bcrypt of 'ChangeMe@123' (cost 10). Regenerate if bcrypt version differs.
INSERT INTO agents (full_name, phone, password_hash, agency_name, role, status) VALUES
 ('Default Admin','9999999999','$2b$10$SYY1xOuL7fY1fxHrASEOQ.jTXDZq0XPt1V091ZUx/f6mcpjhbwWKm','HQ','admin','active');
