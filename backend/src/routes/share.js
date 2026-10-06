import { Router } from 'express';
import { z } from 'zod';
import { config } from '../lib/config.js';
import { many, one, query } from '../lib/db.js';
import { asyncHandler, conflict, forbidden, notFound } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { photosByProfile, profilePublic } from '../lib/profiles.js';
import { formatDob, formatHeight, nriLabel, renderProfileCard } from '../lib/card.js';
import { renderProfilePdf } from '../lib/pdf.js';
import { loadRow } from './profiles.js';

// Mounted at /api/profiles
export const profileShareRouter = Router();
// Mounted at /api/share-tokens
export const shareTokensRouter = Router();

// 'whatsapp'/'link' → public masked page; 'download' → JPEG card; 'pdf' → A4 bio-data.
const shareSchema = z.object({ method: z.enum(['whatsapp', 'link', 'download', 'pdf']) });

export const DEFAULT_AGENCY_LABEL = 'Mediator';

/** Finds or creates the active public token for a profile. */
async function activeToken(profileId, agentId) {
  const existing = await one(
    'SELECT id, token FROM share_tokens WHERE profile_id = $1 AND active = TRUE ORDER BY id LIMIT 1',
    [profileId],
  );
  if (existing) return existing;
  return one(
    'INSERT INTO share_tokens (profile_id, created_by) VALUES ($1, $2) RETURNING id, token',
    [profileId, agentId],
  );
}

/**
 * One-line summary safe to paste into WhatsApp. Nothing on request (SPEC §3.3
 * / §9.8): no contacts, uploader, native place, parents, work place or NRI
 * place — the work country (when abroad) / NRI country are the only location.
 */
export function shareSummary(profile) {
  const workCountry = profile.work_country?.name;
  const bits = [
    `${profile.gender === 'bride' ? 'Bride' : 'Groom'}: ${profile.full_name}`,
    profile.age ? `${profile.age} yrs${profile.dob ? ` (${formatDob(profile.dob)})` : ''}` : null,
    profile.height_cm ? formatHeight(profile.height_cm) : null,
    profile.religion?.name,
    profile.community?.name,
    profile.subcaste?.name,
    profile.gothram ? `Gothram ${profile.gothram}` : null,
    profile.mother_tongue?.name,
    profile.education?.name,
    profile.profession?.name,
    workCountry && workCountry.toLowerCase() !== 'india' && !profile.is_nri ? `Works in ${workCountry}` : null,
    nriLabel(profile),
  ].filter(Boolean);
  return bits.join(' | ');
}

// POST /api/profiles/:id/share  {method}
profileShareRouter.post(
  '/:id/share',
  asyncHandler(async (req, res) => {
    const { method } = parse(shareSchema, req.body ?? {});
    const row = await loadRow(Number(req.params.id), req.agent);
    // A Gandharva profile reaches nobody outside until its fee is paid (SPEC §9.12).
    if (row.customer_id && !row.paid_at) {
      throw conflict('payment_required', 'The customer has not paid the registration fee for this profile yet');
    }
    const photos = (await photosByProfile([row.id])).get(row.id);
    const profile = profilePublic(row, { photos, agent: req.agent });
    const agencyLabel = req.agent.agency_name || DEFAULT_AGENCY_LABEL;

    // Every share is logged (CLAUDE.md rule 5).
    await query('INSERT INTO share_logs (profile_id, agent_id, method) VALUES ($1,$2,$3)', [
      row.id,
      req.agent.id,
      method,
    ]);

    if (method === 'download') {
      const card = await renderProfileCard({ ...profile, __photoPath: photos[0]?.file_path }, { agencyLabel });
      res.set({
        'Content-Type': 'image/jpeg',
        'Content-Disposition': `attachment; filename="${slug(profile.full_name)}.jpg"`,
        'Content-Length': card.length,
      });
      return res.send(card);
    }

    if (method === 'pdf') {
      const pdf = await renderProfilePdf(profile, {
        agencyLabel,
        photoPaths: photos.map((p) => p.file_path),
      });
      res.set({
        'Content-Type': 'application/pdf',
        'Content-Disposition': `attachment; filename="${slug(profile.full_name)}-profile.pdf"`,
        'Content-Length': pdf.length,
      });
      return res.send(pdf);
    }

    const token = await activeToken(row.id, req.agent.id);
    const share_url = `${config.publicBaseUrl}/p/${token.token}`;
    const summary = shareSummary(profile);
    res.json({
      share_url,
      share_token_id: token.id,
      summary,
      // Ready to hand to url_launcher on the app side.
      whatsapp_text: `${summary}\n\nView full profile: ${share_url}`,
    });
  }),
);

const slug = (s) =>
  String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'profile';

// GET /api/profiles/:id/share-tokens — uploader or admin
profileShareRouter.get(
  '/:id/share-tokens',
  asyncHandler(async (req, res) => {
    const row = await loadRow(Number(req.params.id), req.agent);
    if (!req.agent.is_admin && row.uploaded_by !== req.agent.id) {
      throw forbidden('not_your_profile', 'Only the agent who added this profile can manage its links');
    }
    const tokens = await many(
      `SELECT id, token, active, created_at FROM share_tokens WHERE profile_id = $1 ORDER BY id DESC`,
      [row.id],
    );
    res.json({
      share_tokens: tokens.map((t) => ({ ...t, url: `${config.publicBaseUrl}/p/${t.token}` })),
    });
  }),
);

// POST /api/share-tokens/:id/deactivate — uploader or admin (SPEC §4)
shareTokensRouter.post(
  '/:id/deactivate',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('token_not_found', 'Share link not found');
    const row = await one(
      `SELECT st.id, st.profile_id, p.uploaded_by FROM share_tokens st
         JOIN profiles p ON p.id = st.profile_id WHERE st.id = $1`,
      [id],
    );
    if (!row) throw notFound('token_not_found', 'Share link not found');
    if (!req.agent.is_admin && row.uploaded_by !== req.agent.id) {
      throw forbidden('not_your_profile', 'Only the agent who added this profile can deactivate its links');
    }
    await query('UPDATE share_tokens SET active = FALSE WHERE id = $1', [id]);
    res.json({ ok: true });
  }),
);
