import { Router } from 'express';
import { z } from 'zod';
import { many, one, tx } from '../lib/db.js';
import { asyncHandler, badRequest, conflict } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { AGENT_SELECT, agentPublic } from '../lib/serialize.js';
import { findState, issueAgentCode, issueMissingProfileCodes } from '../lib/codes.js';

// Mounted at /api/my — agent self-service (SPEC §5 screen 10).
export const meRouter = Router();

/** Communities the agent belongs to, as {id, name} — same shape as auth.js. */
async function agentCommunities(agentId) {
  return many(
    `SELECT c.id, c.name
       FROM agent_communities ac JOIN communities c ON c.id = ac.community_id
      WHERE ac.agent_id = $1
      ORDER BY c.sort_order, c.name`,
    [agentId],
  );
}

// Empty strings clear the value; absent keys are left alone.
const emptyToNull = (v) => (v === '' ? null : v);
const accountSchema = z.object({
  city: z.string().trim().max(80).nullable().optional().transform(emptyToNull),
  agency_name: z.string().trim().max(120).nullable().optional().transform(emptyToNull),
});

// PATCH /api/my/account {city?, agency_name?} — the agent's own directory
// details, shown to customers in the Gandharva agent list (SPEC §9.5 / §9.6).
meRouter.patch(
  '/account',
  asyncHandler(async (req, res) => {
    const body = parse(accountSchema, req.body ?? {});
    const sets = [];
    const params = [];
    if (body.city !== undefined) {
      params.push(body.city);
      sets.push(`city = $${params.length}`);
    }
    if (body.agency_name !== undefined) {
      params.push(body.agency_name);
      sets.push(`agency_name = $${params.length}`);
    }
    if (!sets.length) throw badRequest('nothing_to_update', 'Send a city or an agency name to update');

    params.push(req.agent.id);
    await one(`UPDATE agents SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING id`, params);
    const agent = await one(`${AGENT_SELECT} WHERE a.id = $1`, [req.agent.id]);
    res.json({ agent: agentPublic(agent, await agentCommunities(agent.id)) });
  }),
);

const stateSchema = z.object({ state_id: z.coerce.number().int().positive('Select your state') });

// POST /api/my/state {state_id} — an agent registered before v2.8 chooses
// their State ONCE (SPEC §9.18 B). That issues their permanent agent code and
// the IDs of every profile they already have (oldest first). Neither can be
// changed afterwards: 409 state_already_set.
meRouter.post(
  '/state',
  asyncHandler(async (req, res) => {
    const { state_id } = parse(stateSchema, req.body ?? {});
    await tx(async (client) => {
      // Lock the row: two taps must not issue two codes.
      const { rows } = await client.query('SELECT id, agent_code FROM agents WHERE id = $1 FOR UPDATE', [
        req.agent.id,
      ]);
      if (rows[0].agent_code) {
        throw conflict('state_already_set', `Your agent code is ${rows[0].agent_code} — it cannot be changed`);
      }
      const state = await findState(client, state_id);
      if (!state) throw badRequest('invalid_state', 'Select your state from the list');
      await issueAgentCode(client, req.agent.id, state);
      await issueMissingProfileCodes(client, { agentId: req.agent.id });
    });
    const agent = await one(`${AGENT_SELECT} WHERE a.id = $1`, [req.agent.id]);
    res.json({ agent: agentPublic(agent, await agentCommunities(agent.id)) });
  }),
);

// GET /api/my/communities — current communities plus any pending join requests.
meRouter.get(
  '/communities',
  asyncHandler(async (req, res) => {
    const [communities, requests] = await Promise.all([
      many(
        `SELECT c.id, c.name FROM agent_communities ac JOIN communities c ON c.id = ac.community_id
          WHERE ac.agent_id = $1 ORDER BY c.sort_order, c.name`,
        [req.agent.id],
      ),
      many(
        `SELECT ccr.id, ccr.status, ccr.created_at, ccr.decided_at, c.id AS community_id, c.name AS community_name
           FROM community_change_requests ccr JOIN communities c ON c.id = ccr.community_id
          WHERE ccr.agent_id = $1 ORDER BY ccr.created_at DESC`,
        [req.agent.id],
      ),
    ]);
    res.json({ communities, requests });
  }),
);

const requestSchema = z.object({ community_id: z.coerce.number().int().positive() });

// POST /api/my/community-requests — additions after signup need admin approval (SPEC §2).
meRouter.post(
  '/community-requests',
  asyncHandler(async (req, res) => {
    const { community_id } = parse(requestSchema, req.body ?? {});

    const community = await one('SELECT id, name FROM communities WHERE id = $1 AND active = TRUE', [community_id]);
    if (!community) throw badRequest('invalid_community', 'That community is not available');

    const already = await one('SELECT 1 FROM agent_communities WHERE agent_id = $1 AND community_id = $2', [
      req.agent.id,
      community_id,
    ]);
    if (already) throw conflict('already_member', `You are already in ${community.name}`);

    const pending = await one(
      `SELECT id FROM community_change_requests
        WHERE agent_id = $1 AND community_id = $2 AND status = 'pending'`,
      [req.agent.id, community_id],
    );
    if (pending) throw conflict('already_pending', 'You already have a pending request for this community');

    const row = await one(
      `INSERT INTO community_change_requests (agent_id, community_id)
       VALUES ($1,$2) RETURNING id, community_id, status, created_at`,
      [req.agent.id, community_id],
    );
    res.status(201).json({ community_request: { ...row, community_name: community.name } });
  }),
);
