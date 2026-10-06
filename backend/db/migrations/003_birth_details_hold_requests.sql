-- 003: birth time / birth place (horoscope), the profile HOLD workflow, and
--      the 'on_hold' profile status.
--
--  * profiles.birth_time (TIME) and profiles.birth_place — public horoscope
--    fields, shown wherever star/rasi are shown (SPEC §2). The native place
--    (city/state) stays PROTECTED; birth place is a separate field.
--  * profiles.status gains 'on_hold': talks are in progress, so the profile is
--    hidden from other agents like engaged/married — except the agent whose
--    hold was approved, who keeps seeing it.
--  * hold_requests: any agent can ask for a hold; the uploader or an admin
--    approves/rejects; the uploader, an admin or the holder releases it.
--    Holds placed by the uploader/admin themselves are approved immediately.
--    Every row stays as the log of who held what and when (CLAUDE.md rule 5).
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/003_birth_details_hold_requests.sql
-- Fresh installs get the same DDL from schema.sql.

BEGIN;

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS birth_time TIME,
  ADD COLUMN IF NOT EXISTS birth_place TEXT;

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_status_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_status_check
  CHECK (status IN ('active','engaged','married','hidden','on_hold'));

CREATE TABLE IF NOT EXISTS hold_requests (
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
CREATE INDEX IF NOT EXISTS idx_hold_requests_profile ON hold_requests(profile_id, status);
CREATE INDEX IF NOT EXISTS idx_hold_requests_requester ON hold_requests(requester_id, status);

COMMIT;
