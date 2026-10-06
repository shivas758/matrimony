import { Router } from 'express';
import { z } from 'zod';
import { config } from '../lib/config.js';
import { many, one } from '../lib/db.js';
import { asyncHandler, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { loadRow } from './profiles.js';

// Mounted at /api/profiles — the request-creating half of the workflow.
export const profileContactRouter = Router();
// Mounted at /api/contact-requests — listing and decisions.
export const contactRequestsRouter = Router();

const requestSchema = z.object({
  note: z.string().trim().max(500).optional().nullable().transform((v) => (v ? v : null)),
});

// POST /api/profiles/:id/contact-request
profileContactRouter.post(
  '/:id/contact-request',
  asyncHandler(async (req, res) => {
    const body = parse(requestSchema, req.body ?? {});
    // loadRow enforces community visibility — no requesting profiles you can't see.
    const profile = await loadRow(Number(req.params.id), req.agent);

    if (profile.uploaded_by === req.agent.id) {
      throw badRequest('own_profile', 'You already have the contact details for your own upload');
    }
    if (req.agent.is_admin) {
      throw badRequest('admin_has_access', 'Admins can already see contact details');
    }

    const existing = await one(
      `SELECT id, status, (status = 'approved' AND expires_at > now()) AS live
         FROM contact_requests
        WHERE profile_id = $1 AND requester_id = $2
        ORDER BY requested_at DESC LIMIT 1`,
      [profile.id, req.agent.id],
    );
    if (existing?.status === 'pending') {
      throw conflict('already_pending', 'Your request is already waiting for approval');
    }
    if (existing?.live) {
      throw conflict('already_approved', 'You already have access to these contact details');
    }

    const created = await one(
      `INSERT INTO contact_requests (profile_id, requester_id, note) VALUES ($1, $2, $3) RETURNING id`,
      [profile.id, req.agent.id, body.note],
    );
    // Re-read through LIST_SELECT so the app gets the same shape as the list.
    res.status(201).json({ contact_request: shape(await one(`${LIST_SELECT} WHERE cr.id = $1`, [created.id])) });
  }),
);

// ---------------------------------------------------------------- listing

const LIST_SELECT = `
  SELECT cr.id, cr.profile_id, cr.requester_id, cr.status, cr.note,
         cr.requested_at, cr.decided_by, cr.decided_at, cr.expires_at,
         -- Computed in SQL so the countdown uses one clock, not Node's and the DB's.
         CASE WHEN cr.status = 'approved' AND cr.expires_at > now()
              THEN CEIL(EXTRACT(EPOCH FROM (cr.expires_at - now())) / 86400)::int
         END AS days_left,
         (cr.status = 'approved' AND cr.expires_at <= now()) AS is_expired,
         p.full_name AS profile_name, p.gender AS profile_gender, p.uploaded_by,
         c.name AS profile_community,
         r.full_name AS requester_name, r.agency_name AS requester_agency, r.phone AS requester_phone,
         (SELECT ph.id FROM profile_photos ph
           WHERE ph.profile_id = p.id ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1) AS photo_id
    FROM contact_requests cr
    JOIN profiles p ON p.id = cr.profile_id
    JOIN communities c ON c.id = p.community_id
    JOIN agents r ON r.id = cr.requester_id`;

/**
 * API shape. `requester` is included only in the inbox (the approver needs to
 * know who is asking); the sent box never exposes the uploader's identity.
 */
function shape(row, { includeRequester = false } = {}) {
  const expired = Boolean(row.is_expired);
  const daysLeft = row.days_left ?? null;

  return {
    id: row.id,
    profile_id: row.profile_id,
    profile_name: row.profile_name,
    profile_gender: row.profile_gender,
    profile_community: row.profile_community,
    profile_photo_url: row.photo_id ? `/api/photos/${row.photo_id}` : null,
    status: expired ? 'expired' : row.status,
    note: row.note,
    requested_at: row.requested_at,
    decided_at: row.decided_at,
    expires_at: row.expires_at,
    days_left: daysLeft,
    ...(includeRequester
      ? {
          requester: {
            id: row.requester_id,
            full_name: row.requester_name,
            agency_name: row.requester_agency,
            phone: row.requester_phone,
          },
        }
      : {}),
  };
}

const listSchema = z.object({
  box: z.enum(['inbox', 'sent']).default('inbox'),
  status: z.enum(['pending', 'approved', 'rejected', 'revoked', 'expired']).optional(),
});

// GET /api/contact-requests?box=inbox|sent
contactRequestsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(listSchema, req.query);
    const where = [];
    const params = [];

    if (f.box === 'sent') {
      params.push(req.agent.id);
      where.push(`cr.requester_id = $${params.length}`);
    } else if (req.agent.is_admin) {
      // Admins see every inbox request (SPEC §4).
    } else {
      params.push(req.agent.id);
      where.push(`p.uploaded_by = $${params.length}`);
    }

    if (f.status === 'expired') {
      where.push(`(cr.status = 'expired' OR (cr.status = 'approved' AND cr.expires_at <= now()))`);
    } else if (f.status === 'approved') {
      where.push(`cr.status = 'approved' AND cr.expires_at > now()`);
    } else if (f.status) {
      params.push(f.status);
      where.push(`cr.status = $${params.length}`);
    }

    const rows = await many(
      `${LIST_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY CASE WHEN cr.status = 'pending' THEN 0 ELSE 1 END, cr.requested_at DESC`,
      params,
    );
    res.json({
      box: f.box,
      contact_requests: rows.map((r) => shape(r, { includeRequester: f.box === 'inbox' })),
    });
  }),
);

// ---------------------------------------------------------------- decisions

/** Loads a request the caller is allowed to decide on (uploader or admin). */
async function loadDecidable(id, agent) {
  if (!Number.isInteger(id) || id <= 0) throw notFound('request_not_found', 'Request not found');
  const row = await one(
    `SELECT cr.*, p.uploaded_by FROM contact_requests cr
       JOIN profiles p ON p.id = cr.profile_id WHERE cr.id = $1`,
    [id],
  );
  if (!row) throw notFound('request_not_found', 'Request not found');
  if (!agent.is_admin && row.uploaded_by !== agent.id) {
    throw forbidden('not_your_request', 'Only the agent who added this profile can decide this request');
  }
  return row;
}

/** Re-reads a decided request with the joins so the response matches the list shape. */
async function reload(id, agent) {
  const row = await one(`${LIST_SELECT} WHERE cr.id = $1`, [id]);
  return shape(row, { includeRequester: !agent || agent.is_admin || row.uploaded_by === agent.id });
}

// POST /api/contact-requests/:id/approve — grants access for CONTACT_ACCESS_DAYS (default 15).
contactRequestsRouter.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidable(id, req.agent);
    if (row.status !== 'pending') {
      throw conflict('already_decided', `This request is already ${row.status}`);
    }
    await one(
      `UPDATE contact_requests
          SET status = 'approved', decided_by = $2, decided_at = now(),
              expires_at = now() + make_interval(days => $3)
        WHERE id = $1 RETURNING id`,
      [id, req.agent.id, config.contactAccessDays],
    );
    res.json({ contact_request: await reload(id, req.agent) });
  }),
);

// POST /api/contact-requests/:id/reject
contactRequestsRouter.post(
  '/:id/reject',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidable(id, req.agent);
    if (row.status !== 'pending') {
      throw conflict('already_decided', `This request is already ${row.status}`);
    }
    await one(
      `UPDATE contact_requests SET status = 'rejected', decided_by = $2, decided_at = now(), expires_at = NULL
        WHERE id = $1 RETURNING id`,
      [id, req.agent.id],
    );
    res.json({ contact_request: await reload(id, req.agent) });
  }),
);

// POST /api/contact-requests/:id/revoke — admin or the agent who approved it (SPEC §4).
contactRequestsRouter.post(
  '/:id/revoke',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadDecidable(id, req.agent);
    if (row.status !== 'approved') {
      throw conflict('not_approved', 'Only an approved request can be revoked');
    }
    if (!req.agent.is_admin && row.decided_by !== req.agent.id) {
      throw forbidden('not_the_approver', 'Only an admin or the approving agent can revoke this');
    }
    await one(
      `UPDATE contact_requests SET status = 'revoked', expires_at = now() WHERE id = $1 RETURNING id`,
      [id],
    );
    res.json({ contact_request: await reload(id, req.agent) });
  }),
);

/**
 * Tidies stale rows: approved + past expiry -> 'expired'.
 * Read-time checks already treat these as expired; this keeps the table honest.
 */
export async function expireStaleApprovals() {
  const { rowCount } = await one(
    `WITH updated AS (
       UPDATE contact_requests SET status = 'expired'
        WHERE status = 'approved' AND expires_at IS NOT NULL AND expires_at <= now()
        RETURNING 1)
     SELECT count(*)::int AS "rowCount" FROM updated`,
  );
  return rowCount;
}
