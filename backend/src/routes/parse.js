import { Router } from 'express';
import multer from 'multer';
import rateLimit from 'express-rate-limit';
import { config } from '../lib/config.js';
import { many } from '../lib/db.js';
import { ApiError, asyncHandler, badRequest } from '../lib/errors.js';
import { extractProfile, isAiConfigured, mapAiError } from '../lib/ai.js';
import { EDUCATION_LEVELS } from '../lib/profiles.js';

// Mounted at /api/profiles — AI import (SPEC §4, POST /profiles/parse).
export const parseRouter = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    if (/^(application\/pdf|image\/(jpe?g|png|webp)|text\/plain)$/i.test(file.mimetype)) {
      return cb(null, true);
    }
    cb(badRequest('unsupported_file', 'Upload a PDF, a photo (JPG/PNG), or a text file'));
  },
});

// Each parse costs real money; cap it per agent.
const perAgentLimit = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 30,
  keyGenerator: (req) => String(req.agent.id),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too_many_parses', message: 'Limit of 30 AI imports per hour reached' },
});

// GET /api/profiles/parse/status — lets the app show or hide the button.
parseRouter.get('/parse/status', (_req, res) => {
  res.json({ enabled: isAiConfigured(), model: isAiConfigured() ? config.claudeModel : null });
});

// ---------------------------------------------------------------- matching

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');

/**
 * Best master row for free text, or null. Exact normalised match wins, then
 * "master contains value" (B.Tech → "B.Tech / B.E."), then the reverse.
 */
function matchMaster(value, rows, namesOf = (r) => [r.name]) {
  const q = norm(value);
  if (q.length < 2) return null;
  let best = null;
  let bestScore = 0;
  for (const row of rows) {
    for (const name of namesOf(row)) {
      const m = norm(name);
      if (!m) continue;
      let score = 0;
      if (m === q) score = 3;
      else if (q.length >= 3 && m.includes(q)) score = 2;
      else if (m.length >= 3 && q.includes(m)) score = 1;
      if (score > bestScore) {
        best = row;
        bestScore = score;
      }
    }
  }
  return best;
}

const clean = (s, max) => {
  const v = String(s ?? '').replace(/\s+/g, ' ').trim();
  return v ? v.slice(0, max) : null;
};

function validDob(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s ?? '')) return false;
  const d = new Date(`${s}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return false;
  const years = (Date.now() - d.getTime()) / (365.2425 * 24 * 3600 * 1000);
  return years >= 18 && years <= 100;
}

// POST /api/profiles/parse  (multipart: file | text)
parseRouter.post(
  '/parse',
  perAgentLimit,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    // Validate the input before checking availability, so a bad request is a
    // 400 whether or not the feature is switched on.
    const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
    if (!req.file && !text) throw badRequest('nothing_to_parse', 'Attach a file or paste the bio-data text');
    if (!isAiConfigured()) {
      throw new ApiError(503, 'ai_not_configured', 'AI import is not set up on this server');
    }

    let extracted;
    try {
      extracted = await extractProfile({
        text: text || undefined,
        file: req.file ? { buffer: req.file.buffer, mimetype: req.file.mimetype } : undefined,
      });
    } catch (e) {
      throw mapAiError(e);
    }
    const d = extracted.data;
    if (!d.is_biodata) {
      throw new ApiError(422, 'not_a_biodata', 'This does not look like a matrimony bio-data');
    }

    const [
      communities, subcastes, educations, professions, maritals, complexions, countries, zodiacs, nakshatrams,
      religions, languages, foodHabits, occupationTypes,
    ] = await Promise.all([
      many('SELECT id, name FROM communities WHERE active = TRUE'),
      many('SELECT id, community_id, name FROM subcastes WHERE active = TRUE'),
      many('SELECT id, name FROM educations WHERE active = TRUE'),
      many('SELECT id, name FROM professions WHERE active = TRUE'),
      many('SELECT id, name FROM marital_statuses WHERE active = TRUE'),
      many('SELECT id, name FROM complexions WHERE active = TRUE'),
      // India first (sort 0) so "Indian" resolves to it before anything else.
      many('SELECT id, name FROM countries WHERE active = TRUE ORDER BY sort_order'),
      many('SELECT id, english_name, indian_name FROM zodiac_signs'),
      many('SELECT id, name FROM nakshatrams'),
      many('SELECT id, name FROM religions WHERE active = TRUE ORDER BY sort_order'),
      many('SELECT id, name FROM languages WHERE active = TRUE ORDER BY sort_order'),
      // Sorted so "veg" resolves to Vegetarian before Non-Vegetarian.
      many('SELECT id, name FROM food_habits WHERE active = TRUE ORDER BY sort_order'),
      many('SELECT id, name FROM occupation_types WHERE active = TRUE ORDER BY sort_order'),
    ]);

    const draft = {};
    const unmatched = {};
    const warnings = [];

    draft.full_name = clean(d.full_name, 120);
    draft.gender = d.gender ?? null;

    if (d.dob && validDob(d.dob)) draft.dob = d.dob;
    else if (d.age_years) warnings.push(`Age is given as ${d.age_years} but there is no full date of birth — pick it manually.`);
    else warnings.push('No date of birth found — pick it manually.');

    if (Number.isInteger(d.height_cm) && d.height_cm >= 100 && d.height_cm <= 250) draft.height_cm = d.height_cm;
    if (Number.isInteger(d.weight_kg) && d.weight_kg >= 25 && d.weight_kg <= 250) draft.weight_kg = d.weight_kg;

    // Community drives subcaste scoping and the agent's permission to upload.
    const community = d.community ? matchMaster(d.community, communities) : null;
    if (community) {
      draft.community_id = community.id;
      if (!req.agent.is_admin && !req.agent.community_ids.includes(community.id)) {
        warnings.push(`The bio-data says "${d.community}" (${community.name}), which is not one of your communities.`);
      }
    } else if (d.community) {
      unmatched.community = clean(d.community, 80);
    }

    if (d.subcaste) {
      const sc = community ? matchMaster(d.subcaste, subcastes.filter((s) => s.community_id === community.id)) : null;
      if (sc) draft.subcaste_id = sc.id;
      else if (community) draft.subcaste_name = clean(d.subcaste, 80); // created on save
      else unmatched.subcaste = clean(d.subcaste, 80);
    }

    const pick = (value, rows, key, max = 80, namesOf) => {
      if (!value) return;
      const hit = matchMaster(value, rows, namesOf);
      if (hit) draft[`${key}_id`] = hit.id;
      else unmatched[key] = clean(value, max);
    };
    pick(d.education, educations, 'education');
    pick(d.profession, professions, 'profession');
    pick(d.marital_status, maritals, 'marital_status');
    pick(d.complexion, complexions, 'complexion', 40);
    pick(d.zodiac, zodiacs, 'zodiac', 40, (z) => [z.english_name, z.indian_name]);
    pick(d.nakshatram, nakshatrams, 'nakshatram', 40);
    pick(d.religion, religions, 'religion', 40);
    pick(d.mother_tongue, languages, 'mother_tongue', 40);
    pick(d.food_habit, foodHabits, 'food_habit', 40);
    // Registration-form fields (SPEC §9.7): nationality / work / birth country
    // all resolve against the countries master, the job kind against occupation_types.
    pick(d.nationality, countries, 'nationality', 40);
    pick(d.occupation_type, occupationTypes, 'occupation_type', 40);
    pick(d.work_country, countries, 'work_country', 40);
    pick(d.birth_country, countries, 'birth_country', 40);

    // Education by stage: one entry per level, its country resolved to the
    // master (an unknown country is reported and dropped, the level is kept).
    if (Array.isArray(d.education_levels) && d.education_levels.length) {
      const levels = [];
      const seen = new Set();
      const missCountries = [];
      for (const lv of d.education_levels) {
        if (!lv || !EDUCATION_LEVELS.includes(lv.level) || seen.has(lv.level)) continue;
        seen.add(lv.level);
        const entry = { level: lv.level, details: clean(lv.details, 300) };
        if (lv.country) {
          const country = matchMaster(lv.country, countries);
          if (country) entry.country_id = country.id;
          else missCountries.push(`${lv.level}: ${clean(lv.country, 40)}`);
        }
        levels.push(entry);
      }
      if (levels.length) draft.education_levels = levels;
      if (missCountries.length) unmatched.education_levels_country = missCountries.join(', ');
    }

    // Known languages: each entry resolves to the languages master or is reported.
    if (Array.isArray(d.known_languages) && d.known_languages.length) {
      const ids = [];
      const miss = [];
      for (const name of d.known_languages) {
        const hit = matchMaster(name, languages);
        if (hit) ids.push(hit.id);
        else if (clean(name, 40)) miss.push(clean(name, 40));
      }
      if (ids.length) draft.known_language_ids = [...new Set(ids)];
      if (miss.length) unmatched.known_languages = miss.join(', ');
    }

    // Siblings: tri-state; counts/details only when there are some.
    const smallCount = (n) => (Number.isInteger(n) && n >= 0 && n <= 20 ? n : undefined);
    if (typeof d.has_siblings === 'boolean') {
      draft.has_siblings = d.has_siblings;
      if (d.has_siblings) {
        draft.siblings_count = smallCount(d.siblings_count);
        draft.siblings_details = clean(d.siblings_details, 2000);
        draft.elder_sisters = smallCount(d.elder_sisters);
        draft.younger_sisters = smallCount(d.younger_sisters);
        draft.elder_brothers = smallCount(d.elder_brothers);
        draft.younger_brothers = smallCount(d.younger_brothers);
      }
    }

    // Horoscope birth time must already be HH:MM (24h); anything else is shown
    // as a hint so the agent can type it. The birth PLACE is protected (§9.8)
    // and lands in the draft's on-request section like the native place.
    if (d.birth_time && /^([01]\d|2[0-3]):[0-5]\d$/.test(d.birth_time)) draft.birth_time = d.birth_time;
    else if (d.birth_time) unmatched.birth_time = clean(d.birth_time, 20);
    draft.birth_place = clean(d.birth_place, 120);
    draft.birth_state = clean(d.birth_state, 80);

    draft.gothram = clean(d.gothram, 80);
    draft.education_details = clean(d.education_details, 500);
    draft.profession_details = clean(d.profession_details, 500);
    draft.work_place = clean(d.work_place, 120);
    draft.income_text = clean(d.income_text, 80);
    draft.other_income = clean(d.other_income, 80);

    // NRI: country resolves to the master; an unknown country is reported, not guessed.
    draft.is_nri = d.is_nri === true;
    if (draft.is_nri) {
      const country = d.nri_country ? matchMaster(d.nri_country, countries) : null;
      if (country) draft.nri_country_id = country.id;
      else if (d.nri_country) unmatched.nri_country = clean(d.nri_country, 80);
      draft.nri_place = clean(d.nri_place, 120);
    }

    // Native place + parents are PROTECTED fields; they land in the draft's
    // protected section exactly like the contact person.
    draft.city = clean(d.city, 80);
    draft.state = clean(d.state, 80);
    draft.about = clean(d.about, 4000);
    draft.family_details = clean(d.family_details, 4000);
    draft.property_share = clean(d.property_share, 500);
    draft.property_details = clean(d.property_details, 4000);
    draft.father_name = clean(d.father_name, 120);
    draft.father_occupation = clean(d.father_occupation, 120);
    draft.mother_name = clean(d.mother_name, 120);
    draft.mother_occupation = clean(d.mother_occupation, 120);
    draft.contact_name = clean(d.contact_name, 120);

    const phone = (raw, key) => {
      const digits = String(raw ?? '').replace(/\D/g, '');
      if (digits.length >= 10) draft[key] = digits.slice(-10);
      else if (raw) unmatched[key] = clean(raw, 20);
    };
    phone(d.contact_phone, 'contact_phone');
    phone(d.father_phone, 'father_phone');
    phone(d.mother_phone, 'mother_phone');

    for (const k of Object.keys(draft)) if (draft[k] === null || draft[k] === undefined) delete draft[k];

    res.json({
      draft,
      unmatched,
      warnings,
      ai: { model: extracted.model, ...extracted.usage },
    });
  }),
);
