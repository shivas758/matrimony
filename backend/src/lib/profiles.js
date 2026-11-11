import { many, one, query } from './db.js';
import { deleteStoredPhoto } from './photos.js';
import { displayName, hiddenSet, mask } from './privacy.js';

/**
 * An interest that is still "in play" (SPEC §9.4): pending, or accepted with
 * an unexpired window. Alias `ci`. An accepted row whose window lapsed is
 * reported as 'expired' everywhere (interestRow, customerAccess) and must not
 * keep granting anything.
 */
export const LIVE_INTEREST = `(ci.status = 'pending' OR (ci.status = 'accepted' AND ci.access_expires_at > now()))`;

/**
 * "Shown to" (SPEC §9.18 E): a profile is shown to its own community, and to
 * the extra communities its family chose — or to every community. `$n` is an
 * int[] of the viewer's communities; profiles aliased `p`.
 */
export const shownToSql = (n) =>
  `(p.community_id = ANY($${n}::int[]) OR p.audience_all OR p.audience_community_ids && $${n}::int[])`;

/**
 * Visibility SQL for the profiles table (CLAUDE.md rule 1, SPEC §3.1 / §9.18 E).
 * Agents: active profiles shown to one of their communities, plus all their
 * own uploads. Admins: everything.
 * Returns a { clause, params } fragment; `next` is the next $n placeholder index.
 */
export function visibilityClause(agent, next) {
  if (agent.is_admin) return { clause: 'TRUE', params: [], next };
  const shown = shownToSql(next + 1);
  // Third branch: a profile on hold stays visible to the agent whose hold was
  // approved — they are the ones in talks — but to nobody else.
  // Fourth branch (SPEC §9.4): a customer who marked interest in one of my
  // uploads becomes visible to me while that interest is pending/accepted,
  // even outside my communities — I need to see who is asking. "While" is
  // literal: only the community test is relaxed, never the status test of
  // §3.1 (a hidden / engaged / married / on-hold customer profile stays
  // invisible), and an accepted interest counts only until its window ends —
  // nothing ever moves a lapsed row off 'accepted', every other read treats
  // it as 'expired' (LIVE_INTEREST).
  return {
    clause: `(p.uploaded_by = $${next}
      OR (p.status = 'active' AND ${shown})
      OR (p.status = 'on_hold' AND ${shown}
          AND EXISTS (SELECT 1 FROM hold_requests h
                       WHERE h.profile_id = p.id AND h.requester_id = $${next} AND h.status = 'approved'))
      OR (p.customer_id IS NOT NULL AND p.status = 'active'
          -- only the customer profile that expressed the interest (SPEC §9.12)
          AND EXISTS (SELECT 1 FROM customer_interests ci JOIN profiles t ON t.id = ci.profile_id
                       WHERE ci.from_profile_id = p.id AND t.uploaded_by = $${next}
                         AND ${LIVE_INTEREST})))`,
    params: [agent.id, agent.community_ids],
    next: next + 2,
  };
}

/**
 * Visibility for a Gandharva customer (SPEC §9.9 / §9.18 E): their own
 * profile, plus active profiles in their agent's communities, profiles shown
 * to every community, and profiles whose audience includes the community of
 * the customer's OWN profile. `customer.community_ids` are the agent's
 * communities, `customer.own_community_ids` the community of their profile
 * (both loaded by requireCustomer).
 */
export function customerVisibilityClause(customer, next) {
  return {
    clause: `(p.customer_id = $${next}
      OR (p.status = 'active'
          AND (p.community_id = ANY($${next + 1}::int[]) OR p.audience_all
               OR p.audience_community_ids && $${next + 2}::int[])))`,
    params: [customer.id, customer.community_ids || [], customer.own_community_ids || []],
    next: next + 3,
  };
}

const EDUCATION_LEVEL_ORDER = `ARRAY['below_10th','10th','intermediate','graduation','post_graduation']`;
export const EDUCATION_LEVELS = ['below_10th', '10th', 'intermediate', 'graduation', 'post_graduation'];

export const PROFILE_SELECT = `
  SELECT p.id, p.uploaded_by, p.customer_id, p.paid_at, p.full_name, p.gender, p.dob, p.height_cm, p.weight_kg,
         p.profile_code, p.hidden_fields, p.audience_all, p.audience_community_ids,
         COALESCE((SELECT json_agg(json_build_object('id', au.id, 'name', au.name) ORDER BY au.sort_order, au.name)
                     FROM communities au WHERE au.id = ANY(p.audience_community_ids)), '[]'::json) AS audience_communities,
         p.gothram, p.education_details, p.profession_details, p.work_place,
         p.income_text, p.other_income, p.is_nri, p.nri_place, p.about, p.family_details,
         p.has_siblings, p.siblings_count, p.siblings_details,
         p.elder_sisters, p.younger_sisters, p.elder_brothers, p.younger_brothers,
         p.property_share, p.property_details,
         p.status, p.created_at, p.updated_at,
         to_char(p.birth_time, 'HH24:MI') AS birth_time, p.birth_place, p.birth_state,
         p.city, p.state, p.father_name, p.father_occupation, p.father_phone,
         p.mother_name, p.mother_occupation, p.mother_phone,
         p.contact_name, p.contact_phone,
         date_part('year', age(p.dob))::int AS age,
         c.id AS community_id, c.name AS community_name,
         sc.id AS subcaste_id, sc.name AS subcaste_name,
         e.id AS education_id, e.name AS education_name,
         pr.id AS profession_id, pr.name AS profession_name,
         ot.id AS occupation_type_id, ot.name AS occupation_type_name,
         ms.id AS marital_status_id, ms.name AS marital_status_name,
         cx.id AS complexion_id, cx.name AS complexion_name,
         co.id AS nri_country_id, co.name AS nri_country_name,
         wc.id AS work_country_id, wc.name AS work_country_name,
         na.id AS nationality_id, na.name AS nationality_name,
         bc.id AS birth_country_id, bc.name AS birth_country_name,
         z.id AS zodiac_id, z.english_name AS zodiac_english_name, z.indian_name AS zodiac_indian_name,
         n.id AS nakshatram_id, n.name AS nakshatram_name,
         rl.id AS religion_id, rl.name AS religion_name,
         mt.id AS mother_tongue_id, mt.name AS mother_tongue_name,
         fh.id AS food_habit_id, fh.name AS food_habit_name,
         COALESCE((SELECT json_agg(json_build_object('id', l.id, 'name', l.name) ORDER BY l.sort_order, l.name)
                     FROM profile_languages pl JOIN languages l ON l.id = pl.language_id
                    WHERE pl.profile_id = p.id), '[]'::json) AS known_languages,
         COALESCE((SELECT json_agg(json_build_object(
                              'level', el.level,
                              'details', el.details,
                              'country', CASE WHEN ec.id IS NULL THEN NULL
                                              ELSE json_build_object('id', ec.id, 'name', ec.name) END)
                            ORDER BY array_position(${EDUCATION_LEVEL_ORDER}, el.level))
                     FROM profile_education_levels el LEFT JOIN countries ec ON ec.id = el.country_id
                    WHERE el.profile_id = p.id), '[]'::json) AS education_levels
    FROM profiles p
    JOIN communities c ON c.id = p.community_id
    LEFT JOIN subcastes sc ON sc.id = p.subcaste_id
    LEFT JOIN educations e ON e.id = p.education_id
    LEFT JOIN professions pr ON pr.id = p.profession_id
    LEFT JOIN occupation_types ot ON ot.id = p.occupation_type_id
    LEFT JOIN marital_statuses ms ON ms.id = p.marital_status_id
    LEFT JOIN complexions cx ON cx.id = p.complexion_id
    LEFT JOIN countries co ON co.id = p.nri_country_id
    LEFT JOIN countries wc ON wc.id = p.work_country_id
    LEFT JOIN countries na ON na.id = p.nationality_id
    LEFT JOIN countries bc ON bc.id = p.birth_country_id
    LEFT JOIN zodiac_signs z ON z.id = p.zodiac_id
    LEFT JOIN nakshatrams n ON n.id = p.nakshatram_id
    LEFT JOIN religions rl ON rl.id = p.religion_id
    LEFT JOIN languages mt ON mt.id = p.mother_tongue_id
    LEFT JOIN food_habits fh ON fh.id = p.food_habit_id`;

const ref = (id, name) => (id ? { id, name } : null);

/**
 * PROTECTED ("on request") fields — CLAUDE.md rules 3/4, SPEC §3.2 / §9.8.
 * These are the API keys that are OMITTED from list rows, shares, downloads
 * and public pages. The detail routes add them only for the uploader, admins,
 * an unexpired approved contact request, or (customers) their own profile /
 * an unexpired accepted interest. Everything on the hand-written "On request"
 * sheet lives here: native place, birth place, exact work place, parents,
 * contact person, siblings, family details, property.
 */
export const PROTECTED_FIELDS = [
  'city',
  'state',
  'birth_place',
  'birth_state',
  'birth_country',
  'work_place',
  'nri_place',
  'father_name',
  'father_occupation',
  'father_phone',
  'mother_name',
  'mother_occupation',
  'mother_phone',
  'contact_name',
  'contact_phone',
  'has_siblings',
  'siblings_count',
  'siblings_details',
  'elder_sisters',
  'younger_sisters',
  'elder_brothers',
  'younger_brothers',
  'family_details',
  'property_share',
  'property_details',
];

/** Copies the protected values off a DB row — call ONLY once access is granted. */
export function protectedFields(row) {
  const hasSiblings = row.has_siblings ?? null;
  return {
    city: row.city ?? null,
    state: row.state ?? null,
    birth_place: row.birth_place ?? null,
    birth_state: row.birth_state ?? null,
    birth_country: ref(row.birth_country_id, row.birth_country_name),
    work_place: row.work_place ?? null,
    nri_place: row.is_nri ? row.nri_place ?? null : null,
    father_name: row.father_name ?? null,
    father_occupation: row.father_occupation ?? null,
    father_phone: row.father_phone ?? null,
    mother_name: row.mother_name ?? null,
    mother_occupation: row.mother_occupation ?? null,
    mother_phone: row.mother_phone ?? null,
    contact_name: row.contact_name ?? null,
    contact_phone: row.contact_phone ?? null,
    // Siblings: null = not recorded, false = none, true = see counts/details.
    has_siblings: hasSiblings,
    siblings_count: hasSiblings === null ? null : hasSiblings ? row.siblings_count ?? null : 0,
    siblings_details: hasSiblings ? row.siblings_details ?? null : null,
    elder_sisters: hasSiblings ? row.elder_sisters ?? null : hasSiblings === false ? 0 : null,
    younger_sisters: hasSiblings ? row.younger_sisters ?? null : hasSiblings === false ? 0 : null,
    elder_brothers: hasSiblings ? row.elder_brothers ?? null : hasSiblings === false ? 0 : null,
    younger_brothers: hasSiblings ? row.younger_brothers ?? null : hasSiblings === false ? 0 : null,
    family_details: row.family_details ?? null,
    property_share: row.property_share ?? null,
    property_details: row.property_details ?? null,
  };
}

/**
 * Shapes a profile row for the API — PUBLIC ("appearance profile") fields only.
 * Protected fields and uploader identity are added by the caller only when
 * allowed — never here. `agent` or `customer` (Gandharva) marks ownership.
 *
 * Privacy toggles (SPEC §9.18 D): the details the family switched off are
 * masked (lib/privacy.js mask()) unless the viewer is on the owner side — the
 * uploader, an admin, the owning customer — or the caller passes
 * `reveal: true` after establishing access (an approved contact request, an
 * accepted interest). `masked_fields` lists what was withheld.
 *
 * `share: true` shapes the object for something that LEAVES the app (WhatsApp
 * text, photo card, PDF): always masked, never the owner-side keys — whoever
 * shares it (SPEC §3.3, CLAUDE.md rule 3).
 *
 * The owner side also gets the profile ID (SPEC §9.18 C — it carries the
 * agent's code, so nobody else may see it), the family's privacy setting and
 * the community audience (§9.18 E).
 */
export function profilePublic(
  row,
  { photos = [], agent, customer, reveal = false, share = false, photoUrlBase = '/api/photos' } = {},
) {
  const isMine = agent ? row.uploaded_by === agent.id : customer ? row.customer_id === customer.id : false;
  const ownerSide = !share && (isMine || Boolean(agent?.is_admin));
  const out = {
    id: row.id,
    full_name: row.full_name,
    gender: row.gender,
    dob: row.dob,
    age: row.age,
    height_cm: row.height_cm,
    weight_kg: row.weight_kg,
    complexion: ref(row.complexion_id, row.complexion_name),
    religion: ref(row.religion_id, row.religion_name),
    community: ref(row.community_id, row.community_name),
    subcaste: ref(row.subcaste_id, row.subcaste_name),
    gothram: row.gothram,
    mother_tongue: ref(row.mother_tongue_id, row.mother_tongue_name),
    known_languages: Array.isArray(row.known_languages) ? row.known_languages : [],
    food_habit: ref(row.food_habit_id, row.food_habit_name),
    nationality: ref(row.nationality_id, row.nationality_name),
    education: ref(row.education_id, row.education_name),
    education_details: row.education_details,
    education_levels: Array.isArray(row.education_levels) ? row.education_levels : [],
    profession: ref(row.profession_id, row.profession_name),
    profession_details: row.profession_details,
    occupation_type: ref(row.occupation_type_id, row.occupation_type_name),
    // Public coarse location: the country of work (India for most) and the NRI country.
    work_country: ref(row.work_country_id, row.work_country_name),
    marital_status: ref(row.marital_status_id, row.marital_status_name),
    zodiac: row.zodiac_id
      ? { id: row.zodiac_id, english_name: row.zodiac_english_name, indian_name: row.zodiac_indian_name }
      : null,
    nakshatram: ref(row.nakshatram_id, row.nakshatram_name),
    // Horoscope birth time — public like star/rasi. Birth PLACE is protected.
    birth_time: row.birth_time ?? null, // "HH:MM" (24h) or null
    income_text: row.income_text,
    other_income: row.other_income ?? null,
    is_nri: Boolean(row.is_nri),
    nri_country: row.is_nri ? ref(row.nri_country_id, row.nri_country_name) : null,
    about: row.about,
    status: row.status,
    is_customer_profile: row.customer_id != null,
    created_at: row.created_at,
    updated_at: row.updated_at,
    is_mine: isMine,
    photos: photos.map((p) => photoPublic(p, photoUrlBase)),
  };
  out.masked_fields = ownerSide || (reveal && !share) ? [] : mask(out, row.hidden_fields);
  // After mask(): a family that hides its other photos leaves only the main one.
  out.primary_photo_url = out.photos.length ? out.photos[0].url : null;
  if (ownerSide) {
    out.profile_code = row.profile_code ?? null;
    out.hidden_fields = [...hiddenSet(row.hidden_fields)];
    out.audience_all = Boolean(row.audience_all);
    out.audience_communities = Array.isArray(row.audience_communities) ? row.audience_communities : [];
  }
  return out;
}

/**
 * Of `profileIds`, the ones this agent currently has contact access to (an
 * approved, unexpired request) — list rows of those come unmasked like their
 * detail page does (SPEC §9.18 D).
 */
export async function agentAccessIds(agentId, profileIds) {
  if (!profileIds.length) return new Set();
  const rows = await many(
    `SELECT DISTINCT profile_id FROM contact_requests
      WHERE requester_id = $1 AND profile_id = ANY($2::int[])
        AND status = 'approved' AND expires_at > now()`,
    [agentId, profileIds],
  );
  return new Set(rows.map((r) => r.profile_id));
}

/**
 * Compact summary for embedding in client / interest rows (SPEC §9.4, §9.5).
 * Public fields only. `photoUrlBase` lets customer routes point at their own
 * photo endpoint.
 *
 * `reveal` (SPEC §9.18 D): pass true only for a viewer with access to this
 * profile — its own agent, an admin, the owning customer, or someone holding
 * a live approval. Everyone else gets the neutral name and no hidden
 * community / subcaste (`name_hidden` says the name was replaced). The
 * default is the safe one. `code` adds the profile ID — owner side ONLY
 * (§9.18 C: it carries the agent's code).
 */
export function profileSummary(
  row,
  { photoId = null, photoUrlBase = '/api/photos', reveal = false, code = false } = {},
) {
  if (!row) return null;
  const hidden = reveal ? new Set() : hiddenSet(row.hidden_fields);
  return {
    id: row.id,
    full_name: displayName(row, reveal),
    name_hidden: hidden.has('name'),
    gender: row.gender,
    age: row.age ?? null,
    community: hidden.has('community') ? null : ref(row.community_id, row.community_name),
    subcaste: hidden.has('subcaste') ? null : ref(row.subcaste_id, row.subcaste_name),
    status: row.status,
    photo_url: photoId ? `${photoUrlBase}/${photoId}` : null,
    ...(code ? { profile_code: row.profile_code ?? null } : {}),
  };
}

export function photoPublic(photo, photoUrlBase = '/api/photos') {
  return {
    id: photo.id,
    url: `${photoUrlBase}/${photo.id}`,
    is_primary: photo.is_primary,
    sort_order: photo.sort_order,
  };
}

/** Photos for a set of profile ids, grouped by profile id, primary first. */
export async function photosByProfile(profileIds) {
  const map = new Map(profileIds.map((id) => [id, []]));
  if (!profileIds.length) return map;
  const rows = await many(
    `SELECT id, profile_id, file_path, is_primary, sort_order
       FROM profile_photos
      WHERE profile_id = ANY($1::int[])
      ORDER BY is_primary DESC, sort_order, id`,
    [profileIds],
  );
  for (const r of rows) map.get(r.profile_id)?.push(r);
  return map;
}

/**
 * Replaces the set of languages a profile knows (profile_languages).
 * `client` is a pg client inside a transaction, or the pool.
 */
export async function setKnownLanguages(client, profileId, languageIds) {
  await client.query('DELETE FROM profile_languages WHERE profile_id = $1', [profileId]);
  if (languageIds.length) {
    await client.query(
      `INSERT INTO profile_languages (profile_id, language_id)
       SELECT $1, unnest($2::int[]) ON CONFLICT DO NOTHING`,
      [profileId, languageIds],
    );
  }
}

/**
 * Replaces the education-by-level rows (SPEC §9.7). `levels` is an array of
 * {level, details, country_id} already validated by the route.
 */
export async function setEducationLevels(client, profileId, levels) {
  await client.query('DELETE FROM profile_education_levels WHERE profile_id = $1', [profileId]);
  for (const lv of levels) {
    await client.query(
      `INSERT INTO profile_education_levels (profile_id, level, details, country_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (profile_id, level) DO UPDATE SET details = EXCLUDED.details, country_id = EXCLUDED.country_id`,
      [profileId, lv.level, lv.details ?? null, lv.country_id ?? null],
    );
  }
}

/**
 * Contact access state for (profile, agent) — SPEC §3.2.
 * 'granted' for the uploader, admins, or an approved request that hasn't expired.
 */
export async function contactAccess(profile, agent) {
  if (agent.is_admin || profile.uploaded_by === agent.id) {
    return { access: 'granted', expires_at: null, request_status: 'owner', request_id: null };
  }
  const rows = await many(
    `SELECT id, status, expires_at,
            (status = 'approved' AND expires_at > now()) AS live
       FROM contact_requests
      WHERE profile_id = $1 AND requester_id = $2
      ORDER BY requested_at DESC
      LIMIT 1`,
    [profile.id, agent.id],
  );
  const latest = rows[0];
  if (!latest) return { access: 'none', expires_at: null, request_status: null, request_id: null };

  // Expiry is decided by the database clock, never Node's.
  const live = Boolean(latest.live);
  const access = live ? 'granted' : latest.status === 'pending' ? 'pending' : 'none';
  return {
    access,
    expires_at: live ? latest.expires_at : null,
    // Raw status lets the app distinguish "rejected" from "never requested".
    request_status: latest.status === 'approved' && !live ? 'expired' : latest.status,
    request_id: latest.id,
  };
}

/**
 * Access state for (profile, customer) — SPEC §9.4 / §9.9. Their own profile
 * is always granted; another profile only while their interest is accepted
 * and unexpired. Returns the interest row summary too.
 */
export async function customerAccess(profile, customer) {
  if (profile.customer_id === customer.id) {
    return { access: 'granted', expires_at: null, interest: null };
  }
  const row = await one(
    `SELECT id, status, note, created_at, decided_at, access_expires_at,
            (status = 'accepted' AND access_expires_at > now()) AS live,
            CASE WHEN status = 'accepted' AND access_expires_at > now()
                 THEN CEIL(EXTRACT(EPOCH FROM (access_expires_at - now())) / 86400)::int END AS days_left
       FROM customer_interests
      WHERE profile_id = $1 AND customer_id = $2`,
    [profile.id, customer.id],
  );
  if (!row) return { access: 'none', expires_at: null, interest: null };
  const live = Boolean(row.live);
  return {
    access: live ? 'granted' : 'none',
    expires_at: live ? row.access_expires_at : null,
    interest: {
      id: row.id,
      // An accepted interest whose window lapsed reads as 'expired' for the app.
      status: row.status === 'accepted' && !live ? 'expired' : row.status,
      note: row.note,
      created_at: row.created_at,
      decided_at: row.decided_at,
      access_expires_at: live ? row.access_expires_at : null,
      days_left: row.days_left ?? null,
    },
  };
}

/**
 * Hold state for (profile, agent) — the hold workflow (SPEC §2 hold_requests).
 * `request_status` is the caller's latest request on this profile;
 * `held_by` / `pending_count` are for the uploader and admins only.
 */
export async function holdState(profile, agent) {
  const mine = await one(
    `SELECT id, status FROM hold_requests
      WHERE profile_id = $1 AND requester_id = $2
      ORDER BY requested_at DESC, id DESC LIMIT 1`,
    [profile.id, agent.id],
  );
  const out = { request_status: mine?.status ?? null, request_id: mine?.id ?? null };
  if (!(agent.is_admin || profile.uploaded_by === agent.id)) return out;

  const active = await one(
    `SELECT h.id, h.requested_at, h.decided_at, a.id AS agent_id, a.full_name, a.agency_name
       FROM hold_requests h JOIN agents a ON a.id = h.requester_id
      WHERE h.profile_id = $1 AND h.status = 'approved'
      ORDER BY h.decided_at DESC NULLS LAST, h.id DESC LIMIT 1`,
    [profile.id],
  );
  out.held_by = active
    ? {
        hold_request_id: active.id,
        id: active.agent_id,
        full_name: active.full_name,
        agency_name: active.agency_name,
        since: active.decided_at ?? active.requested_at,
      }
    : null;
  const pending = await one(
    `SELECT count(*)::int AS n FROM hold_requests WHERE profile_id = $1 AND status = 'pending'`,
    [profile.id],
  );
  out.pending_count = pending.n;
  return out;
}

/**
 * Hard-deletes a profile and its photo files. Rows in contact_requests,
 * hold_requests, share_tokens, share_logs, shortlists, profile_languages,
 * profile_education_levels and customer_interests cascade away; the owning
 * customer (if any) keeps their account with customer_id set to null.
 * Callers check permission first (uploader or admin — SPEC §4).
 */
export async function deleteProfile(id) {
  const photos = await many('SELECT file_path FROM profile_photos WHERE profile_id = $1', [id]);
  await query('DELETE FROM profiles WHERE id = $1', [id]);
  // Disk clean-up after the row is gone; a missing file is not an error.
  for (const p of photos) await deleteStoredPhoto(p.file_path);
}
