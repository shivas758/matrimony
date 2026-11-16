-- 013 — Store-review demo world (SPEC §9.21, v2.11).
--
--  * agents.is_demo / customers.is_demo / profiles.is_demo (default false).
--  * A profile's is_demo always equals its uploader's: set by a trigger on insert and when
--    uploaded_by changes, and pushed to every upload when an agent's flag changes.
-- Visibility (lib/profiles.js, routes/customerApp.js) only ever shows a viewer profiles of
-- their own world; admins see the real world only.
--
-- No data changes. Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/013_demo_world.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

ALTER TABLE agents ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION profiles_inherit_demo() RETURNS trigger AS $$
BEGIN
  NEW.is_demo := COALESCE((SELECT a.is_demo FROM agents a WHERE a.id = NEW.uploaded_by), FALSE);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profiles_demo ON profiles;
CREATE TRIGGER trg_profiles_demo BEFORE INSERT OR UPDATE OF uploaded_by ON profiles
  FOR EACH ROW EXECUTE FUNCTION profiles_inherit_demo();

CREATE OR REPLACE FUNCTION agents_propagate_demo() RETURNS trigger AS $$
BEGIN
  IF NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN
    UPDATE profiles SET is_demo = NEW.is_demo WHERE uploaded_by = NEW.id;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_agents_demo ON agents;
CREATE TRIGGER trg_agents_demo AFTER UPDATE OF is_demo ON agents
  FOR EACH ROW EXECUTE FUNCTION agents_propagate_demo();

CREATE INDEX IF NOT EXISTS idx_profiles_demo ON profiles(id) WHERE is_demo;

COMMIT;
