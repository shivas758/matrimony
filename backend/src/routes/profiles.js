import { Router } from 'express';
import { many, one, query } from '../lib/db.js';
import { asyncHandler, badRequest, forbidden, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import {
  PROFILE_SELECT,
  contactAccess,
  deleteProfile,
  holdState,
  photosByProfile,
  photoPublic,
  profilePublic,
  protectedFields,
  visibilityClause,
} from '../lib/profiles.js';
import { SORTS, applyListFilters, listQuerySchema } from '../lib/profileQuery.js';
import {
  MAX_PHOTOS,
  addPhotos,
  createProfileRecord,
  loadEditableRow,
  prepareProfileBody,
  resolveSubcaste,
  updateProfileRecord,
  upload,
} from '../lib/profileWrite.js';

export const profilesRouter = Router();

// Re-exported for the routes that grew up importing them from here
// (share.js, contactRequests.js, holdRequests.js, shortlists.js, tests).
export { MAX_PHOTOS, resolveSubcaste };

// ---------------------------------------------------------------- list

// GET /api/profiles
profilesRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const f = parse(listQuerySchema, req.query);

    const where = [];
    const params = [];
    const add = (sql, ...vals) => {
      let i = params.length;
      where.push(sql.replace(/\$#/g, () => `$${++i}`));
      params.push(...vals);
    };

    const vis = visibilityClause(req.agent, params.length + 1);
    where.push(vis.clause);
    params.push(...vis.params);

    if (f.mine === 'true') add('p.uploaded_by = $#', req.agent.id);
    // Non-admins can only narrow within what visibilityClause already allows.
    if (f.status) add('p.status = $#', f.status);
    // The search filters are shared with the customer list (lib/profileQuery.js).
    applyListFilters(f, add);

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const offset = (f.page - 1) * f.limit;

    const { rows: countRows } = await query(
      `SELECT count(*)::int AS total FROM profiles p ${whereSql}`,
      params,
    );
    const rows = await many(
      `${PROFILE_SELECT} ${whereSql} ORDER BY ${SORTS[f.sort]} LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, f.limit, offset],
    );

    const photos = await photosByProfile(rows.map((r) => r.id));
    res.json({
      total: countRows[0].total,
      page: f.page,
      limit: f.limit,
      profiles: rows.map((r) => profilePublic(r, { photos: photos.get(r.id), agent: req.agent })),
    });
  }),
);

// ---------------------------------------------------------------- create

// POST /api/profiles (multipart: fields + photos[])
profilesRouter.post(
  '/',
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const body = await prepareProfileBody(req.body, { multipart: true });

    // Agents may only upload into their own communities; admins anywhere.
    // (Customers may pick any community — that check belongs here, not in the lib.)
    if (!req.agent.is_admin && !req.agent.community_ids.includes(body.community_id)) {
      throw forbidden('community_not_allowed', 'You can only add profiles in your own communities');
    }
    const { id } = await createProfileRecord({ uploadedBy: req.agent.id, body, files: req.files || [] });
    res.status(201).json({ profile: await loadDetail(id, req.agent) });
  }),
);

// ---------------------------------------------------------------- detail

/** Loads one visible profile row or throws 404. */
export async function loadRow(id, agent) {
  if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
  const vis = visibilityClause(agent, 2);
  const row = await one(`${PROFILE_SELECT} WHERE p.id = $1 AND ${vis.clause}`, [id, ...vis.params]);
  if (!row) throw notFound('profile_not_found', 'Profile not found');
  return row;
}

/** Detail payload with the contact rule applied (SPEC §3.2). */
export async function loadDetail(id, agent) {
  const row = await loadRow(id, agent);
  const photos = (await photosByProfile([row.id])).get(row.id);
  const access = await contactAccess(row, agent);
  const out = profilePublic(row, { photos, agent });

  out.contact_access = access.access;
  out.contact_expires_at = access.expires_at;
  // Raw status lets the app distinguish "rejected" from "never requested".
  out.contact_request_status = access.request_status;
  out.contact_request_id = access.request_id;

  // The on-request fields travel together (SPEC §3.2 / §9.8): native place,
  // birth place, work place, parents, contact person, siblings, family, property.
  if (access.access === 'granted') Object.assign(out, protectedFields(row));
  // Uploader identity — and which Gandharva account owns the profile — stay
  // hidden from other agents (CLAUDE.md rule 3).
  const owner = agent.is_admin || row.uploaded_by === agent.id;
  if (owner) {
    out.uploaded_by = row.uploaded_by;
    out.customer_id = row.customer_id ?? null;
  }
  out.can_edit = owner;
  // Deleting is the same circle as editing (SPEC §4: uploader or admin).
  out.can_delete = out.can_edit;

  // Hold workflow: my latest request, plus (uploader/admin) who holds it now.
  const hold = await holdState(row, agent);
  out.hold_request_status = hold.request_status;
  out.hold_request_id = hold.request_id;
  if ('held_by' in hold) {
    out.held_by = hold.held_by;
    out.pending_hold_requests = hold.pending_count;
  }
  return out;
}

// GET /api/profiles/:id
profilesRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    res.json({ profile: await loadDetail(Number(req.params.id), req.agent) });
  }),
);

// ---------------------------------------------------------------- update / delete

/** Throws unless the caller uploaded the profile or is an admin. */
async function assertCanEdit(id, agent) {
  const row = await loadEditableRow(id);
  if (!agent.is_admin && row.uploaded_by !== agent.id) {
    throw forbidden('not_your_profile', 'Only the agent who added this profile can change it');
  }
  return row;
}

// PATCH /api/profiles/:id — uploader or admin
profilesRouter.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = await assertCanEdit(id, req.agent);
    const body = await prepareProfileBody(req.body, { partial: true });

    if (body.community_id && !req.agent.is_admin && !req.agent.community_ids.includes(body.community_id)) {
      throw forbidden('community_not_allowed', 'You can only use your own communities');
    }
    await updateProfileRecord({ id, existing, body, actorAgentId: req.agent.id });
    res.json({ profile: await loadDetail(id, req.agent) });
  }),
);

// DELETE /api/profiles/:id — uploader or admin (SPEC §4). Hard delete, photos
// included; hiding is still the gentler option and the app says so.
profilesRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await assertCanEdit(id, req.agent);
    await deleteProfile(id);
    res.json({ ok: true });
  }),
);

// ---------------------------------------------------------------- photos

// POST /api/profiles/:id/photos
profilesRouter.post(
  '/:id/photos',
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    await assertCanEdit(id, req.agent);
    if (!req.files?.length) throw badRequest('no_photos', 'Attach at least one photo');

    const stats = await one('SELECT count(*)::int AS n FROM profile_photos WHERE profile_id = $1', [id]);
    if (stats.n + req.files.length > MAX_PHOTOS) {
      throw badRequest('too_many_photos', `A profile can have at most ${MAX_PHOTOS} photos`);
    }
    const saved = await addPhotos(id, req.files);
    // Not `.map(photoPublic)`: the index would land in photoPublic's url-base argument.
    res.status(201).json({ photos: saved.map((p) => photoPublic(p)) });
  }),
);
