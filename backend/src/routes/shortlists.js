import { Router } from 'express';
import { z } from 'zod';
import { many, one, query } from '../lib/db.js';
import { asyncHandler, conflict, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { displayName, hiddenSet } from '../lib/privacy.js';
import { loadRow } from './profiles.js';

// Mounted at /api/profiles
export const profileShortlistRouter = Router();
// Mounted at /api/shortlists
export const shortlistsRouter = Router();

const addSchema = z.object({
  client_label: z.string().trim().max(120).default('').transform((v) => v || ''),
});

// POST /api/profiles/:id/shortlist {client_label}
profileShortlistRouter.post(
  '/:id/shortlist',
  asyncHandler(async (req, res) => {
    const body = parse(addSchema, req.body ?? {});
    const profile = await loadRow(Number(req.params.id), req.agent);

    const existing = await one(
      'SELECT id FROM shortlists WHERE agent_id = $1 AND profile_id = $2 AND client_label = $3',
      [req.agent.id, profile.id, body.client_label],
    );
    if (existing) throw conflict('already_shortlisted', 'Already in this client’s shortlist');

    const row = await one(
      `INSERT INTO shortlists (agent_id, profile_id, client_label)
       VALUES ($1,$2,$3) RETURNING id, profile_id, client_label, created_at`,
      [req.agent.id, profile.id, body.client_label],
    );
    res.status(201).json({ shortlist: row });
  }),
);

// GET /api/shortlists — grouped by client label (SPEC §5 screen 8).
// Rows are list rows: PUBLIC fields only (SPEC §3.2 / §9.8, CLAUDE.md rule 4).
// The native place (`city`) is on request — never here; the public location
// is the work / NRI country, as on the list cards.
shortlistsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const rows = await many(
      `SELECT s.id, s.client_label, s.created_at,
              p.id AS profile_id, p.full_name, p.gender, p.status, p.hidden_fields, p.uploaded_by,
              date_part('year', age(p.dob))::int AS age,
              c.name AS community_name,
              wc.name AS work_country_name,
              CASE WHEN p.is_nri THEN co.name END AS nri_country_name,
              -- A live contact approval lifts the family's privacy toggles (SPEC §9.18 D).
              EXISTS (SELECT 1 FROM contact_requests cr
                       WHERE cr.profile_id = p.id AND cr.requester_id = $1
                         AND cr.status = 'approved' AND cr.expires_at > now()) AS has_access,
              (SELECT ph.id FROM profile_photos ph WHERE ph.profile_id = p.id
                ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1) AS photo_id
         FROM shortlists s
         JOIN profiles p ON p.id = s.profile_id
         JOIN communities c ON c.id = p.community_id
         LEFT JOIN countries wc ON wc.id = p.work_country_id
         LEFT JOIN countries co ON co.id = p.nri_country_id
        WHERE s.agent_id = $1
        ORDER BY s.client_label, s.created_at DESC`,
      [req.agent.id],
    );

    const groups = new Map();
    for (const r of rows) {
      const key = r.client_label || '';
      if (!groups.has(key)) groups.set(key, []);
      // What the family switched off stays off here too, unless the profile is
      // my own upload or I currently hold contact access (SPEC §9.18 D).
      const reveal = req.agent.is_admin || r.uploaded_by === req.agent.id || Boolean(r.has_access);
      const hidden = reveal ? new Set() : hiddenSet(r.hidden_fields);
      const place = !hidden.has('work_location');
      groups.get(key).push({
        shortlist_id: r.id,
        profile_id: r.profile_id,
        full_name: displayName({ id: r.profile_id, full_name: r.full_name, hidden_fields: r.hidden_fields }, reveal),
        name_hidden: hidden.has('name'),
        gender: r.gender,
        age: r.age,
        work_country: place ? r.work_country_name ?? null : null,
        nri_country: place ? r.nri_country_name ?? null : null,
        community: hidden.has('community') ? null : r.community_name,
        status: r.status,
        photo_url: r.photo_id ? `/api/photos/${r.photo_id}` : null,
        created_at: r.created_at,
      });
    }

    res.json({
      groups: [...groups.entries()].map(([client_label, profiles]) => ({
        client_label,
        count: profiles.length,
        profiles,
      })),
    });
  }),
);

// GET /api/shortlists/labels — for the "add to shortlist" picker.
shortlistsRouter.get(
  '/labels',
  asyncHandler(async (req, res) => {
    const rows = await many(
      `SELECT client_label, count(*)::int AS count FROM shortlists
        WHERE agent_id = $1 GROUP BY client_label ORDER BY client_label`,
      [req.agent.id],
    );
    res.json({ labels: rows });
  }),
);

// DELETE /api/shortlists/:id
shortlistsRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const row = await one('SELECT id FROM shortlists WHERE id = $1 AND agent_id = $2', [id, req.agent.id]);
    if (!row) throw notFound('shortlist_not_found', 'Shortlist entry not found');
    await query('DELETE FROM shortlists WHERE id = $1', [id]);
    res.json({ ok: true });
  }),
);
