// Gandharva customer routes — SPEC §9.9 / §9.12. Mounted at /api/customer
// behind requireCustomer (req.customer = row + agent + the agent's
// community_ids).
//
// Access (SPEC §9.12): a GUEST (no agent, not approved, or no paid profile)
// may browse cards with a few public fields and primary photos, pick an agent
// and manage their own profiles (once an agent is linked); FULL access
// (active + a paid profile) opens profiles and interests
// (requireFullAccess). Agent change needs an active account.
//
// Every profile object here comes from profilePublic() / protectedFields()
// (lib/profiles.js) — never hand-picked columns — so the customer app can
// never see more than the "before approval" sheet, plus the on-request block
// for their own profile or an accepted, unexpired interest (SPEC §9.8).
// Uploader identity is never sent to a customer.
import { Router } from 'express';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { z } from 'zod';
import { many, one, query, tx } from '../lib/db.js';
import { asyncHandler, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { intQuery, parse, phoneSchema } from '../lib/validate.js';
import { deleteStoredPhoto, resolveStoredPath, watermarkedBuffer } from '../lib/photos.js';
import {
  PROFILE_SELECT,
  deleteProfile,
  customerAccess,
  customerVisibilityClause,
  photoPublic,
  photosByProfile,
  profilePublic,
  protectedFields,
} from '../lib/profiles.js';
import { SORTS, applyListFilters, listQuerySchema } from '../lib/profileQuery.js';
import { config } from '../lib/config.js';
import { confirmPayment, createProfilePayment, paymentPublic } from '../lib/payments.js';
import {
  MAX_PHOTOS,
  addPhotos,
  createProfileRecord,
  loadEditableRow,
  prepareProfileBody,
  updateProfileRecord,
  upload,
} from '../lib/profileWrite.js';
import { agentDirectory } from '../lib/serialize.js';
import {
  AGENT_CHANGE_SELECT,
  CUSTOMER_PHOTO_BASE,
  INTEREST_SELECT,
  agentChangeRow,
  customerAccessLevel,
  deleteRequestRow,
  interestRow,
  loadDeleteRequest,
  loadAgentChange,
  loadCustomerMe,
  loadInterest,
  profileVisibility,
} from '../lib/customers.js';
import { requireActiveCustomer, requireFullAccess, requireNotSuspended } from '../middleware/customerAuth.js';

export const customerRouter = Router();

const DEFAULT_WATERMARK = 'MILI';
const MAX_PROFILES = () => config.payments.maxCustomerProfiles;

/** Public profile shape with photo urls pointing at /api/customer/photos. */
function customerProfilePublic(row, photos, customer) {
  const out = profilePublic(row, { photos, customer });
  out.photos = photos.map((p) => photoPublic(p, CUSTOMER_PHOTO_BASE));
  out.primary_photo_url = out.photos.length ? out.photos[0].url : null;
  return out;
}

/**
 * Own-profile WRITES are allowed while pending (and active) — SPEC §9.9 /
 * §9.2 — but not for a rejected or suspended account: suspension is the stop
 * button, and the profile stays live under the agent's uploads otherwise.
 * Delegates to requireActiveCustomer for the exact 403 code.
 */
function requireProfileEditor(req, res, next) {
  const { status } = req.customer;
  if (status === 'active' || status === 'pending') return next();
  return requireActiveCustomer(req, res, next);
}

// ================================================================ my profile (pending allowed)

/**
 * The id of one of the customer's own profiles: `id` given → that one (404
 * profile_not_found when it is not theirs); null → the OLDEST (the v1.0 app's
 * single profile; 404 no_profile when there is none).
 */
async function ownProfileId(customer, id = null) {
  if (id === null) {
    const row = await one('SELECT id FROM profiles WHERE customer_id = $1 ORDER BY created_at, id LIMIT 1', [
      customer.id,
    ]);
    if (!row) throw notFound('no_profile', 'You have not created your profile yet');
    return row.id;
  }
  if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
  const row = await one('SELECT id FROM profiles WHERE id = $1 AND customer_id = $2', [id, customer.id]);
  if (!row) throw notFound('profile_not_found', 'Profile not found');
  return row.id;
}

/**
 * Own profile: public fields + the on-request block (always granted to its
 * owner) + where it stands with the fee and approval (SPEC §9.12).
 */
async function ownProfileView(customer, id) {
  const row = await one(`${PROFILE_SELECT} WHERE p.id = $1`, [id]);
  if (!row) throw notFound('profile_not_found', 'Profile not found');
  const photos = (await photosByProfile([row.id])).get(row.id);
  const out = customerProfilePublic(row, photos, customer);
  Object.assign(out, protectedFields(row));
  out.contact_access = 'granted';
  out.contact_expires_at = null;
  out.interest = null;
  out.paid = row.paid_at != null;
  out.paid_at = row.paid_at ?? null;
  out.visibility = profileVisibility(row, customer.status);
  out.profile_fee_inr = config.payments.profileFeeInr;
  const pendingDelete = await one(
    `SELECT id, status, reason, created_at FROM profile_delete_requests WHERE profile_id = $1 AND status = 'pending'`,
    [id],
  );
  out.delete_request = pendingDelete ?? null;
  return out;
}

/**
 * Creates the customer's profile (SPEC §9.12 / §9.17): multipart, the agent
 * form minus `status`; always stored hidden — it goes live once paid AND the
 * customer is approved. Owned by the customer's agent. One per customer:
 * 409 profile_limit, also when two saves race past the count (the database
 * keeps one — uq_profiles_one_per_customer, migration 009).
 */
async function createOwnProfile(req) {
  if (!req.customer.agent_id) throw forbidden('agent_required', 'Choose your agent before registering a profile');
  const limitReached = () => conflict('profile_limit', 'You can register only one profile');
  const { n } = await one('SELECT count(*)::int AS n FROM profiles WHERE customer_id = $1', [req.customer.id]);
  if (n >= MAX_PROFILES()) throw limitReached();
  const raw = { ...(req.body ?? {}) };
  delete raw.status;
  const body = await prepareProfileBody(raw, { multipart: true });
  try {
    const { id } = await createProfileRecord({
      uploadedBy: req.customer.agent_id,
      customerId: req.customer.id,
      body,
      files: req.files || [],
      status: 'hidden',
    });
    return id;
  } catch (e) {
    if (e.code === '23505' && e.constraint === 'uq_profiles_one_per_customer') throw limitReached();
    throw e;
  }
}

/** PATCH one own profile — JSON; `status` is ignored (the agent manages it). */
async function patchOwnProfile(req, id) {
  const existing = await loadEditableRow(id);
  const raw = { ...(req.body ?? {}) };
  delete raw.status;
  const body = await prepareProfileBody(raw, { partial: true });
  await updateProfileRecord({ id, existing, body, actorAgentId: req.customer.agent_id });
}

/** Adds photos to one own profile (MAX_PHOTOS in all). */
async function addOwnPhotos(req, id) {
  if (!req.files?.length) throw badRequest('no_photos', 'Attach at least one photo');
  const stats = await one('SELECT count(*)::int AS n FROM profile_photos WHERE profile_id = $1', [id]);
  if (stats.n + req.files.length > MAX_PHOTOS) {
    throw badRequest('too_many_photos', `A profile can have at most ${MAX_PHOTOS} photos`);
  }
  const saved = await addPhotos(id, req.files);
  return saved.map((p) => photoPublic(p, CUSTOMER_PHOTO_BASE));
}

// ---- my profile: one per customer (SPEC §9.12 / §9.17)

// GET /api/customer/my-profiles
customerRouter.get(
  '/my-profiles',
  asyncHandler(async (req, res) => {
    const ids = await many('SELECT id FROM profiles WHERE customer_id = $1 ORDER BY created_at, id', [req.customer.id]);
    const profiles = [];
    for (const { id } of ids) profiles.push(await ownProfileView(req.customer, id));
    res.json({
      profiles,
      max_profiles: MAX_PROFILES(),
      profile_fee_inr: config.payments.profileFeeInr,
      payment_provider: config.payments.provider,
    });
  }),
);

// POST /api/customer/my-profiles — multipart
customerRouter.post(
  '/my-profiles',
  requireProfileEditor,
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const id = await createOwnProfile(req);
    res.status(201).json({ profile: await ownProfileView(req.customer, id) });
  }),
);

// GET /api/customer/my-profiles/:id
customerRouter.get(
  '/my-profiles/:id',
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    res.json({ profile: await ownProfileView(req.customer, id) });
  }),
);

// PATCH /api/customer/my-profiles/:id — JSON
customerRouter.patch(
  '/my-profiles/:id',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    await patchOwnProfile(req, id);
    res.json({ profile: await ownProfileView(req.customer, id) });
  }),
);

// DELETE /api/customer/my-profiles/:id — only while unpaid (a paid profile is
// the agent's to retire).
customerRouter.delete(
  '/my-profiles/:id',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    const row = await one('SELECT paid_at FROM profiles WHERE id = $1', [id]);
    if (row.paid_at) {
      throw conflict('approval_required', 'A paid profile is deleted only with your agent\'s approval — send a delete request');
    }
    await deleteProfile(id);
    res.json({ ok: true });
  }),
);

const deleteRequestSchema = z.object({
  reason: z.string().trim().max(500).optional().nullable().transform((v) => (v ? v : null)),
});

// POST /api/customer/my-profiles/:id/delete-request {reason?} — a PAID profile
// is deleted only when my agent (or an admin) approves (SPEC §9.13).
customerRouter.post(
  '/my-profiles/:id/delete-request',
  requireNotSuspended,
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    const body = parse(deleteRequestSchema, req.body ?? {});
    const row = await one('SELECT full_name, paid_at FROM profiles WHERE id = $1', [id]);
    if (!row.paid_at) throw badRequest('not_paid', 'This profile is not paid for — you can delete it yourself');
    let created;
    try {
      created = await one(
        `INSERT INTO profile_delete_requests (customer_id, profile_id, profile_name, reason)
         VALUES ($1, $2, $3, $4) RETURNING id`,
        [req.customer.id, id, row.full_name, body.reason],
      );
    } catch (e) {
      if (e.code === '23505') throw conflict('already_pending', 'You have already asked to delete this profile');
      throw e;
    }
    res.status(201).json({ delete_request: deleteRequestRow(await loadDeleteRequest(created.id), { customer: req.customer }) });
  }),
);

// POST /api/customer/delete-requests/:id/cancel — while pending.
customerRouter.post(
  '/delete-requests/:id/cancel',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('request_not_found', 'Request not found');
    const row = await one('SELECT id, status FROM profile_delete_requests WHERE id = $1 AND customer_id = $2', [
      id,
      req.customer.id,
    ]);
    if (!row) throw notFound('request_not_found', 'Request not found');
    if (row.status !== 'pending') throw conflict('wrong_status', `This request is already ${row.status}`);
    await query(`UPDATE profile_delete_requests SET status = 'cancelled', decided_at = now() WHERE id = $1`, [id]);
    res.json({ delete_request: deleteRequestRow(await loadDeleteRequest(id), { customer: req.customer }) });
  }),
);

// POST /api/customer/my-profiles/:id/photos
customerRouter.post(
  '/my-profiles/:id/photos',
  requireProfileEditor,
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    res.status(201).json({ photos: await addOwnPhotos(req, id) });
  }),
);

// ---- the registration fee (SPEC §9.12)

// POST /api/customer/my-profiles/:id/payment — starts a checkout.
customerRouter.post(
  '/my-profiles/:id/payment',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer, Number(req.params.id));
    res.status(201).json({ payment: paymentPublic(await createProfilePayment(req.customer, id)) });
  }),
);

const confirmSchema = z.object({
  provider_payment_id: z.string().trim().max(120).optional(),
  signature: z.string().trim().max(256).optional(),
  outcome: z.enum(['success', 'failure']).optional(),
});

// POST /api/customer/payments/:id/confirm → {payment, profile, customer}
customerRouter.post(
  '/payments/:id/confirm',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const body = parse(confirmSchema, req.body ?? {});
    const payment = await confirmPayment(req.customer, Number(req.params.id), body);
    res.json({
      payment: paymentPublic(payment),
      profile: payment.profile_id ? await ownProfileView(req.customer, payment.profile_id) : null,
      customer: await loadCustomerMe(req.customer.id),
    });
  }),
);

// ---- v1.0 single-profile routes: the oldest profile

// GET /api/customer/profile
customerRouter.get(
  '/profile',
  asyncHandler(async (req, res) => {
    res.json({ profile: await ownProfileView(req.customer, await ownProfileId(req.customer)) });
  }),
);

// POST /api/customer/profile — the v1.0 app creates its one profile here.
customerRouter.post(
  '/profile',
  requireProfileEditor,
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const existing = await one('SELECT id FROM profiles WHERE customer_id = $1 LIMIT 1', [req.customer.id]);
    if (existing) throw conflict('profile_exists', 'You already have a profile — edit it instead');
    const id = await createOwnProfile(req);
    res.status(201).json({ profile: await ownProfileView(req.customer, id) });
  }),
);

// PATCH /api/customer/profile
customerRouter.patch(
  '/profile',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer);
    await patchOwnProfile(req, id);
    res.json({ profile: await ownProfileView(req.customer, id) });
  }),
);

// POST /api/customer/profile/photos
customerRouter.post(
  '/profile/photos',
  requireProfileEditor,
  upload.array('photos', MAX_PHOTOS),
  asyncHandler(async (req, res) => {
    const id = await ownProfileId(req.customer);
    res.status(201).json({ photos: await addOwnPhotos(req, id) });
  }),
);

/** A photo on the customer's OWN profile (404 / 403 not_your_profile otherwise). */
async function loadOwnPhoto(photoId, customer) {
  if (!Number.isInteger(photoId) || photoId <= 0) throw notFound('photo_not_found', 'Photo not found');
  const row = await one(
    `SELECT ph.id, ph.file_path, ph.profile_id, ph.is_primary, p.customer_id
       FROM profile_photos ph JOIN profiles p ON p.id = ph.profile_id
      WHERE ph.id = $1`,
    [photoId],
  );
  if (!row) throw notFound('photo_not_found', 'Photo not found');
  if (row.customer_id !== customer.id) throw forbidden('not_your_profile', 'You can only change your own photos');
  return row;
}

// DELETE /api/customer/photos/:id
customerRouter.delete(
  '/photos/:id',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const photo = await loadOwnPhoto(Number(req.params.id), req.customer);
    await query('DELETE FROM profile_photos WHERE id = $1', [photo.id]);
    await deleteStoredPhoto(photo.file_path);
    // Keep exactly one primary photo per profile.
    if (photo.is_primary) {
      const next = await one(
        'SELECT id FROM profile_photos WHERE profile_id = $1 ORDER BY sort_order, id LIMIT 1',
        [photo.profile_id],
      );
      if (next) await query('UPDATE profile_photos SET is_primary = TRUE WHERE id = $1', [next.id]);
    }
    res.json({ ok: true });
  }),
);

// POST /api/customer/photos/:id/primary
customerRouter.post(
  '/photos/:id/primary',
  requireProfileEditor,
  asyncHandler(async (req, res) => {
    const photo = await loadOwnPhoto(Number(req.params.id), req.customer);
    await tx(async (client) => {
      await client.query('UPDATE profile_photos SET is_primary = FALSE WHERE profile_id = $1', [photo.profile_id]);
      await client.query('UPDATE profile_photos SET is_primary = TRUE WHERE id = $1', [photo.id]);
    });
    const photos = await many(
      `SELECT id, is_primary, sort_order FROM profile_photos
        WHERE profile_id = $1 ORDER BY is_primary DESC, sort_order, id`,
      [photo.profile_id],
    );
    res.json({ photos: photos.map((p) => photoPublic(p, CUSTOMER_PHOTO_BASE)) });
  }),
);

// GET /api/customer/photos/:id — own photos plain; anyone else's WATERMARKED
// with the label of the customer's OWN agent — the bureau presenting the
// match, exactly as shares and /p/:token stamp the sharing agent. Never the
// uploader's agency: uploader identity is never sent to a customer (SPEC §9.9,
// §3.3, CLAUDE.md rule 3). Customers never get clean copies of other people's
// photos. Guest access (SPEC §9.12): only the PRIMARY photo of an active
// profile, stamped "MILI".
customerRouter.get(
  '/photos/:id',
  requireNotSuspended,
  asyncHandler(async (req, res) => {
    const photoId = Number(req.params.id);
    if (!Number.isInteger(photoId) || photoId <= 0) throw notFound('photo_not_found', 'Photo not found');
    const access = await customerAccessLevel(req.customer);
    const vis =
      access === 'full' ? customerVisibilityClause(req.customer, 2) : guestVisibilityClause(req.customer, 2);
    const row = await one(
      `SELECT ph.id, ph.file_path, p.customer_id,
              ph.id = (SELECT x.id FROM profile_photos x WHERE x.profile_id = p.id
                        ORDER BY x.is_primary DESC, x.sort_order, x.id LIMIT 1) AS is_first
         FROM profile_photos ph
         JOIN profiles p ON p.id = ph.profile_id
        WHERE ph.id = $1 AND ${vis.clause}`,
      [photoId, ...vis.params],
    );
    if (!row) throw notFound('photo_not_found', 'Photo not found');

    const own = row.customer_id === req.customer.id;
    if (!own) {
      if (access !== 'full' && !row.is_first) {
        throw forbidden('unlock_required', 'Register and get approved to see more photos');
      }
      const label = access === 'full' ? req.customer.agent?.agency_name || DEFAULT_WATERMARK : DEFAULT_WATERMARK;
      const buf = await watermarkedBuffer(row.file_path, label);
      res.set({
        'Content-Type': 'image/jpeg',
        'Content-Length': buf.length,
        'Cache-Control': 'private, max-age=3600',
      });
      return res.send(buf);
    }

    const abs = resolveStoredPath(row.file_path);
    if (!abs) throw notFound('photo_not_found', 'Photo not found');
    let info;
    try {
      info = await stat(abs);
    } catch {
      throw notFound('photo_missing', 'Photo file is no longer on the server');
    }
    res.set({
      'Content-Type': 'image/jpeg',
      'Content-Length': info.size,
      'Cache-Control': 'private, max-age=86400',
    });
    createReadStream(abs).pipe(res);
  }),
);

// ================================================================ browse

/**
 * Guest scope (SPEC §9.12): my own profiles, plus every ACTIVE profile in
 * any community — a teaser; rows are cut down to guestRow().
 */
function guestVisibilityClause(customer, next) {
  return {
    clause: `(p.customer_id = $${next} OR p.status = 'active')`,
    params: [customer.id],
    next: next + 1,
  };
}

const ref = (id, name) => (id ? { id, name } : null);

/** The guest card: photo, age, job, caste, package — nothing else (SPEC §9.12). */
function guestRow(row, photos) {
  const first = photos?.[0];
  return {
    id: row.id,
    gender: row.gender,
    age: row.age,
    community: ref(row.community_id, row.community_name),
    subcaste: ref(row.subcaste_id, row.subcaste_name),
    profession: ref(row.profession_id, row.profession_name),
    occupation_type: ref(row.occupation_type_id, row.occupation_type_name),
    income_text: row.income_text,
    primary_photo_url: first ? `${CUSTOMER_PHOTO_BASE}/${first.id}` : null,
    locked: true,
  };
}

// Same filters as the agent list minus `mine` / `status` (SPEC §9.9).
const customerListSchema = listQuerySchema.omit({ mine: true, status: true });

// GET /api/customer/profiles — full access: active profiles in my agent's
// communities; guest access: active profiles everywhere, as guest cards.
// Never my own. Gender defaults to the opposite of my oldest PAID profile's.
customerRouter.get(
  '/profiles',
  requireNotSuspended,
  asyncHandler(async (req, res) => {
    const f = parse(customerListSchema, req.query);
    const access = await customerAccessLevel(req.customer);
    if (access !== 'full') {
      // Guest cards have no name, so no name search or name sort (SPEC §9.13);
      // every other filter, place included, works.
      delete f.q;
      if (f.sort === 'name') f.sort = 'newest';
    }
    if (!f.gender) {
      const mine = await one(
        `SELECT gender FROM profiles WHERE customer_id = $1 AND paid_at IS NOT NULL ORDER BY created_at, id LIMIT 1`,
        [req.customer.id],
      );
      if (mine) f.gender = mine.gender === 'bride' ? 'groom' : 'bride';
    }

    const where = [];
    const params = [];
    const add = (sql, ...vals) => {
      let i = params.length;
      where.push(sql.replace(/\$#/g, () => `$${++i}`));
      params.push(...vals);
    };

    const vis =
      access === 'full'
        ? customerVisibilityClause(req.customer, params.length + 1)
        : guestVisibilityClause(req.customer, params.length + 1);
    where.push(vis.clause);
    params.push(...vis.params);
    add('p.customer_id IS DISTINCT FROM $#', req.customer.id);
    add(`p.status = 'active'`);
    applyListFilters(f, add);

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const offset = (f.page - 1) * f.limit;
    const { rows: countRows } = await query(`SELECT count(*)::int AS total FROM profiles p ${whereSql}`, params);
    const rows = await many(
      `${PROFILE_SELECT} ${whereSql} ORDER BY ${SORTS[f.sort]} LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, f.limit, offset],
    );

    const ids = rows.map((r) => r.id);
    if (access !== 'full') {
      const photos = await photosByProfile(ids);
      return res.json({
        total: countRows[0].total,
        page: f.page,
        limit: f.limit,
        gender: f.gender ?? null,
        access,
        profiles: rows.map((r) => guestRow(r, photos.get(r.id))),
      });
    }
    const [photos, interests] = await Promise.all([
      photosByProfile(ids),
      ids.length
        ? many(
            `SELECT profile_id, status, (status = 'accepted' AND access_expires_at > now()) AS live
               FROM customer_interests WHERE customer_id = $1 AND profile_id = ANY($2::int[])`,
            [req.customer.id, ids],
          )
        : Promise.resolve([]),
    ]);
    const byProfile = new Map(interests.map((i) => [i.profile_id, i]));

    res.json({
      total: countRows[0].total,
      page: f.page,
      limit: f.limit,
      gender: f.gender ?? null,
      access,
      profiles: rows.map((r) => {
        const out = customerProfilePublic(r, photos.get(r.id), req.customer);
        const it = byProfile.get(r.id);
        out.interest_status = it ? (it.status === 'accepted' && !it.live ? 'expired' : it.status) : null;
        out.is_interested = Boolean(it && (it.status === 'pending' || it.live));
        return out;
      }),
    });
  }),
);

/** One profile the customer may see (own, or active in the agent's communities). */
async function loadVisibleProfile(id, customer) {
  if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
  const vis = customerVisibilityClause(customer, 2);
  const row = await one(`${PROFILE_SELECT} WHERE p.id = $1 AND ${vis.clause}`, [id, ...vis.params]);
  if (!row) throw notFound('profile_not_found', 'Profile not found');
  return row;
}

// GET /api/customer/profiles/:id — public fields + my interest; the on-request
// block only for my own profile or an accepted, unexpired interest.
customerRouter.get(
  '/profiles/:id',
  requireFullAccess,
  asyncHandler(async (req, res) => {
    const row = await loadVisibleProfile(Number(req.params.id), req.customer);
    const photos = (await photosByProfile([row.id])).get(row.id);
    const access = await customerAccess(row, req.customer);
    const out = customerProfilePublic(row, photos, req.customer);
    out.interest = access.interest;
    out.contact_access = access.access;
    out.contact_expires_at = access.expires_at;
    if (access.access === 'granted') Object.assign(out, protectedFields(row));
    res.json({ profile: out });
  }),
);

// ================================================================ interests (active only)

const noteSchema = z.string().trim().max(500).optional().nullable().transform((v) => (v ? v : null));
const interestSchema = z.object({
  note: noteSchema,
  // Which of my profiles is interested (SPEC §9.12); defaulted when unambiguous.
  from_profile_id: z.coerce.number().int().positive().optional().nullable(),
});

// POST /api/customer/profiles/:id/interest {note?} — one row per (customer,
// profile): a withdrawn / declined / revoked / lapsed one goes back to pending.
customerRouter.post(
  '/profiles/:id/interest',
  requireFullAccess,
  asyncHandler(async (req, res) => {
    const body = parse(interestSchema, req.body ?? {});
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
    const vis = customerVisibilityClause(req.customer, 2);
    const profile = await one(
      `SELECT p.id, p.customer_id, p.status, p.gender FROM profiles p WHERE p.id = $1 AND ${vis.clause}`,
      [id, ...vis.params],
    );
    if (!profile) throw notFound('profile_not_found', 'Profile not found');
    if (profile.customer_id === req.customer.id) throw badRequest('own_profile', 'This is your own profile');

    // On whose behalf: one of my paid, live profiles of the other gender.
    const candidates = await many(
      `SELECT id FROM profiles
        WHERE customer_id = $1 AND paid_at IS NOT NULL AND status = 'active' AND gender <> $2
        ORDER BY created_at, id`,
      [req.customer.id, profile.gender],
    );
    let fromProfileId = body.from_profile_id ?? null;
    if (fromProfileId !== null) {
      if (!candidates.some((c) => c.id === fromProfileId)) {
        throw badRequest('invalid_from_profile', 'Pick one of your live profiles');
      }
    } else if (candidates.length === 1) {
      fromProfileId = candidates[0].id;
    } else if (!candidates.length) {
      throw badRequest('no_matching_profile', 'None of your live profiles can express interest in this profile');
    } else {
      throw badRequest('from_profile_required', 'Choose which of your profiles is interested');
    }

    const existing = await one(
      `SELECT id, status, (status = 'accepted' AND access_expires_at > now()) AS live
         FROM customer_interests WHERE customer_id = $1 AND profile_id = $2`,
      [req.customer.id, id],
    );
    if (existing?.status === 'pending') throw conflict('already_pending', 'Your agent is already following this up');
    if (existing?.live) throw conflict('already_accepted', 'This family has already shared their details with you');

    const row = await one(
      `INSERT INTO customer_interests (customer_id, profile_id, note, from_profile_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (customer_id, profile_id) DO UPDATE
         SET status = 'pending', note = EXCLUDED.note, from_profile_id = EXCLUDED.from_profile_id,
             created_at = now(), decided_by = NULL, decided_at = NULL, access_expires_at = NULL
       RETURNING id`,
      [req.customer.id, id, body.note, fromProfileId],
    );
    res.status(201).json({ interest: interestRow(await loadInterest(row.id), { customer: req.customer }) });
  }),
);

// POST /api/customer/interests/:id/withdraw — my pending interest → withdrawn.
customerRouter.post(
  '/interests/:id/withdraw',
  requireFullAccess,
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('interest_not_found', 'Interest not found');
    const row = await one('SELECT id, status FROM customer_interests WHERE id = $1 AND customer_id = $2', [
      id,
      req.customer.id,
    ]);
    if (!row) throw notFound('interest_not_found', 'Interest not found');
    if (row.status !== 'pending') throw conflict('wrong_status', `This interest is already ${row.status}`);
    await query(`UPDATE customer_interests SET status = 'withdrawn', decided_at = now() WHERE id = $1`, [id]);
    res.json({ interest: interestRow(await loadInterest(id), { customer: req.customer }) });
  }),
);

// GET /api/customer/interests — mine, newest first.
customerRouter.get(
  '/interests',
  requireFullAccess,
  asyncHandler(async (req, res) => {
    const rows = await many(`${INTEREST_SELECT} WHERE ci.customer_id = $1 ORDER BY ci.created_at DESC, ci.id DESC`, [
      req.customer.id,
    ]);
    res.json({ interests: rows.map((r) => interestRow(r, { customer: req.customer })) });
  }),
);

// ================================================================ agents / linking / agent change

const agentsSchema = z.object({
  q: z.string().trim().max(80).optional(),
  community_id: intQuery(1),
  city: z.string().trim().max(80).optional(),
});

// GET /api/customer/agents?q=&community_id=&city= — the directory (SPEC §9.6):
// active agents' business details; `is_current` marks mine.
customerRouter.get(
  '/agents',
  requireNotSuspended,
  asyncHandler(async (req, res) => {
    const f = parse(agentsSchema, req.query);
    // Only agents who can actually show profiles (at least one community).
    const where = [`a.status = 'active'`, 'EXISTS (SELECT 1 FROM agent_communities y WHERE y.agent_id = a.id)'];
    const params = [];
    if (f.q) {
      params.push(`%${f.q}%`);
      where.push(`(a.full_name ILIKE $${params.length} OR a.agency_name ILIKE $${params.length})`);
    }
    if (f.city) {
      params.push(`%${f.city}%`);
      where.push(`a.city ILIKE $${params.length}`);
    }
    if (f.community_id !== undefined) {
      params.push(f.community_id);
      where.push(`EXISTS (SELECT 1 FROM agent_communities x WHERE x.agent_id = a.id AND x.community_id = $${params.length})`);
    }
    params.push(req.customer.agent_id ?? 0);
    const rows = await many(
      `SELECT a.id, a.full_name, a.agency_name, a.city, a.phone,
              COALESCE(json_agg(json_build_object('id', c.id, 'name', c.name) ORDER BY c.sort_order, c.name)
                       FILTER (WHERE c.id IS NOT NULL), '[]') AS communities
         FROM agents a
         LEFT JOIN agent_communities ac ON ac.agent_id = a.id
         LEFT JOIN communities c ON c.id = ac.community_id
        WHERE ${where.join(' AND ')}
        GROUP BY a.id
        ORDER BY (a.id = $${params.length}) DESC, a.full_name, a.id`,
      params,
    );
    res.json({
      agents: rows.map((a) => ({ ...agentDirectory(a, a.communities), is_current: a.id === req.customer.agent_id })),
    });
  }),
);

const linkSchema = z
  .object({
    agent_phone: z.preprocess((v) => (v === '' || v === null ? undefined : v), phoneSchema.optional()),
    agent_id: z.coerce.number().int().positive().optional(),
  })
  .refine((b) => b.agent_phone || b.agent_id, { message: "Enter your agent's mobile number" });

// POST /api/customer/agent {agent_phone | agent_id} — a guest (or a pending /
// rejected customer) links an agent and waits for their approval; my
// profiles move with me (SPEC §9.12). Active customers use /agent-change.
customerRouter.post(
  '/agent',
  asyncHandler(async (req, res) => {
    const body = parse(linkSchema, req.body ?? {});
    const { status } = req.customer;
    if (!['guest', 'pending', 'rejected'].includes(status)) {
      throw conflict('wrong_status', status === 'active' ? 'Use Change agent instead' : `Your account is ${status}`);
    }
    const agent = body.agent_id
      ? await one('SELECT id, status FROM agents WHERE id = $1', [body.agent_id])
      : await one('SELECT id, status FROM agents WHERE phone = $1', [body.agent_phone]);
    if (!agent) throw notFound('agent_not_found', 'No agent has this mobile number — check with your agent');
    if (agent.status !== 'active') {
      throw badRequest('agent_not_active', "This agent's account is not active yet — check with your agent");
    }
    // An account with no communities (e.g. the built-in admin) could never show me a profile.
    const hasCommunity = await one('SELECT 1 FROM agent_communities WHERE agent_id = $1 LIMIT 1', [agent.id]);
    if (!hasCommunity) throw badRequest('agent_has_no_communities', 'This number cannot take customers — check with your agent');
    if (status === 'pending' && agent.id === req.customer.agent_id) {
      throw badRequest('same_agent', 'You are already waiting for this agent');
    }
    await tx(async (client) => {
      await client.query(
        `UPDATE customers SET agent_id = $2, status = 'pending', updated_at = now() WHERE id = $1`,
        [req.customer.id, agent.id],
      );
      await client.query('UPDATE profiles SET uploaded_by = $2, updated_at = now() WHERE customer_id = $1', [
        req.customer.id,
        agent.id,
      ]);
    });
    res.json({ customer: await loadCustomerMe(req.customer.id) });
  }),
);

const changeSchema = z.object({
  to_agent_id: z.coerce.number().int().positive('Pick an agent'),
  note: noteSchema,
});

// POST /api/customer/agent-change {to_agent_id, note?} — asks my CURRENT agent
// to release me to another active agent (SPEC §9.6).
customerRouter.post(
  '/agent-change',
  requireActiveCustomer,
  asyncHandler(async (req, res) => {
    const body = parse(changeSchema, req.body ?? {});
    if (body.to_agent_id === req.customer.agent_id) throw badRequest('same_agent', 'That is already your agent');

    const target = await one('SELECT id, status FROM agents WHERE id = $1', [body.to_agent_id]);
    if (!target) throw notFound('agent_not_found', 'Agent not found');
    if (target.status !== 'active') throw badRequest('agent_not_active', 'That agent is not active');

    const pending = await one(
      `SELECT id FROM agent_change_requests WHERE customer_id = $1 AND status = 'pending'`,
      [req.customer.id],
    );
    if (pending) throw conflict('already_pending', 'You already have a pending request — cancel it first');

    const row = await one(
      `INSERT INTO agent_change_requests (customer_id, from_agent_id, to_agent_id, note)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [req.customer.id, req.customer.agent_id, body.to_agent_id, body.note],
    );
    res.status(201).json({ agent_change_request: agentChangeRow(await loadAgentChange(row.id), { customer: req.customer }) });
  }),
);

// POST /api/customer/agent-change/:id/cancel — while pending.
customerRouter.post(
  '/agent-change/:id/cancel',
  requireActiveCustomer,
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('request_not_found', 'Request not found');
    const row = await one('SELECT id, status FROM agent_change_requests WHERE id = $1 AND customer_id = $2', [
      id,
      req.customer.id,
    ]);
    if (!row) throw notFound('request_not_found', 'Request not found');
    if (row.status !== 'pending') throw conflict('wrong_status', `This request is already ${row.status}`);
    await query(`UPDATE agent_change_requests SET status = 'cancelled', decided_at = now() WHERE id = $1`, [id]);
    res.json({ agent_change_request: agentChangeRow(await loadAgentChange(id), { customer: req.customer }) });
  }),
);

// GET /api/customer/agent-change — my requests, newest first.
customerRouter.get(
  '/agent-change',
  requireActiveCustomer,
  asyncHandler(async (req, res) => {
    const rows = await many(
      `${AGENT_CHANGE_SELECT} WHERE r.customer_id = $1 ORDER BY r.created_at DESC, r.id DESC`,
      [req.customer.id],
    );
    res.json({ agent_change_requests: rows.map((r) => agentChangeRow(r, { customer: req.customer })) });
  }),
);
