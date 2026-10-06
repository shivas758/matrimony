import { Router } from 'express';
import { z } from 'zod';
import { many, one, tx } from '../lib/db.js';
import { asyncHandler, conflict, forbidden, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { loadRow } from './profiles.js';

// The HOLD workflow (SPEC §2 hold_requests, §4).
//  * any active agent who can see a profile may ask to put it on hold
//    (their client is in talks with this family);
//  * the uploader or an admin approves or rejects — an approved hold flips the
//    profile to status 'on_hold', hiding it from everyone except the holder;
//  * the uploader, an admin or the holder releases it, which makes it active again;
//  * holds placed by the uploader/admin themselves are approved on the spot.
// Rows are never deleted: the table doubles as the hold log (CLAUDE.md rule 5).

// Mounted at /api/profiles — the request-creating half.
export const profileHoldRouter = Router();
// Mounted at /api/hold-requests — listing and decisions.
export const holdRequestsRouter = Router();

const requestSchema = z.object({
  note: z.string().trim().max(500).optional().nullable().transform((v) => (v ? v : null)),
});

const LIST_SELECT = `
  SELECT h.id, h.profile_id, h.requester_id, h.status, h.note,
         h.requested_at, h.decided_by, h.decided_at, h.released_by, h.released_at,
         p.full_name AS profile_name, p.gender AS profile_gender, p.status AS profile_status,
         p.uploaded_by, c.name AS profile_community,
         r.full_name AS requester_name, r.agency_name AS requester_agency, r.phone AS requester_phone,
         (SELECT ph.id FROM profile_photos ph
           WHERE ph.profile_id = p.id ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1) AS photo_id
    FROM hold_requests h
    JOIN profiles p ON p.id = h.profile_id
    JOIN communities c ON c.id = p.community_id
    JOIN agents r ON r.id = h.requester_id`;

/**
 * API shape. `requester` only for the inbox (the approver must know who is
 * asking); the sent box never exposes the uploader's identity (CLAUDE.md rule 3).
 */
function shape(row, { includeRequester = false, viewerId = null } = {}) {
  return {
    id: row.id,
    profile_id: row.profile_id,
    profile_name: row.profile_name,
    profile_gender: row.profile_gender,
    profile_community: row.profile_community,
    profile_status: row.profile_status,
    profile_photo_url: row.photo_id ? `/api/photos/${row.photo_id}` : null,
    status: row.status,
    note: row.note,
    requested_at: row.requested_at,
    decided_at: row.decided_at,
    released_at: row.released_at,
    is_mine: viewerId !== null && row.requester_id === viewerId,
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

async function reload(id, agent) {
  const row = await one(`${LIST_SELECT} WHERE h.id = $1`, [id]);
  return shape(row, {
    includeRequester: agent.is_admin || row.uploaded_by === agent.id,
    viewerId: agent.id,
  });
}

// POST /api/profiles/:id/hold-request  {note}
profileHoldRouter.post(
  '/:id/hold-request',
  asyncHandler(async (req, res) => {
    const body = parse(requestSchema, req.body ?? {});
    // loadRow enforces community visibility — no holding what you cannot see.
    const profile = await loadRow(Number(req.params.id), req.agent);
    const decides = req.agent.is_admin || profile.uploaded_by === req.agent.id;

    if (profile.status === 'on_hold') {
      throw conflict('already_on_hold', 'This profile is already on hold');
    }
    if (profile.status !== 'active') {
      throw conflict('not_active', 'Only active profiles can be put on hold');
    }
    const pending = await one(
      `SELECT id FROM hold_requests WHERE profile_id = $1 AND requester_id = $2 AND status = 'pending'`,
      [profile.id, req.agent.id],
    );
    if (pending) throw conflict('already_pending', 'Your hold request is already waiting for approval');

    const created = await tx(async (client) => {
      if (decides) {
        // The approver is the one asking — nobody else to wait for.
        const { rows } = await client.query(
          `INSERT INTO hold_requests (profile_id, requester_id, note, status, decided_by, decided_at)
           VALUES ($1, $2, $3, 'approved', $2, now()) RETURNING id`,
          [profile.id, req.agent.id, body.note],
        );
        await client.query(
          `UPDATE profiles SET status = 'on_hold', updated_at = now() WHERE id = $1`,
          [profile.id],
        );
        return rows[0];
      }
      const { rows } = await client.query(
        `INSERT INTO hold_requests (profile_id, requester_id, note) VALUES ($1, $2, $3) RETURNING id`,
        [profile.id, req.agent.id, body.note],
      );
      return rows[0];
    });
    res.status(201).json({ hold_request: await reload(created.id, req.agent) });
  }),
);

// ---------------------------------------------------------------- listing

const listSchema = z.object({
  box: z.enum(['inbox', 'sent']).default('inbox'),
  status: z.enum(['pending', 'approved', 'rejected', 'cancelled', 'released']).optional(),
});

// GET /api/hold-requests?box=inbox|sent[&status]
holdRequestsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(listSchema, req.query);
    const where = [];
    const params = [];

    if (f.box === 'sent') {
      params.push(req.agent.id);
      where.push(`h.requester_id = $${params.length}`);
    } else if (!req.agent.is_admin) {
      // Admins see every inbox request, like contact requests (SPEC §4).
      params.push(req.agent.id);
      where.push(`p.uploaded_by = $${params.length}`);
    }
    if (f.status) {
      params.push(f.status);
      where.push(`h.status = $${params.length}`);
    }

    const rows = await many(
      `${LIST_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY CASE h.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
                h.requested_at DESC`,
      params,
    );
    res.json({
      box: f.box,
      hold_requests: rows.map((r) =>
        shape(r, { includeRequester: f.box === 'inbox', viewerId: req.agent.id }),
      ),
    });
  }),
);

// ---------------------------------------------------------------- decisions

async function loadHold(id) {
  if (!Number.isInteger(id) || id <= 0) throw notFound('request_not_found', 'Hold request not found');
  const row = await one(
    `SELECT h.*, p.uploaded_by, p.status AS profile_status FROM hold_requests h
       JOIN profiles p ON p.id = h.profile_id WHERE h.id = $1`,
    [id],
  );
  if (!row) throw notFound('request_not_found', 'Hold request not found');
  return row;
}

const isDecider = (row, agent) => agent.is_admin || row.uploaded_by === agent.id;

// POST /api/hold-requests/:id/approve — uploader or admin
holdRequestsRouter.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadHold(id);
    if (!isDecider(row, req.agent)) {
      throw forbidden('not_your_request', 'Only the agent who added this profile or an admin can approve a hold');
    }
    if (row.status !== 'pending') throw conflict('already_decided', `This request is already ${row.status}`);
    if (row.profile_status === 'on_hold') throw conflict('already_on_hold', 'This profile is already on hold');
    if (row.profile_status !== 'active') throw conflict('not_active', 'Only active profiles can be put on hold');

    await tx(async (client) => {
      await client.query(
        `UPDATE hold_requests SET status = 'approved', decided_by = $2, decided_at = now() WHERE id = $1`,
        [id, req.agent.id],
      );
      // One holder at a time: other open requests on this profile are turned down.
      await client.query(
        `UPDATE hold_requests SET status = 'rejected', decided_by = $3, decided_at = now()
          WHERE profile_id = $1 AND status = 'pending' AND id <> $2`,
        [row.profile_id, id, req.agent.id],
      );
      await client.query(
        `UPDATE profiles SET status = 'on_hold', updated_at = now() WHERE id = $1`,
        [row.profile_id],
      );
    });
    res.json({ hold_request: await reload(id, req.agent) });
  }),
);

// POST /api/hold-requests/:id/reject — uploader or admin
holdRequestsRouter.post(
  '/:id/reject',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadHold(id);
    if (!isDecider(row, req.agent)) {
      throw forbidden('not_your_request', 'Only the agent who added this profile or an admin can reject a hold');
    }
    if (row.status !== 'pending') throw conflict('already_decided', `This request is already ${row.status}`);
    await one(
      `UPDATE hold_requests SET status = 'rejected', decided_by = $2, decided_at = now()
        WHERE id = $1 RETURNING id`,
      [id, req.agent.id],
    );
    res.json({ hold_request: await reload(id, req.agent) });
  }),
);

// POST /api/hold-requests/:id/release — uploader, admin, or the holder
holdRequestsRouter.post(
  '/:id/release',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadHold(id);
    if (!isDecider(row, req.agent) && row.requester_id !== req.agent.id) {
      throw forbidden('not_your_hold', 'Only the holder, the uploader or an admin can release this hold');
    }
    if (row.status !== 'approved') throw conflict('not_on_hold', 'Only an approved hold can be released');

    await tx(async (client) => {
      await client.query(
        `UPDATE hold_requests SET status = 'released', released_by = $2, released_at = now() WHERE id = $1`,
        [id, req.agent.id],
      );
      await client.query(
        `UPDATE profiles SET status = 'active', updated_at = now() WHERE id = $1 AND status = 'on_hold'`,
        [row.profile_id],
      );
    });
    res.json({ hold_request: await reload(id, req.agent) });
  }),
);

// POST /api/hold-requests/:id/cancel — the requester withdraws a pending request
holdRequestsRouter.post(
  '/:id/cancel',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await loadHold(id);
    if (row.requester_id !== req.agent.id) {
      throw forbidden('not_your_request', 'Only the agent who asked for this hold can cancel it');
    }
    if (row.status !== 'pending') throw conflict('already_decided', `This request is already ${row.status}`);
    await one(`UPDATE hold_requests SET status = 'cancelled' WHERE id = $1 RETURNING id`, [id]);
    res.json({ hold_request: await reload(id, req.agent) });
  }),
);
