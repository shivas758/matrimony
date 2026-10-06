-- 001: subcastes master table + profiles.subcaste_id
--
-- A subcaste belongs to exactly one community. Agents create them by typing on
-- the profile form (find-or-create, case-insensitive); admins manage them from
-- the master editor.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony < db/migrations/001_subcastes.sql
-- Fresh installs get the same DDL from schema.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS subcastes (
  id SERIAL PRIMARY KEY,
  community_id INT NOT NULL REFERENCES communities(id),
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (community_id, name)
);

-- Case-insensitive uniqueness so "Chowdary" and "chowdary" cannot both exist.
CREATE UNIQUE INDEX IF NOT EXISTS uq_subcastes_community_lower_name
  ON subcastes (community_id, lower(name));

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS subcaste_id INT REFERENCES subcastes(id);

CREATE INDEX IF NOT EXISTS idx_profiles_subcaste ON profiles(subcaste_id);

COMMIT;
