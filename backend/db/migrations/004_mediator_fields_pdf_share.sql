-- 004: Mediator release — new bio-data fields and the PDF share method.
--
--  * religions, languages, food_habits masters (admin-editable like the rest)
--  * profiles.religion_id, mother_tongue_id, food_habit_id
--  * profile_languages: the languages a person knows (M:N to languages)
--  * profiles.has_siblings / siblings_count / siblings_details
--      has_siblings NULL = not recorded, FALSE = none, TRUE = see count/details.
--      siblings_details is in-app only — like family_details it never reaches
--      shares, PDFs or public pages (it may name people). The count is public.
--  * share_logs.method gains 'pdf' (POST /profiles/:id/share {method:'pdf'})
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/004_mediator_fields_pdf_share.sql
-- Fresh installs get the same DDL from schema.sql.

BEGIN;

-- ===== new masters =====
CREATE TABLE IF NOT EXISTS religions (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO religions (name, sort_order) VALUES
 ('Hindu',1),('Muslim',2),('Christian',3),('Sikh',4),('Jain',5),('Buddhist',6),
 ('Parsi',7),('Jewish',8),('Other',99)
ON CONFLICT (name) DO NOTHING;

-- One list serves both "mother tongue" and "known languages".
CREATE TABLE IF NOT EXISTS languages (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO languages (name, sort_order) VALUES
 ('Telugu',1),('Hindi',2),('English',3),('Tamil',4),('Kannada',5),('Malayalam',6),
 ('Marathi',7),('Gujarati',8),('Bengali',9),('Punjabi',10),('Urdu',11),('Odia',12),
 ('Konkani',13),('Tulu',14),('Rajasthani',15),('Bhojpuri',16),('Assamese',17),
 ('Sanskrit',18),('Other',99)
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS food_habits (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO food_habits (name, sort_order) VALUES
 ('Vegetarian',1),('Non-Vegetarian',2),('Eggetarian',3),('Fish only (Pescatarian)',4),
 ('Occasionally Non-Veg',5),('Jain',6),('Vegan',7)
ON CONFLICT (name) DO NOTHING;

-- ===== profiles =====
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS religion_id INT REFERENCES religions(id),
  ADD COLUMN IF NOT EXISTS mother_tongue_id INT REFERENCES languages(id),
  ADD COLUMN IF NOT EXISTS food_habit_id INT REFERENCES food_habits(id),
  ADD COLUMN IF NOT EXISTS has_siblings BOOLEAN,   -- NULL = not recorded
  ADD COLUMN IF NOT EXISTS siblings_count INT
    CHECK (siblings_count IS NULL OR (siblings_count >= 0 AND siblings_count <= 20)),
  ADD COLUMN IF NOT EXISTS siblings_details TEXT;  -- in-app only, never shared

CREATE INDEX IF NOT EXISTS idx_profiles_religion ON profiles(religion_id);
CREATE INDEX IF NOT EXISTS idx_profiles_mother_tongue ON profiles(mother_tongue_id);
CREATE INDEX IF NOT EXISTS idx_profiles_food_habit ON profiles(food_habit_id);

CREATE TABLE IF NOT EXISTS profile_languages (
  profile_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  language_id INT NOT NULL REFERENCES languages(id),
  PRIMARY KEY (profile_id, language_id)
);

-- ===== sharing =====
ALTER TABLE share_logs DROP CONSTRAINT IF EXISTS share_logs_method_check;
ALTER TABLE share_logs ADD CONSTRAINT share_logs_method_check
  CHECK (method IN ('whatsapp','download','link','pdf'));

COMMIT;
