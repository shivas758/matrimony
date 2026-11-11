-- 010: Wedbook (SPEC §9.18) — agent codes, customer / profile IDs, privacy
-- toggles and the community audience.
--
--   * states                  master: Indian states / UTs with their 2-letter code
--   * agents.state_id         the agent's state (chosen once, never changed)
--   * agents.agent_code       STATE + NUMBER + LETTER(S): KA1A, KA1B … (permanent, unique)
--   * agent_code_counters     per-state sequence; only counts up → codes are never reused
--   * agents.profile_seq      per-agent sequence for profile IDs; only counts up
--   * profiles.profile_code   GN-<agent code>-<letter><3 digits>: GN-KA1A-A001 (permanent)
--   * profiles.hidden_fields  the details the family switched off ("only after approval")
--   * profiles.audience_all / audience_community_ids
--                             extra communities the profile is shown to (own one is implicit)
--
-- No codes are issued here: agents registered before this migration choose
-- their State in the app (POST /api/my/state), which issues their code and the
-- IDs of all their profiles. Idempotent — deploy/update.sh re-runs every
-- migration on each deploy.

CREATE TABLE IF NOT EXISTS states (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{2}$'),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);

INSERT INTO states (name, code, sort_order) VALUES
 ('Karnataka','KA',1), ('Andhra Pradesh','AP',2), ('Telangana','TS',3), ('Tamil Nadu','TN',4),
 ('Kerala','KL',5), ('Maharashtra','MH',6),
 ('Andaman and Nicobar Islands','AN',10), ('Arunachal Pradesh','AR',11), ('Assam','AS',12),
 ('Bihar','BR',13), ('Chandigarh','CH',14), ('Chhattisgarh','CG',15),
 ('Dadra and Nagar Haveli and Daman and Diu','DD',16), ('Delhi','DL',17), ('Goa','GA',18),
 ('Gujarat','GJ',19), ('Haryana','HR',20), ('Himachal Pradesh','HP',21),
 ('Jammu and Kashmir','JK',22), ('Jharkhand','JH',23), ('Ladakh','LA',24), ('Lakshadweep','LD',25),
 ('Madhya Pradesh','MP',26), ('Manipur','MN',27), ('Meghalaya','ML',28), ('Mizoram','MZ',29),
 ('Nagaland','NL',30), ('Odisha','OD',31), ('Puducherry','PY',32), ('Punjab','PB',33),
 ('Rajasthan','RJ',34), ('Sikkim','SK',35), ('Tripura','TR',36), ('Uttar Pradesh','UP',37),
 ('Uttarakhand','UK',38), ('West Bengal','WB',39)
ON CONFLICT DO NOTHING;

ALTER TABLE agents ADD COLUMN IF NOT EXISTS state_id INT REFERENCES states(id);
ALTER TABLE agents ADD COLUMN IF NOT EXISTS agent_code TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS profile_seq INT NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS uq_agents_agent_code ON agents(agent_code) WHERE agent_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS agent_code_counters (
  state_id INT PRIMARY KEY REFERENCES states(id),
  last_seq INT NOT NULL DEFAULT 0
);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS profile_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_profile_code ON profiles(profile_code) WHERE profile_code IS NOT NULL;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS hidden_fields TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS audience_all BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS audience_community_ids INT[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS idx_profiles_audience ON profiles USING GIN (audience_community_ids);
