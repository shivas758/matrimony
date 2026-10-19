// The agent side of the Gandharva customer domain (SPEC §9.4 / §9.5 / §9.6):
//  * clientsRouter      → /api/clients              my customers, approve / reject /
//                                                   suspend / activate, registration link
//  * interestsRouter    → /api/interests            interests on my uploads (decide) and
//                                                   my clients' interests (read)
//  * agentChangeRouter  → /api/agent-change-requests customers asking to move agent
// All three sit behind requireAuth + requireActive (server.js).
import { Router } from 'express';
import { z } from 'zod';
import { config } from '../lib/config.js';
import { many, one, query, tx } from '../lib/db.js';
import { asyncHandler, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import {
  AGENT_CHANGE_SELECT,
  CLIENT_SELECT,
  DELETE_REQUEST_SELECT,
  INTEREST_SELECT,
  agentChangeRow,
  clientRow,
  deleteRequestRow,
  interestRow,
  loadDeleteRequest,
  loadAgentChange,
  loadClient,
  loadClientFor,
  loadInterest,
  reassignCustomer,
  transitionCustomer,
} from '../lib/customers.js';
import { deleteProfile } from '../lib/profiles.js';
import { recordCashPayment } from '../lib/payments.js';

export const clientsRouter = Router();
export const interestsRouter = Router();
export const agentChangeRouter = Router();

const first = async (client, sql, params) => (await client.query(sql, params)).rows[0] ?? null;

// ================================================================ clients (SPEC §9.5)

const clientListSchema = z.object({
  status: z.enum(['pending', 'active', 'rejected', 'suspended']).optional(),
  q: z.string().trim().max(80).optional(),
});

// GET /api/clients?status=&q= — my customers (admin: everyone's, rows add `agent`).
clientsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(clientListSchema, req.query);
    const where = [];
    const params = [];
    if (!req.agent.is_admin) {
      params.push(req.agent.id);
      where.push(`cu.agent_id = $${params.length}`);
    }
    if (f.status) {
      params.push(f.status);
      where.push(`cu.status = $${params.length}`);
    }
    if (f.q) {
      params.push(`%${f.q}%`);
      where.push(`(cu.full_name ILIKE $${params.length} OR cu.phone ILIKE $${params.length})`);
    }
    const rows = await many(
      `${CLIENT_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY CASE cu.status WHEN 'pending' THEN 0 ELSE 1 END, cu.created_at DESC, cu.id DESC`,
      params,
    );
    res.json({ clients: rows.map((r) => clientRow(r, { admin: req.agent.is_admin })) });
  }),
);

// ---- registration link (SPEC §9.3-B). Declared BEFORE /:id so the literal
// path is never parsed as a customer id.

/** {url, whatsapp_text} for the agent's current token (minting one if the row predates 005). */
async function registrationLink(agent) {
  let token = agent.registration_token;
  if (!token) {
    const row = await one(
      `UPDATE agents SET registration_token = encode(gen_random_bytes(12), 'hex')
        WHERE id = $1 AND registration_token IS NULL RETURNING registration_token`,
      [agent.id],
    );
    token = row?.registration_token ?? (await one('SELECT registration_token FROM agents WHERE id = $1', [agent.id])).registration_token;
  }
  const url = `${config.publicBaseUrl}/r/${token}`;
  const who = agent.agency_name ? `${agent.full_name} from ${agent.agency_name}` : agent.full_name;
  const whatsapp_text =
    `Namaste! This is ${who}. Please fill in this registration form so I can add your profile ` +
    `and start looking for matches:\n${url}\n\n` +
    'After submitting, install the MILI app and log in with the same mobile number to browse profiles.';
  return { url, whatsapp_text };
}

// GET /api/clients/registration-link
clientsRouter.get(
  '/registration-link',
  asyncHandler(async (req, res) => {
    res.json(await registrationLink(req.agent));
  }),
);

// POST /api/clients/registration-link/rotate — the old link stops working at once.
clientsRouter.post(
  '/registration-link/rotate',
  asyncHandler(async (req, res) => {
    const row = await one(
      `UPDATE agents SET registration_token = encode(gen_random_bytes(12), 'hex')
        WHERE id = $1 RETURNING registration_token`,
      [req.agent.id],
    );
    res.json(await registrationLink({ ...req.agent, registration_token: row.registration_token }));
  }),
);

// ---------------------------------------------------------------- delete requests (SPEC §9.13)

const deleteListSchema = z.object({
  status: z.enum(['pending', 'approved', 'rejected', 'cancelled']).default('pending'),
});

// GET /api/clients/delete-requests?status= — my clients' (admin: all).
clientsRouter.get(
  '/delete-requests',
  asyncHandler(async (req, res) => {
    const f = parse(deleteListSchema, req.query);
    const params = [f.status];
    let where = 'd.status = $1';
    if (!req.agent.is_admin) {
      params.push(req.agent.id);
      where += ' AND cu.agent_id = $2';
    }
    const rows = await many(`${DELETE_REQUEST_SELECT} WHERE ${where} ORDER BY d.created_at DESC, d.id DESC`, params);
    res.json({ delete_requests: rows.map((r) => deleteRequestRow(r, { agent: req.agent })) });
  }),
);

/** A pending delete request the agent may decide (the customer's agent or an admin). */
async function loadDecidableDelete(id, agent) {
  const row = await loadDeleteRequest(id);
  if (!row) throw notFound('request_not_found', 'Request not found');
  if (!agent.is_admin && row.customer_agent_id !== agent.id) {
    throw forbidden('not_your_client', 'This customer is attached to another agent');
  }
  if (row.status !== 'pending') throw conflict('wrong_status', `This request is already ${row.status}`);
  return row;
}

// POST /api/clients/delete-requests/:id/approve — deletes the profile for good.
clientsRouter.post(
  '/delete-requests/:id/approve',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidableDelete(id, req.agent);
    await query(
      `UPDATE profile_delete_requests SET status = 'approved', decided_by = $2, decided_at = now() WHERE id = $1`,
      [id, req.agent.id],
    );
    if (row.profile_id) await deleteProfile(row.profile_id);
    res.json({ delete_request: deleteRequestRow(await loadDeleteRequest(id), { agent: req.agent }) });
  }),
);

// POST /api/clients/delete-requests/:id/reject
clientsRouter.post(
  '/delete-requests/:id/reject',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await loadDecidableDelete(id, req.agent);
    await query(
      `UPDATE profile_delete_requests SET status = 'rejected', decided_by = $2, decided_at = now() WHERE id = $1`,
      [id, req.agent.id],
    );
    res.json({ delete_request: deleteRequestRow(await loadDeleteRequest(id), { agent: req.agent }) });
  }),
);

const markPaidSchema = z.object({
  note: z.string().trim().max(300).optional().nullable().transform((v) => (v ? v : null)),
});

// POST /api/clients/:id/profiles/:profileId/mark-paid {note?} — fee paid in cash (SPEC §9.13).
clientsRouter.post(
  '/:id/profiles/:profileId/mark-paid',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await loadClientFor(id, req.agent);
    const profileId = Number(req.params.profileId);
    if (!Number.isInteger(profileId) || profileId <= 0) throw notFound('profile_not_found', 'Profile not found');
    const body = parse(markPaidSchema, req.body ?? {});
    await recordCashPayment({ profileId, customerId: id, agentId: req.agent.id, note: body.note });
    res.json({ client: clientRow(await loadClient(id), { admin: req.agent.is_admin }) });
  }),
);

// GET /api/clients/:id — the row plus the client's interests and agent-change requests.
clientsRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadClientFor(id, req.agent);
    const [interests, changes, deletes] = await Promise.all([
      many(
        `${INTEREST_SELECT} WHERE ci.customer_id = $1
          ORDER BY CASE WHEN ci.status = 'pending' THEN 0 ELSE 1 END, ci.created_at DESC, ci.id DESC`,
        [id],
      ),
      many(`${AGENT_CHANGE_SELECT} WHERE r.customer_id = $1 ORDER BY r.created_at DESC, r.id DESC`, [id]),
      many(`${DELETE_REQUEST_SELECT} WHERE d.customer_id = $1 ORDER BY d.created_at DESC, d.id DESC`, [id]),
    ]);
    res.json({
      client: {
        ...clientRow(row, { admin: req.agent.is_admin }),
        interests: interests.map((r) => interestRow(r, { agent: req.agent })),
        agent_change_requests: changes.map((r) => agentChangeRow(r, { agent: req.agent })),
        delete_requests: deletes.map((r) => deleteRequestRow(r, { agent: req.agent })),
      },
    });
  }),
);

/** POST /api/clients/:id/<action> — own client or admin; 409 wrong_status otherwise. */
function clientAction(action) {
  return asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await loadClientFor(id, req.agent);
    await transitionCustomer({ id, action, actorId: req.agent.id });
    res.json({ client: clientRow(await loadClient(id), { admin: req.agent.is_admin }) });
  });
}

clientsRouter.post('/:id/approve', clientAction('approve')); // pending → active (+ hidden profile → active)
clientsRouter.post('/:id/reject', clientAction('reject')); // pending → rejected
clientsRouter.post('/:id/suspend', clientAction('suspend')); // active → suspended
clientsRouter.post('/:id/activate', clientAction('activate')); // suspended → active

// ================================================================ interests (SPEC §9.4)

const interestListSchema = z.object({
  box: z.enum(['received', 'clients']).default('received'),
  status: z.enum(['pending', 'accepted', 'declined', 'withdrawn', 'revoked', 'expired']).optional(),
});

// GET /api/interests?box=received|clients&status=
//  received = interests on my uploads (I decide them); clients = interests my
//  clients expressed (read-only, with the other agent's contact). Admin: all.
interestsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(interestListSchema, req.query);
    const where = [];
    const params = [];
    if (!req.agent.is_admin) {
      params.push(req.agent.id);
      where.push(f.box === 'clients' ? `cu.agent_id = $${params.length}` : `p.uploaded_by = $${params.length}`);
    }
    if (f.status === 'expired') {
      where.push(`(ci.status = 'accepted' AND ci.access_expires_at <= now())`);
    } else if (f.status === 'accepted') {
      where.push(`(ci.status = 'accepted' AND ci.access_expires_at > now())`);
    } else if (f.status) {
      params.push(f.status);
      where.push(`ci.status = $${params.length}`);
    }
    const rows = await many(
      `${INTEREST_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY CASE WHEN ci.status = 'pending' THEN 0 ELSE 1 END, ci.created_at DESC, ci.id DESC`,
      params,
    );
    res.json({ box: f.box, interests: rows.map((r) => interestRow(r, { agent: req.agent })) });
  }),
);

/** An interest the caller may decide: the target profile's uploader or an admin. */
async function loadDecidableInterest(id, agent) {
  const row = await loadInterest(id);
  if (!row) throw notFound('interest_not_found', 'Interest not found');
  if (!agent.is_admin && row.target_agent_id !== agent.id) {
    throw forbidden('not_your_profile', 'Only the agent who added this profile can decide this interest');
  }
  return row;
}

/**
 * Accepting an interest also lets the customer's CURRENT agent see the
 * profile's contact details (SPEC §9.4): a live approved contact_requests row
 * is left alone, a pending one is approved, otherwise an approved row is
 * inserted — so every acceptance lands in the contact log (CLAUDE.md rule 5).
 * The uploader (their own upload) and admins (see everything) need nothing.
 */
async function grantAgentContact(client, { profileId, agentId, agentRole, uploaderId, decidedBy, expiresAt, interestId }) {
  if (agentId === uploaderId || agentRole === 'admin') return null;
  const note = `via interest #${interestId}`;
  const latest = await first(
    client,
    `SELECT id, status, (status = 'approved' AND expires_at > now()) AS live
       FROM contact_requests
      WHERE profile_id = $1 AND requester_id = $2
      ORDER BY requested_at DESC, id DESC LIMIT 1
      FOR UPDATE`,
    [profileId, agentId],
  );
  if (latest?.live) return latest.id;
  if (latest?.status === 'pending') {
    await client.query(
      `UPDATE contact_requests
          SET status = 'approved', decided_by = $2, decided_at = now(), expires_at = $3,
              note = CASE WHEN note IS NULL OR note = '' THEN $4 ELSE note || ' · ' || $4 END
        WHERE id = $1`,
      [latest.id, decidedBy, expiresAt, note],
    );
    return latest.id;
  }
  const created = await first(
    client,
    `INSERT INTO contact_requests (profile_id, requester_id, status, note, decided_by, decided_at, expires_at)
     VALUES ($1, $2, 'approved', $3, $4, now(), $5) RETURNING id`,
    [profileId, agentId, note, decidedBy, expiresAt],
  );
  return created.id;
}

// POST /api/interests/:id/accept — pending / declined / lapsed → accepted for
// CONTACT_ACCESS_DAYS; auto-grants contact access to the customer's agent.
interestsRouter.post(
  '/:id/accept',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidableInterest(id, req.agent);
    const acceptable = row.status === 'pending' || row.status === 'declined' || Boolean(row.is_expired);
    if (!acceptable) throw conflict('wrong_status', `This interest is already ${row.status}`);

    await tx(async (client) => {
      const updated = await first(
        client,
        `UPDATE customer_interests
            SET status = 'accepted', decided_by = $2, decided_at = now(),
                access_expires_at = now() + make_interval(days => $3)
          WHERE id = $1 RETURNING access_expires_at`,
        [id, req.agent.id, config.contactAccessDays],
      );
      await grantAgentContact(client, {
        profileId: row.profile_id,
        agentId: row.customer_agent_id,
        agentRole: row.customer_agent_role,
        uploaderId: row.target_agent_id,
        decidedBy: req.agent.id,
        expiresAt: updated.access_expires_at,
        interestId: id,
      });
    });
    res.json({ interest: interestRow(await loadInterest(id), { agent: req.agent }) });
  }),
);

// POST /api/interests/:id/decline — pending → declined.
interestsRouter.post(
  '/:id/decline',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidableInterest(id, req.agent);
    if (row.status !== 'pending') throw conflict('wrong_status', `This interest is already ${row.status}`);
    await one(
      `UPDATE customer_interests SET status = 'declined', decided_by = $2, decided_at = now(), access_expires_at = NULL
        WHERE id = $1 RETURNING id`,
      [id, req.agent.id],
    );
    res.json({ interest: interestRow(await loadInterest(id), { agent: req.agent }) });
  }),
);

// POST /api/interests/:id/revoke — accepted → revoked; the customer's access
// ends now (SPEC §9.4) AND so does the contact access grantAgentContact() gave
// the customer's agent because of this acceptance: the Mediator app promises
// "the client and their agent lose access immediately", and that row exists
// only because of this interest (CLAUDE.md rule 4 — access is the uploader's
// to withdraw). A row the agent held independently (no `via interest` note,
// left untouched at accept time) is not affected.
interestsRouter.post(
  '/:id/revoke',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidableInterest(id, req.agent);
    if (row.status !== 'accepted') throw conflict('wrong_status', 'Only an accepted interest can be revoked');
    await tx(async (client) => {
      await client.query(
        `UPDATE customer_interests SET status = 'revoked', decided_by = $2, decided_at = now(), access_expires_at = now()
          WHERE id = $1`,
        [id, req.agent.id],
      );
      // grantAgentContact() always appends "via interest #<id>" LAST, so the
      // suffix match cannot confuse #36 with #360. Matched on the profile, not
      // the requester: the customer may have changed agent since acceptance.
      await client.query(
        `UPDATE contact_requests SET status = 'revoked', expires_at = now()
          WHERE profile_id = $1 AND status = 'approved' AND note LIKE '%via interest #' || $2::text`,
        [row.profile_id, id],
      );
    });
    res.json({ interest: interestRow(await loadInterest(id), { agent: req.agent }) });
  }),
);

// ================================================================ agent change (SPEC §9.6)

const changeListSchema = z.object({
  box: z.enum(['outgoing', 'incoming']).default('outgoing'),
  status: z.enum(['pending', 'approved', 'rejected', 'cancelled']).optional(),
});

// GET /api/agent-change-requests?box=outgoing|incoming&status=
//  outgoing = my clients asking to leave (I decide); incoming = customers
//  moving to me (read-only). Admins get every request, box ignored.
agentChangeRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(changeListSchema, req.query);
    const where = [];
    const params = [];
    if (!req.agent.is_admin) {
      params.push(req.agent.id);
      where.push(f.box === 'incoming' ? `r.to_agent_id = $${params.length}` : `r.from_agent_id = $${params.length}`);
    }
    if (f.status) {
      params.push(f.status);
      where.push(`r.status = $${params.length}`);
    }
    const rows = await many(
      `${AGENT_CHANGE_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY CASE WHEN r.status = 'pending' THEN 0 ELSE 1 END, r.created_at DESC, r.id DESC`,
      params,
    );
    res.json({ box: f.box, agent_change_requests: rows.map((r) => agentChangeRow(r, { agent: req.agent })) });
  }),
);

/** A pending request the caller may decide: the customer's current (from) agent or an admin. */
async function loadDecidableChange(id, agent) {
  const row = await loadAgentChange(id);
  if (!row) throw notFound('request_not_found', 'Request not found');
  if (!agent.is_admin && row.from_agent_id !== agent.id) {
    throw forbidden('not_your_client', "Only the customer's current agent can decide this request");
  }
  if (row.status !== 'pending') throw conflict('wrong_status', `This request is already ${row.status}`);
  return row;
}

// POST /api/agent-change-requests/:id/approve — one transaction: the customer
// and their profile move to the new agent; their other pending asks are cancelled.
agentChangeRouter.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidableChange(id, req.agent);
    const target = await one('SELECT id, status FROM agents WHERE id = $1', [row.to_agent_id]);
    if (!target || target.status !== 'active') {
      throw badRequest('agent_not_active', 'The agent this customer wants to move to is not active');
    }
    await tx(async (client) => {
      await client.query(
        `UPDATE agent_change_requests SET status = 'approved', decided_by = $2, decided_at = now() WHERE id = $1`,
        [id, req.agent.id],
      );
      await reassignCustomer(client, {
        customerId: row.customer_id,
        toAgentId: row.to_agent_id,
        actorId: req.agent.id,
        keepRequestId: id,
      });
    });
    res.json({ agent_change_request: agentChangeRow(await loadAgentChange(id), { agent: req.agent }) });
  }),
);

// POST /api/agent-change-requests/:id/reject
agentChangeRouter.post(
  '/:id/reject',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await loadDecidableChange(id, req.agent);
    await one(
      `UPDATE agent_change_requests SET status = 'rejected', decided_by = $2, decided_at = now() WHERE id = $1 RETURNING id`,
      [id, req.agent.id],
    );
    res.json({ agent_change_request: agentChangeRow(await loadAgentChange(id), { agent: req.agent }) });
  }),
);
