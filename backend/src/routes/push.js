// Push notification registration — SPEC §9.16.
//  pushConfigRouter        → /api/push/config             public Firebase client options
//  agentPushRouter         → /api/push/devices            agents (any status)
//  customerPushRouter      → /api/customer/push/devices   customers (any status)
// The admin run/outbox routes live in admin.js.
import { Router } from 'express';
import { z } from 'zod';
import { query } from '../lib/db.js';
import { asyncHandler } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { clientOptions } from '../lib/push.js';

export const pushConfigRouter = Router();
export const agentPushRouter = Router();
export const customerPushRouter = Router();

const appSchema = z.object({ app: z.enum(['mediator', 'gandharva']) });
const tokenSchema = z.object({ token: z.string().trim().min(10).max(4096) });

// GET /api/push/config?app=mediator|gandharva
pushConfigRouter.get(
  '/config',
  asyncHandler(async (req, res) => {
    const { app } = parse(appSchema, req.query);
    const options = clientOptions(app);
    res.json({ enabled: Boolean(options), options });
  }),
);

/** Upsert: a token belongs to whoever registered it last; the cursor starts now (no backlog). */
async function register(token, app, { agentId = null, customerId = null }) {
  await query(
    `INSERT INTO push_devices (token, app, agent_id, customer_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (token) DO UPDATE
       SET app = EXCLUDED.app, agent_id = EXCLUDED.agent_id, customer_id = EXCLUDED.customer_id,
           last_seen_at = now(),
           cursor_at = CASE WHEN push_devices.agent_id IS NOT DISTINCT FROM EXCLUDED.agent_id
                             AND push_devices.customer_id IS NOT DISTINCT FROM EXCLUDED.customer_id
                            THEN push_devices.cursor_at ELSE now() END`,
    [token, app, agentId, customerId],
  );
}

agentPushRouter.post(
  '/devices',
  asyncHandler(async (req, res) => {
    const { token } = parse(tokenSchema, req.body ?? {});
    await register(token, 'mediator', { agentId: req.agent.id });
    res.status(201).json({ ok: true });
  }),
);

agentPushRouter.post(
  '/devices/remove',
  asyncHandler(async (req, res) => {
    const { token } = parse(tokenSchema, req.body ?? {});
    await query('DELETE FROM push_devices WHERE token = $1 AND agent_id = $2', [token, req.agent.id]);
    res.json({ ok: true });
  }),
);

customerPushRouter.post(
  '/devices',
  asyncHandler(async (req, res) => {
    const { token } = parse(tokenSchema, req.body ?? {});
    await register(token, 'gandharva', { customerId: req.customer.id });
    res.status(201).json({ ok: true });
  }),
);

customerPushRouter.post(
  '/devices/remove',
  asyncHandler(async (req, res) => {
    const { token } = parse(tokenSchema, req.body ?? {});
    await query('DELETE FROM push_devices WHERE token = $1 AND customer_id = $2', [token, req.customer.id]);
    res.json({ ok: true });
  }),
);
