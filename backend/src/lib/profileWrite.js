// Profile create / update machinery shared by the agent routes
// (routes/profiles.js), the Gandharva customer routes (/api/customer/profile)
// and the public registration form (/r/:token) — SPEC §4 Profiles, §9.3, §9.7,
// §9.9. Everything that validates a profile body and writes the profiles row
// (+ languages, education levels, photos) lives here so the three entry points
// can never disagree on the rules (NRI, siblings, subcaste scoping, masters).
//
// Permission checks stay in the routes: an agent may only upload into their own
// communities, a customer may pick any community, an admin anything.

import multer from 'multer';
import { z } from 'zod';
import { one, pool, tx } from './db.js';
import { badRequest, conflict, notFound } from './errors.js';
import { parse } from './validate.js';
import { EDUCATION_LEVELS, setEducationLevels, setKnownLanguages } from './profiles.js';
import { deleteStoredPhoto, storeProfilePhoto } from './photos.js';

export const MAX_PHOTOS = 8;

/**
 * Multer instance for profile photos (SPEC §4: max 8, 10 MB each).
 * HEIC/HEIF is refused up front: the prebuilt libvips sharp ships with has no
 * HEVC decoder (on linux/arm64 too), so admitting it only produced a decode
 * failure after the whole upload. Anything that still cannot be decoded is
 * mapped to 400 unreadable_image in addPhotos().
 */
export const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: MAX_PHOTOS },
  fileFilter: (_req, file, cb) => {
    if (/^image\/(jpe?g|png|webp)$/i.test(file.mimetype)) return cb(null, true);
    cb(badRequest('unsupported_image', 'Photos must be JPG, PNG or WEBP'));
  },
});

// ---------------------------------------------------------------- schema

const nullableText = (max) =>
  z.string().trim().max(max).optional().nullable().transform((v) => (v ? v : null));

const nullableInt = (min, max) =>
  z
    .union([z.number(), z.string()])
    .optional()
    .nullable()
    .transform((v) => (v === undefined || v === null || v === '' ? null : Number(v)))
    .refine((n) => n === null || (Number.isInteger(n) && n >= min && n <= max), {
      message: `Must be a whole number between ${min} and ${max}`,
    });

/** Multipart sends booleans as strings; accept true/false/1/0 in either form. */
const looseBoolean = z
  .union([z.boolean(), z.string(), z.number()])
  .transform((v) => v === true || v === 1 || /^(true|1|yes|on)$/i.test(String(v)));

/** Tri-state boolean: undefined = untouched, null/'' = not recorded. */
const nullableBoolean = z
  .union([z.boolean(), z.string(), z.number()])
  .optional()
  .nullable()
  .transform((v) => {
    if (v === undefined) return undefined;
    if (v === null || v === '' || v === 'null') return null;
    return v === true || v === 1 || /^(true|1|yes|on)$/i.test(String(v));
  });

/**
 * A list of master ids: JSON array, comma-separated string, or a repeated
 * multipart field. undefined = untouched, []/''/null = clear.
 */
const idListBody = z
  .union([z.array(z.union([z.number(), z.string()])), z.string(), z.number()])
  .optional()
  .nullable()
  .transform((v) => {
    if (v === undefined) return undefined;
    if (v === null || v === '') return [];
    const parts = (Array.isArray(v) ? v : [v]).flatMap((s) => String(s).split(','));
    const ids = parts.map((s) => Number(s.trim())).filter((n) => Number.isInteger(n) && n > 0);
    return [...new Set(ids)];
  });

/** One row of the registration form's education table (SPEC §9.7). */
const educationLevelSchema = z.object({
  level: z.enum(EDUCATION_LEVELS, { message: `Level must be one of ${EDUCATION_LEVELS.join(', ')}` }),
  details: nullableText(300),
  country_id: z.coerce.number().int().positive().optional().nullable(),
});

/**
 * education_levels: a JSON array, or (multipart) a JSON string, of
 * {level, details?, country_id?}. undefined = untouched, []/''/null = clear.
 * The set is replaced on write; a duplicated level is a validation error.
 */
const educationLevelsBody = z.preprocess(
  (v) => {
    if (v === undefined) return undefined;
    if (v === null || v === '') return [];
    if (typeof v === 'string') {
      try {
        const parsed = JSON.parse(v);
        return parsed === null ? [] : parsed;
      } catch {
        return v; // fails the array check below → 400 validation_failed
      }
    }
    return v;
  },
  z
    .array(educationLevelSchema)
    .max(EDUCATION_LEVELS.length)
    .superRefine((levels, ctx) => {
      const seen = new Set();
      for (const lv of levels) {
        if (seen.has(lv.level)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Education level "${lv.level}" is listed twice` });
        }
        seen.add(lv.level);
      }
    })
    .optional(),
);

export const profileBodySchema = z.object({
  full_name: z.string().trim().min(2, 'Enter the full name').max(120),
  gender: z.enum(['bride', 'groom'], { message: 'Gender must be bride or groom' }),
  dob: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'Date of birth must be YYYY-MM-DD')
    .refine((s) => {
      const d = new Date(`${s}T00:00:00Z`);
      if (Number.isNaN(d.getTime())) return false;
      const years = (Date.now() - d.getTime()) / (365.2425 * 24 * 3600 * 1000);
      return years >= 18 && years <= 100;
    }, 'Age must be between 18 and 100'),
  height_cm: z.coerce.number().int().min(100).max(250).optional().nullable(),
  weight_kg: nullableInt(25, 250),
  complexion_id: z.coerce.number().int().positive().optional().nullable(),
  religion_id: z.coerce.number().int().positive().optional().nullable(),
  mother_tongue_id: z.coerce.number().int().positive().optional().nullable(),
  known_language_ids: idListBody,
  food_habit_id: z.coerce.number().int().positive().optional().nullable(),
  marital_status_id: z.coerce.number().int().positive().optional().nullable(),
  community_id: z.coerce.number().int().positive('Select a community'),
  // Either an existing subcaste id, or free text that is found-or-created under community_id.
  subcaste_id: z.coerce.number().int().positive().optional().nullable(),
  subcaste_name: nullableText(80),
  gothram: nullableText(80),
  nationality_id: z.coerce.number().int().positive().optional().nullable(),
  education_id: z.coerce.number().int().positive().optional().nullable(),
  education_details: nullableText(500),
  // The registration form's education table (SPEC §9.7).
  education_levels: educationLevelsBody,
  profession_id: z.coerce.number().int().positive().optional().nullable(),
  profession_details: nullableText(500),
  occupation_type_id: z.coerce.number().int().positive().optional().nullable(),
  // Public coarse location (SPEC §9.8); the exact work_place is on request.
  work_country_id: z.coerce.number().int().positive().optional().nullable(),
  income_text: nullableText(80),
  other_income: nullableText(80),
  is_nri: looseBoolean.optional(),
  nri_country_id: z.coerce.number().int().positive().optional().nullable(),
  zodiac_id: z.coerce.number().int().positive().optional().nullable(),
  nakshatram_id: z.coerce.number().int().positive().optional().nullable(),
  // Horoscope birth time — public like star/rasi. Time is "HH:MM" 24-hour; an
  // empty string clears it.
  birth_time: z
    .string()
    .trim()
    .optional()
    .nullable()
    .transform((v) => (v ? v : null))
    .refine((v) => v === null || /^([01]\d|2[0-3]):[0-5]\d$/.test(v), {
      message: 'Birth time must be HH:MM (24-hour)',
    }),
  about: nullableText(4000),
  status: z.enum(['active', 'engaged', 'married', 'hidden', 'on_hold']).optional(),
  // ---- PROTECTED ("on request", SPEC §3.2 / §9.8): birth place, work place,
  // NRI place, siblings, family, property, native place, parents, contact person.
  birth_place: nullableText(120),
  birth_state: nullableText(80),
  birth_country_id: z.coerce.number().int().positive().optional().nullable(),
  work_place: nullableText(120),
  nri_place: nullableText(120),
  // Siblings: has_siblings null = not recorded, false = none, true = counts + details.
  has_siblings: nullableBoolean,
  siblings_count: nullableInt(0, 20),
  siblings_details: nullableText(2000),
  elder_sisters: nullableInt(0, 20),
  younger_sisters: nullableInt(0, 20),
  elder_brothers: nullableInt(0, 20),
  younger_brothers: nullableInt(0, 20),
  family_details: nullableText(4000),
  property_share: nullableText(500),
  property_details: nullableText(4000),
  city: nullableText(80),
  state: nullableText(80),
  father_name: nullableText(120),
  father_occupation: nullableText(120),
  father_phone: nullableText(20),
  mother_name: nullableText(120),
  mother_occupation: nullableText(120),
  mother_phone: nullableText(20),
  contact_name: nullableText(120),
  contact_phone: nullableText(20),
});

export const patchSchema = profileBodySchema.partial();

/**
 * The profiles columns a body may write, in INSERT order. Virtual body keys
 * (subcaste_name, known_language_ids, education_levels) are handled apart;
 * uploaded_by / customer_id / subcaste_id / status are set by the writer.
 */
const PROFILE_COLUMNS = [
  'full_name', 'gender', 'dob', 'height_cm', 'weight_kg', 'complexion_id', 'marital_status_id',
  'community_id', 'gothram', 'nationality_id',
  'education_id', 'education_details', 'profession_id', 'profession_details', 'occupation_type_id',
  'work_place', 'work_country_id', 'income_text', 'other_income',
  'is_nri', 'nri_country_id', 'nri_place',
  'zodiac_id', 'nakshatram_id', 'birth_time', 'birth_place', 'birth_state', 'birth_country_id',
  'religion_id', 'mother_tongue_id', 'food_habit_id', 'about',
  'has_siblings', 'siblings_count', 'siblings_details',
  'elder_sisters', 'younger_sisters', 'elder_brothers', 'younger_brothers',
  'family_details', 'property_share', 'property_details',
  'city', 'state', 'father_name', 'father_occupation', 'father_phone',
  'mother_name', 'mother_occupation', 'mother_phone', 'contact_name', 'contact_phone',
];
const UPDATABLE_COLUMNS = new Set([...PROFILE_COLUMNS, 'subcaste_id', 'status']);

// ---------------------------------------------------------------- body rules

/** Multipart sends everything as strings; drop empties so partial updates work. */
export function normaliseMultipart(body) {
  const out = {};
  for (const [k, v] of Object.entries(body || {})) {
    if (v === '' || v === 'null' || v === 'undefined') continue;
    out[k] = v;
  }
  return out;
}

/**
 * An NRI country/place only make sense on an NRI profile. Clears them when
 * is_nri is (or becomes) false so a stale country never leaks into filters.
 */
export function applyNriRule(body, currentlyNri) {
  const nri = body.is_nri ?? currentlyNri;
  if (nri === false) {
    if ('is_nri' in body || 'nri_country_id' in body || 'nri_place' in body) {
      body.nri_country_id = null;
      body.nri_place = null;
    }
  }
}

const SIBLING_COUNTS = ['siblings_count', 'elder_sisters', 'younger_sisters', 'elder_brothers', 'younger_brothers'];
const SIBLING_KEYS = ['has_siblings', 'siblings_details', ...SIBLING_COUNTS];

/**
 * Siblings counts/details only mean something when has_siblings is true.
 * "No siblings" stores every count as 0; "not recorded" stores nulls.
 */
export function applySiblingsRule(body, currentHas) {
  if (!SIBLING_KEYS.some((k) => k in body)) return;
  const has = body.has_siblings === undefined ? currentHas ?? null : body.has_siblings;
  if (has === true) return;
  const count = has === false ? 0 : null;
  for (const k of SIBLING_COUNTS) body[k] = count;
  body.siblings_details = null;
}

const FK_CHECKS = [
  ['community_id', 'communities'],
  ['subcaste_id', 'subcastes'],
  ['education_id', 'educations'],
  ['profession_id', 'professions'],
  ['occupation_type_id', 'occupation_types'],
  ['marital_status_id', 'marital_statuses'],
  ['complexion_id', 'complexions'],
  ['religion_id', 'religions'],
  ['mother_tongue_id', 'languages'],
  ['food_habit_id', 'food_habits'],
  ['nationality_id', 'countries'],
  ['birth_country_id', 'countries'],
  ['work_country_id', 'countries'],
  ['nri_country_id', 'countries'],
  ['zodiac_id', 'zodiac_signs'],
  ['nakshatram_id', 'nakshatrams'],
];

/** Every master reference in the body must exist (400 invalid_reference otherwise). */
export async function assertMastersExist(data) {
  for (const [field, table] of FK_CHECKS) {
    const id = data[field];
    if (id === undefined || id === null) continue;
    const row = await one(`SELECT id FROM ${table} WHERE id = $1`, [id]);
    if (!row) throw badRequest('invalid_reference', `Unknown ${field.replace(/_id$/, '').replace(/_/g, ' ')}`);
  }
  if (data.known_language_ids?.length) {
    const found = await one('SELECT count(*)::int AS n FROM languages WHERE id = ANY($1::int[])', [
      data.known_language_ids,
    ]);
    if (found.n !== data.known_language_ids.length) throw badRequest('invalid_reference', 'Unknown language');
  }
  const countryIds = [...new Set((data.education_levels ?? []).map((lv) => lv.country_id).filter(Boolean))];
  if (countryIds.length) {
    const found = await one('SELECT count(*)::int AS n FROM countries WHERE id = ANY($1::int[])', [countryIds]);
    if (found.n !== countryIds.length) throw badRequest('invalid_reference', 'Unknown education country');
  }
}

/**
 * Validates a raw request body into a profile body: zod parse (multipart
 * bodies are normalised first) + master existence checks. `partial` selects
 * the PATCH schema. Returns the parsed body; throws 400 on any problem.
 */
export async function prepareProfileBody(raw, { partial = false, multipart = false } = {}) {
  const data = multipart ? normaliseMultipart(raw) : raw ?? {};
  const body = parse(partial ? patchSchema : profileBodySchema, data);
  await assertMastersExist(body);
  return body;
}

// ---------------------------------------------------------------- subcaste

const first = async (client, sql, params) => (await client.query(sql, params)).rows[0] ?? null;

/**
 * Resolves the subcaste for a profile in `communityId` (SPEC §2).
 *  - subcaste_id given  → must belong to communityId, else 400 subcaste_mismatch
 *  - subcaste_name given → find (case-insensitive) or create under communityId.
 *                          This is how agents grow the list by typing.
 *  - neither            → null
 * `client` is a pg client inside a transaction, or the pool.
 */
export async function resolveSubcaste(body, communityId, client = pool) {
  if (body.subcaste_id) {
    const row = await first(client, 'SELECT id, community_id FROM subcastes WHERE id = $1', [body.subcaste_id]);
    if (!row) throw badRequest('invalid_reference', 'Unknown subcaste');
    if (row.community_id !== communityId) {
      throw badRequest('subcaste_mismatch', 'That subcaste belongs to a different community');
    }
    return row.id;
  }
  const name = String(body.subcaste_name ?? '').replace(/\s+/g, ' ').trim();
  if (!name) return null;

  const find = () =>
    first(client, 'SELECT id FROM subcastes WHERE community_id = $1 AND lower(name) = lower($2)', [
      communityId,
      name,
    ]);
  const existing = await find();
  if (existing) return existing.id;

  const created = await first(
    client,
    `INSERT INTO subcastes (community_id, name, sort_order)
     VALUES ($1, $2, (SELECT COALESCE(max(sort_order), 0) + 1 FROM subcastes WHERE community_id = $1))
     ON CONFLICT DO NOTHING
     RETURNING id`,
    [communityId, name],
  );
  // ON CONFLICT covers a concurrent insert of the same name; re-read in that case.
  return created ? created.id : (await find()).id;
}

// ---------------------------------------------------------------- photos

/**
 * Stores uploaded files and links them; the first photo on a profile is
 * primary. `client` is a pg client inside a transaction (required when the
 * profile row itself is not committed yet), or the pool.
 */
export async function addPhotos(profileId, files, client = pool) {
  if (!files?.length) return [];
  const stats = await first(
    client,
    `SELECT count(*)::int AS n,
            COALESCE(max(sort_order), -1)::int AS max_sort,
            bool_or(is_primary) AS has_primary
       FROM profile_photos WHERE profile_id = $1`,
    [profileId],
  );
  let sort = stats.max_sort + 1;
  let hasPrimary = Boolean(stats.has_primary);

  const saved = [];
  for (const file of files) {
    let relPath;
    try {
      relPath = await storeProfilePhoto(profileId, file.buffer);
    } catch {
      // sharp throws a plain Error for anything libvips cannot decode (a
      // truncated JPEG, a mislabelled file). That is the caller's input, not a
      // server fault: answer 400 (the registration form turns it into a
      // banner) and take back what this call already stored — the files would
      // otherwise stay orphaned on disk when the caller's transaction rolls back.
      for (const s of saved) {
        await client.query('DELETE FROM profile_photos WHERE id = $1', [s.id]);
        await deleteStoredPhoto(s.file_path);
      }
      throw badRequest('unreadable_image', 'One of the photos could not be read — use a JPG or PNG');
    }
    const primary = !hasPrimary;
    hasPrimary = true;
    const row = await first(
      client,
      `INSERT INTO profile_photos (profile_id, file_path, is_primary, sort_order)
       VALUES ($1,$2,$3,$4) RETURNING id, file_path, is_primary, sort_order`,
      [profileId, relPath, primary, sort++],
    );
    saved.push(row);
  }
  return saved;
}

// ---------------------------------------------------------------- create

/**
 * Inserts a profile from a body produced by prepareProfileBody() (non-partial):
 * resolves the subcaste, applies the NRI and siblings rules, writes every
 * column, then the known languages, education levels and photos.
 *
 *  uploadedBy  the owning agent (a customer's profile belongs to their agent)
 *  customerId  the Gandharva account that owns it, or null (SPEC §9.2)
 *  status      overrides body.status; default 'active' (registration stores 'hidden')
 *  client      a pg client when the caller owns the transaction (registration
 *              creates customer + profile together); otherwise one is opened here.
 * Returns { id }.
 */
export async function createProfileRecord({ uploadedBy, customerId = null, body, files = [], status, client }) {
  const data = { ...body };
  data.is_nri = data.is_nri ?? false;
  applyNriRule(data, false);
  data.has_siblings = data.has_siblings ?? null;
  applySiblingsRule(data, null);

  const run = async (c) => {
    const record = {};
    for (const col of PROFILE_COLUMNS) record[col] = data[col] ?? null;
    record.is_nri = Boolean(data.is_nri);
    record.uploaded_by = uploadedBy;
    record.customer_id = customerId;
    record.subcaste_id = await resolveSubcaste(data, data.community_id, c);
    record.status = status ?? data.status ?? 'active';

    const cols = Object.keys(record);
    const { rows } = await c.query(
      `INSERT INTO profiles (${cols.join(', ')})
       VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})
       RETURNING id`,
      cols.map((k) => record[k]),
    );
    const id = rows[0].id;
    if (data.known_language_ids?.length) await setKnownLanguages(c, id, data.known_language_ids);
    if (data.education_levels?.length) await setEducationLevels(c, id, data.education_levels);
    await addPhotos(id, files, c);
    return { id };
  };
  return client ? run(client) : tx(run);
}

// ---------------------------------------------------------------- update

/** The columns a PATCH needs to apply the rules; throws 404 when the profile is gone. */
export async function loadEditableRow(id) {
  if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
  const row = await one(
    'SELECT id, uploaded_by, customer_id, community_id, is_nri, has_siblings, status, paid_at FROM profiles WHERE id = $1',
    [id],
  );
  if (!row) throw notFound('profile_not_found', 'Profile not found');
  return row;
}

/**
 * Applies a partial body (prepareProfileBody with partial: true) to a profile:
 * subcaste scoping to the (possibly new) community, the NRI and siblings
 * rules, known languages, education levels, and — when `status` moves to or
 * from on_hold — the hold_requests side effects credited to `actorAgentId`
 * (SPEC §2 hold_requests). Callers check permission (and drop `status` for
 * customers) first. 400 nothing_to_update when the body is empty.
 */
export async function updateProfileRecord({ id, existing, body, actorAgentId }) {
  const data = { ...body };

  // An unpaid Gandharva profile stays hidden until its fee is paid (SPEC §9.12).
  if (data.status && data.status !== 'hidden' && existing.customer_id && !existing.paid_at) {
    throw conflict('payment_required', 'The customer has not paid the registration fee for this profile yet');
  }

  // Subcaste is scoped to the (possibly new) community.
  const effectiveCommunity = data.community_id ?? existing.community_id;
  if ('subcaste_id' in data || 'subcaste_name' in data) {
    data.subcaste_id = await resolveSubcaste(data, effectiveCommunity);
    delete data.subcaste_name; // not a column
  } else if (data.community_id && data.community_id !== existing.community_id) {
    data.subcaste_id = null; // old subcaste no longer applies to the new community
  }
  applyNriRule(data, existing.is_nri);
  applySiblingsRule(data, existing.has_siblings);

  // Known languages and education levels live in their own tables, not columns.
  const languageIds = data.known_language_ids;
  delete data.known_language_ids;
  const educationLevels = data.education_levels;
  delete data.education_levels;

  const keys = Object.keys(data).filter((k) => UPDATABLE_COLUMNS.has(k) && data[k] !== undefined);
  if (!keys.length && languageIds === undefined && educationLevels === undefined) {
    throw badRequest('nothing_to_update', 'No fields supplied');
  }

  // Status edits to/from on_hold keep the hold log in step (SPEC §2 hold_requests):
  // the uploader/admin putting a profile on hold is an approved hold by them;
  // moving it off hold releases whoever was holding it.
  const goesOnHold = data.status === 'on_hold' && existing.status !== 'on_hold';
  const leavesHold = existing.status === 'on_hold' && Boolean(data.status) && data.status !== 'on_hold';

  const sets = keys.map((k, i) => `${k} = $${i + 2}`);
  await tx(async (client) => {
    if (keys.length) {
      await client.query(
        `UPDATE profiles SET ${sets.join(', ')}, updated_at = now() WHERE id = $1`,
        [id, ...keys.map((k) => data[k])],
      );
    } else {
      await client.query('UPDATE profiles SET updated_at = now() WHERE id = $1', [id]);
    }
    if (languageIds !== undefined) await setKnownLanguages(client, id, languageIds);
    if (educationLevels !== undefined) await setEducationLevels(client, id, educationLevels);
    if (goesOnHold) {
      await client.query(
        `INSERT INTO hold_requests (profile_id, requester_id, status, decided_by, decided_at)
         VALUES ($1, $2, 'approved', $2, now())`,
        [id, actorAgentId],
      );
    }
    if (leavesHold) {
      await client.query(
        `UPDATE hold_requests SET status = 'released', released_by = $2, released_at = now()
          WHERE profile_id = $1 AND status = 'approved'`,
        [id, actorAgentId],
      );
    }
  });
}
