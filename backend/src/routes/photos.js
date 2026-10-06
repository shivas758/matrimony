import { Router } from 'express';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { many, one, query, tx } from '../lib/db.js';
import { asyncHandler, forbidden, notFound } from '../lib/errors.js';
import { deleteStoredPhoto, resolveStoredPath } from '../lib/photos.js';
import { visibilityClause } from '../lib/profiles.js';

export const photosRouter = Router();

/** Loads a photo whose profile the caller can see. */
async function loadVisiblePhoto(photoId, agent) {
  if (!Number.isInteger(photoId) || photoId <= 0) throw notFound('photo_not_found', 'Photo not found');
  const vis = visibilityClause(agent, 2);
  const row = await one(
    `SELECT ph.id, ph.file_path, ph.profile_id, ph.is_primary, p.uploaded_by
       FROM profile_photos ph JOIN profiles p ON p.id = ph.profile_id
      WHERE ph.id = $1 AND ${vis.clause}`,
    [photoId, ...vis.params],
  );
  if (!row) throw notFound('photo_not_found', 'Photo not found');
  return row;
}

// GET /api/photos/:id — authenticated, un-watermarked, in-app only.
photosRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const photo = await loadVisiblePhoto(Number(req.params.id), req.agent);
    const abs = resolveStoredPath(photo.file_path);
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

/** Photo the caller is allowed to modify (uploader or admin). */
async function loadEditablePhoto(photoId, agent) {
  const row = await one(
    `SELECT ph.id, ph.file_path, ph.profile_id, ph.is_primary, p.uploaded_by
       FROM profile_photos ph JOIN profiles p ON p.id = ph.profile_id
      WHERE ph.id = $1`,
    [photoId],
  );
  if (!row) throw notFound('photo_not_found', 'Photo not found');
  if (!agent.is_admin && row.uploaded_by !== agent.id) {
    throw forbidden('not_your_profile', 'Only the agent who added this profile can change its photos');
  }
  return row;
}

// POST /api/photos/:id/primary
photosRouter.post(
  '/:id/primary',
  asyncHandler(async (req, res) => {
    const photo = await loadEditablePhoto(Number(req.params.id), req.agent);
    await tx(async (client) => {
      await client.query('UPDATE profile_photos SET is_primary = FALSE WHERE profile_id = $1', [photo.profile_id]);
      await client.query('UPDATE profile_photos SET is_primary = TRUE WHERE id = $1', [photo.id]);
    });
    const photos = await many(
      `SELECT id, is_primary, sort_order FROM profile_photos
        WHERE profile_id = $1 ORDER BY is_primary DESC, sort_order, id`,
      [photo.profile_id],
    );
    res.json({ photos: photos.map((p) => ({ ...p, url: `/api/photos/${p.id}` })) });
  }),
);

// DELETE /api/photos/:id
photosRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const photo = await loadEditablePhoto(Number(req.params.id), req.agent);
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
