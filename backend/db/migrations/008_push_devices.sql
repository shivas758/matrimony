-- 008: push notifications (SPEC §9.16) — one row per app install's FCM token.
--
-- Apply on an existing install:
--   docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/008_push_devices.sql
-- Fresh installs get the same DDL from schema.sql. Safe to run twice.

BEGIN;

CREATE TABLE IF NOT EXISTS push_devices (
  id SERIAL PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  app TEXT NOT NULL CHECK (app IN ('mediator','gandharva')),
  agent_id INT REFERENCES agents(id) ON DELETE CASCADE,
  customer_id INT REFERENCES customers(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Feed items newer than this are pushed; moved forward after every pass.
  cursor_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT push_devices_one_owner CHECK ((agent_id IS NULL) <> (customer_id IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_push_devices_agent ON push_devices(agent_id);
CREATE INDEX IF NOT EXISTS idx_push_devices_customer ON push_devices(customer_id);

COMMIT;
