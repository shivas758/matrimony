// The agent's public registration form — SPEC §9.3-B. Mounted at /r (no auth).
//   GET  /r/:token  → the paper registration form as a mobile-friendly HTML
//                     page (Gandharva styling, agent's name in the header).
//   POST /r/:token  → creates the customer (pending, source 'form', no OTP yet)
//                     AND their profile (hidden, uploaded_by = the agent,
//                     photos stored) in one transaction; thank-you page.
//                     Rate-limited 20/hour/IP (the POST only — §9.3-B).
// Unknown / rotated token or an inactive agent → 404 page. A number that is
// already a customer → 409 page ("open Gandharva and log in").
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { one, tx } from '../lib/db.js';
import { ApiError, asyncHandler } from '../lib/errors.js';
import { parse, phoneSchema } from '../lib/validate.js';
import { escapeXml } from '../lib/photos.js';
import { EDUCATION_LEVELS } from '../lib/profiles.js';
import { createProfileRecord, prepareProfileBody, upload } from '../lib/profileWrite.js';
import { findCustomerByPhone } from '../lib/customers.js';
import { config } from '../lib/config.js';
import { loadMasters } from './masters.js';

export const registrationRouter = Router();

const esc = escapeXml;
const FORM_MAX_PHOTOS = 4;

/** The ACTIVE agent behind a registration token, or null. */
async function loadAgentByToken(token) {
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(String(token || ''))) return null;
  const agent = await one(
    'SELECT id, full_name, agency_name, phone, city, status FROM agents WHERE registration_token = $1',
    [token],
  );
  return agent && agent.status === 'active' ? agent : null;
}

// ---------------------------------------------------------------- page shell

const CSS = `
  :root { color-scheme: light; --maroon:#4A1A29; --maroon-deep:#2E0F18; --rose:#D4A28C; --rose-light:#F0D6CC;
          --blush:#FAF3F0; --ink:#2B1A1F; --muted:#7A6469; --rule:#EBD9D2; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--blush); color:var(--ink);
         font-family: Poppins, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  .brand { background: linear-gradient(135deg, #6B2A3E 0%, var(--maroon) 55%, var(--maroon-deep) 100%);
           color:#fff; padding: 16px 20px 18px; border-bottom: 3px solid var(--rose); }
  .brand .in { max-width: 640px; margin: 0 auto; }
  .brand .name { font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.5rem; color:var(--rose-light); line-height:1; }
  .brand .tag { font-size:.62rem; letter-spacing:.2em; text-transform:uppercase; opacity:.8; margin-top:5px; }
  .brand .agent { margin-top:12px; font-size:.86rem; opacity:.95; }
  .brand .agent b { font-weight:600; }
  .wrap { max-width: 640px; margin: 0 auto; padding: 16px 16px 40px; }
  h1 { margin: 8px 0 4px; font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.5rem; color:var(--maroon); line-height:1.2; }
  .lead { margin: 0 0 14px; color:var(--muted); font-size:.9rem; line-height:1.5; }
  fieldset.card { background:#fff; border:1px solid var(--rule); border-radius:16px; padding: 10px 16px 16px; margin: 0 0 14px;
                  box-shadow: 0 6px 20px rgba(46,15,24,.05); min-width:0; }
  legend { font-size:.72rem; letter-spacing:.16em; text-transform:uppercase; color:var(--maroon); font-weight:600; padding: 0 6px; }
  .grid { display:grid; grid-template-columns: 1fr 1fr; gap: 10px 12px; }
  .f { display:flex; flex-direction:column; gap:4px; grid-column: 1 / -1; font-size:.84rem; color:var(--muted); min-width:0; }
  .f.half { grid-column: auto; }
  .f b { color:#B4453F; }
  .f small { font-size:.74rem; color:var(--muted); }
  input, select, textarea { font: inherit; font-size:16px; color:var(--ink); padding: 10px 12px; width:100%;
                            border:1px solid #D9C4BC; border-radius:10px; background:#FFFDFC; }
  textarea { resize: vertical; min-height: 72px; }
  input:focus, select:focus, textarea:focus { outline: 2px solid var(--rose); border-color: var(--rose); }
  input[type=file] { padding: 8px; background:#fff; }
  .btn { display:block; width:100%; background:var(--maroon); color:var(--rose-light); border:0; border-radius:14px;
         padding: 14px; font: 600 1rem Poppins, system-ui, sans-serif; margin-top: 4px; cursor:pointer; }
  .btn:active { background: var(--maroon-deep); }
  .alert { background:#FDECEC; border:1px solid #F3B9B9; color:#7A1F1F; border-radius:12px; padding: 12px 14px; margin: 0 0 14px; font-size:.9rem; }
  .alert ul { margin: 6px 0 0; padding-left: 18px; }
  .notice { background:#fff; border-radius:18px; padding: 26px 20px; text-align:center; box-shadow: 0 6px 20px rgba(46,15,24,.06); }
  .notice .icon { width:64px; height:64px; border-radius:50%; margin: 0 auto 12px; display:grid; place-items:center;
                  background: var(--rose-light); color: var(--maroon); font-size:1.8rem; }
  .notice p { line-height:1.6; margin: 8px 0; }
  .notice .steps { text-align:left; margin: 14px auto 0; padding-left: 20px; max-width: 420px; line-height:1.7; }
  .notice a { color: var(--maroon); font-weight:600; }
  .foot { text-align:center; color:var(--muted); font-size:.76rem; margin-top: 22px; line-height:1.6; }
  .foot .by { letter-spacing:.08em; text-transform:uppercase; font-size:.68rem; opacity:.75; margin-top:6px; }
  @media (max-width: 420px) { .grid { grid-template-columns: 1fr; } .f.half { grid-column: 1 / -1; } }
`;

/** The Gandharva page shell (noindex; Poppins / Playfair like the share page). */
function page({ title, agent, body }) {
  const agentLine = agent
    ? `<div class="agent">Registering with <b>${esc(agent.full_name)}</b>${
        agent.agency_name ? ` · ${esc(agent.agency_name)}` : ''
      }${agent.city ? ` · ${esc(agent.city)}` : ''}</div>`
    : '';
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#4A1A29">
<title>${esc(title)} — Gandharva</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=Poppins:wght@400;500;600&display=swap" rel="stylesheet">
<style>${CSS}</style>
</head><body>
<header class="brand"><div class="in">
  <div class="name">Gandharva</div><div class="tag">Connecting Hearts, Creating Families</div>
  ${agentLine}
</div></header>
<main class="wrap">
${body}
<footer class="foot">
  Your details are shared only with your agent. Contact details stay private until you approve a match.
  <div class="by">Gandharva · Mediator Matrimony Partners</div>
</footer>
</main>
</body></html>`;
}

function sendPage(res, status, html) {
  res.status(status).set('X-Robots-Tag', 'noindex, nofollow').type('html').send(html);
}

// ---------------------------------------------------------------- form controls

const val = (values, name) => (values[name] === undefined || values[name] === null ? '' : String(values[name]));

function input(values, name, label, opts = {}) {
  const { type = 'text', required = false, placeholder = '', maxlength = 120, hint = '', half = false, inputmode = '' } = opts;
  return `<label class="f${half ? ' half' : ''}"><span>${esc(label)}${required ? ' <b>*</b>' : ''}</span>
  <input type="${type}" name="${name}" value="${esc(val(values, name))}"${required ? ' required' : ''}${
    placeholder ? ` placeholder="${esc(placeholder)}"` : ''
  }${maxlength ? ` maxlength="${maxlength}"` : ''}${inputmode ? ` inputmode="${inputmode}"` : ''}>${
    hint ? `<small>${esc(hint)}</small>` : ''
  }</label>`;
}

function select(values, name, label, options, opts = {}) {
  const { required = false, placeholder = 'Select', half = false, hint = '' } = opts;
  const current = val(values, name);
  const rows = options
    .map((o) => `<option value="${esc(o.value)}"${String(o.value) === current ? ' selected' : ''}>${esc(o.label)}</option>`)
    .join('');
  return `<label class="f${half ? ' half' : ''}"><span>${esc(label)}${required ? ' <b>*</b>' : ''}</span>
  <select name="${name}"${required ? ' required' : ''}><option value="">${esc(placeholder)}</option>${rows}</select>${
    hint ? `<small>${esc(hint)}</small>` : ''
  }</label>`;
}

function textarea(values, name, label, opts = {}) {
  const { rows = 3, maxlength = 4000, hint = '', placeholder = '' } = opts;
  return `<label class="f"><span>${esc(label)}</span>
  <textarea name="${name}" rows="${rows}" maxlength="${maxlength}"${placeholder ? ` placeholder="${esc(placeholder)}"` : ''}>${esc(
    val(values, name),
  )}</textarea>${hint ? `<small>${esc(hint)}</small>` : ''}</label>`;
}

const master = (rows) => rows.map((r) => ({ value: r.id, label: r.name }));
const range = (from, to, suffix = '') =>
  Array.from({ length: to - from + 1 }, (_, i) => ({ value: from + i, label: `${from + i}${suffix}` }));

const LEVEL_LABELS = {
  below_10th: 'Below 10th',
  '10th': '10th',
  intermediate: 'PUC / 10+2 / Intermediate / Diploma',
  graduation: 'Graduation',
  post_graduation: 'Post graduation',
};

/** Field labels for the error banner (body keys → what the form calls them). */
const FIELD_LABELS = {
  phone: 'Your mobile number',
  full_name: 'Full name',
  gender: 'Gender',
  marital_status_id: 'Marital status',
  dob: 'Date of birth',
  birth_time: 'Birth time',
  birth_country_id: 'Birth country',
  nationality_id: 'Nationality',
  religion_id: 'Religion',
  community_id: 'Community',
  subcaste_name: 'Subcaste',
  city: 'Native place (city)',
  state: 'Native place (state)',
  complexion_id: 'Complexion',
  mother_tongue_id: 'Mother tongue',
  height_cm: 'Height',
  weight_kg: 'Weight',
  education_levels: 'Education',
  education_details: 'Other education details',
  education_id: 'Highest qualification',
  occupation_type_id: 'Occupation type',
  profession_id: 'Occupation',
  income_text: 'Salary / income',
  work_country_id: 'Work country',
  profession_details: 'Other professional details',
  food_habit_id: 'Food habit',
  siblings_count: 'Siblings',
};
const labelFor = (field) =>
  FIELD_LABELS[field] ?? field.replace(/\.\d+.*$/, '').replace(/_id$/, '').replace(/_/g, ' ');

// ---------------------------------------------------------------- the form

function renderForm({ agent, masters, values = {}, error = null }) {
  const countries = master(masters.countries);
  const india = masters.countries.find((c) => c.name.toLowerCase() === 'india');
  // First render: India pre-selected where that is almost always right.
  const v = { ...values };
  if (!Object.keys(values).length && india) {
    v.nationality_id = india.id;
    v.birth_country_id = india.id;
    v.work_country_id = india.id;
  }

  const banner = error
    ? `<div class="alert" role="alert"><b>${esc(error.title)}</b>${
        error.items?.length ? `<ul>${error.items.map((i) => `<li>${esc(i)}</li>`).join('')}</ul>` : ''
      }</div>`
    : '';

  const educationRows = EDUCATION_LEVELS.map(
    (level) =>
      input(v, `edu_${level}`, LEVEL_LABELS[level], { half: true, placeholder: 'School / board / degree / college', maxlength: 300 }) +
      select(v, `edu_${level}_country`, 'Country', countries, { half: true, placeholder: 'Country' }),
  ).join('');

  const card = (legend, inner) => `<fieldset class="card"><legend>${esc(legend)}</legend><div class="grid">${inner}</div></fieldset>`;

  const body = `
<h1>Registration form</h1>
<p class="lead">Fill in as much as you can — only the basics are required. Your agent will review the details before your profile goes live.</p>
${banner}
<form method="post" enctype="multipart/form-data" novalidate>
${card(
  'Your login',
  input(v, 'phone', 'Your mobile number', {
    type: 'tel',
    required: true,
    inputmode: 'numeric',
    placeholder: '10-digit mobile number',
    maxlength: 15,
    hint: 'This becomes your Gandharva login. Use the number you will install the app on.',
  }),
)}
${card(
  'Basic details',
  input(v, 'full_name', 'Name', { required: true }) +
    select(v, 'gender', 'Gender', [{ value: 'bride', label: 'Bride (female)' }, { value: 'groom', label: 'Groom (male)' }], { required: true, half: true }) +
    select(v, 'marital_status_id', 'Marital status', master(masters.marital_statuses), { half: true }) +
    input(v, 'dob', 'Date of birth', { type: 'date', required: true, half: true }) +
    input(v, 'birth_time', 'Birth time', { type: 'time', half: true, hint: 'For the horoscope' }),
)}
${card(
  'Birth',
  input(v, 'birth_place', 'Birth place', { half: true }) +
    input(v, 'birth_state', 'State', { half: true, maxlength: 80 }) +
    select(v, 'birth_country_id', 'Country', countries, { half: true }) +
    select(v, 'nationality_id', 'Nationality', countries, { half: true }),
)}
${card(
  'Community',
  select(v, 'religion_id', 'Religion', master(masters.religions), { half: true }) +
    select(v, 'community_id', 'Community', master(masters.communities), { required: true, half: true }) +
    input(v, 'subcaste_name', 'Subcaste', { half: true, maxlength: 80 }) +
    input(v, 'gothram', 'Gothram', { half: true, maxlength: 80 }) +
    input(v, 'city', 'Native place — city', { half: true, maxlength: 80 }) +
    input(v, 'state', 'Native place — state', { half: true, maxlength: 80 }),
)}
${card(
  'Appearance',
  select(v, 'complexion_id', 'Complexion', master(masters.complexions), { half: true }) +
    select(v, 'mother_tongue_id', 'Mother tongue', master(masters.languages), { half: true }) +
    select(v, 'height_ft', 'Height (feet)', range(4, 7, ' ft'), { half: true, placeholder: 'Feet' }) +
    select(v, 'height_in', 'Height (inches)', range(0, 11, ' in'), { half: true, placeholder: 'Inches' }) +
    input(v, 'weight_kg', 'Weight (kg)', { type: 'number', half: true, inputmode: 'numeric', maxlength: 3 }),
)}
${card(
  'Educational qualification',
  educationRows +
    textarea(v, 'education_details', 'Other education details', { rows: 2, maxlength: 500 }) +
    select(v, 'education_id', 'Highest qualification', master(masters.educations)),
)}
${card(
  'Professional details',
  select(v, 'occupation_type_id', 'Occupation type', master(masters.occupation_types), { half: true }) +
    select(v, 'profession_id', 'Occupation', master(masters.professions), { half: true }) +
    input(v, 'income_text', 'Salary / income', { half: true, maxlength: 80, placeholder: 'e.g. 8 LPA' }) +
    input(v, 'other_income', 'Other income', { half: true, maxlength: 80 }) +
    input(v, 'work_place', 'Work place', { half: true, hint: 'City / town — shared only on request' }) +
    select(v, 'work_country_id', 'Country', countries, { half: true }) +
    textarea(v, 'profession_details', 'Other professional details', { rows: 2, maxlength: 500, placeholder: 'Employer, designation…' }),
)}
${card(
  'Family',
  input(v, 'father_name', "Father's name", { half: true }) +
    input(v, 'father_occupation', "Father's occupation", { half: true }) +
    input(v, 'father_phone', "Father's phone no.", { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }) +
    input(v, 'mother_name', "Mother's name", { half: true }) +
    input(v, 'mother_occupation', "Mother's occupation", { half: true }) +
    input(v, 'mother_phone', "Mother's phone no.", { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }) +
    input(v, 'contact_name', 'Contact person', { half: true }) +
    input(v, 'contact_phone', 'Contact person phone no.', { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }) +
    input(v, 'elder_sisters', 'Elder sisters', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
    input(v, 'younger_sisters', 'Younger sisters', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
    input(v, 'elder_brothers', 'Elder brothers', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
    input(v, 'younger_brothers', 'Younger brothers', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
    textarea(v, 'family_details', 'Family other details', { rows: 3 }),
)}
${card(
  'Property',
  input(v, 'property_share', 'Property share', { maxlength: 500 }) +
    textarea(v, 'property_details', 'Property details', { rows: 2 }),
)}
${card(
  'About',
  select(v, 'food_habit_id', 'Food habit', master(masters.food_habits)) +
    textarea(v, 'about', 'About yourself / expectations', { rows: 4 }),
)}
${card(
  'Photos',
  `<label class="f"><span>Photos</span>
  <input type="file" name="photos" accept="image/*" multiple>
  <small>Up to ${FORM_MAX_PHOTOS} photos (JPG or PNG). If the page comes back with an error, attach them again.</small></label>`,
)}
<button class="btn" type="submit">Submit registration</button>
</form>`;
  return page({ title: 'Registration form', agent, body });
}

const notFoundPage = () =>
  page({
    title: 'Link not valid',
    agent: null,
    body: `<div class="notice"><div class="icon">!</div>
<h1>This link is no longer valid</h1>
<p>The registration link may have been replaced. Please ask your marriage bureau agent for a fresh one.</p></div>`,
  });

const takenPage = (agent, phone) =>
  page({
    title: 'Already registered',
    agent,
    body: `<div class="notice"><div class="icon">✓</div>
<h1>This number is already registered</h1>
<p><b>+91 ${esc(phone)}</b> already has a Gandharva account.</p>
<p>Open the <b>Gandharva</b> app and log in with this number — you will get a one-time code by SMS. You can add up to ${esc(String(config.payments.maxCustomerProfiles))} profiles there (My profiles → Add profile).</p>
<p>Questions? Call ${esc(agent.full_name)} on <a href="tel:+91${esc(agent.phone)}">+91 ${esc(agent.phone)}</a>.</p></div>`,
  });

const tooManyPage = () =>
  page({
    title: 'Too many submissions',
    agent: null,
    body: `<div class="notice"><div class="icon">!</div>
<h1>Too many submissions from this network</h1>
<p>Please try again in an hour, or ask your marriage bureau agent to register you from the Mediator app.</p></div>`,
  });

const thanksPage = (agent, name, phone) =>
  page({
    title: 'Thank you',
    agent,
    body: `<div class="notice"><div class="icon">✓</div>
<h1>Thank you, ${esc(name)}!</h1>
<p>Your registration has reached <b>${esc(agent.full_name)}</b>${
      agent.agency_name ? ` (${esc(agent.agency_name)})` : ''
    }. They will check your details and approve your account.</p>
<ol class="steps">
  <li>Install the <b>Gandharva</b> app.</li>
  <li>Log in with <b>+91 ${esc(phone)}</b> — you will receive a one-time code by SMS.</li>
  <li>Pay the <b>₹${esc(String(config.payments.profileFeeInr))}</b> registration fee in the app (My profiles) — your profile becomes visible to others only after that.</li>
  <li>Once ${esc(agent.full_name)} approves you, browse profiles and mark the ones you like.</li>
</ol>
<p>Questions? Call <a href="tel:+91${esc(agent.phone)}">+91 ${esc(agent.phone)}</a>.</p></div>`,
  });

// ---------------------------------------------------------------- form → profile body

const DIRECT_KEYS = [
  'full_name', 'gender', 'marital_status_id', 'dob', 'birth_time',
  'birth_place', 'birth_state', 'birth_country_id', 'nationality_id',
  'religion_id', 'community_id', 'subcaste_name', 'gothram', 'city', 'state',
  'complexion_id', 'mother_tongue_id', 'weight_kg',
  'education_details', 'education_id',
  'occupation_type_id', 'profession_id', 'income_text', 'other_income', 'work_place', 'work_country_id', 'profession_details',
  'father_name', 'father_occupation', 'father_phone', 'mother_name', 'mother_occupation', 'mother_phone',
  'contact_name', 'contact_phone', 'family_details', 'property_share', 'property_details',
  'food_habit_id', 'about',
];
const SIBLING_KEYS = ['elder_sisters', 'younger_sisters', 'elder_brothers', 'younger_brothers'];

/** Only the first value of each field, as a string (multer/urlencoded may give arrays). */
function stringValues(body) {
  const out = {};
  for (const [k, raw] of Object.entries(body || {})) {
    const first = Array.isArray(raw) ? raw[0] : raw;
    if (first === undefined || first === null) continue;
    out[k] = String(first);
  }
  return out;
}

/**
 * Translates the form's fields into a profile body for prepareProfileBody():
 * feet + inches → height_cm, the education table → education_levels[], the
 * four sibling counts → has_siblings / siblings_count + counts.
 */
function bodyFromForm(v) {
  const body = {};
  for (const k of DIRECT_KEYS) if (v[k] !== undefined && v[k].trim() !== '') body[k] = v[k].trim();

  if (v.height_ft) {
    const ft = Number(v.height_ft);
    const inch = Number(v.height_in || 0);
    body.height_cm = Math.round((ft * 12 + inch) * 2.54);
  }

  const levels = [];
  for (const level of EDUCATION_LEVELS) {
    const details = (v[`edu_${level}`] || '').trim();
    const country = (v[`edu_${level}_country`] || '').trim();
    if (details || country) levels.push({ level, details: details || null, country_id: country ? Number(country) : null });
  }
  if (levels.length) body.education_levels = levels;

  const given = SIBLING_KEYS.filter((k) => v[k] !== undefined && v[k].trim() !== '');
  if (given.length) {
    let total = 0;
    for (const k of SIBLING_KEYS) {
      const n = v[k] && v[k].trim() !== '' ? Number(v[k]) : 0;
      body[k] = n;
      total += Number.isFinite(n) ? n : 0;
    }
    body.siblings_count = total;
    body.has_siblings = total > 0;
  }
  return body;
}

/** Turns a 400 ApiError into the banner {title, items[]}. */
function describeError(e) {
  if (e.code === 'validation_failed' && e.details?.length) {
    return {
      title: 'Please check these details',
      items: e.details.map((d) => `${labelFor(d.field)}: ${d.message}`),
    };
  }
  return { title: e.message || 'Something went wrong — please try again', items: [] };
}

const phoneFormSchema = z.object({ phone: phoneSchema });

/** Multer for the form's photos; errors become a banner instead of JSON. */
function formPhotos(req, res, next) {
  upload.array('photos', FORM_MAX_PHOTOS)(req, res, (err) => {
    if (err) {
      req.photoError =
        err.code === 'LIMIT_FILE_SIZE'
          ? 'Each photo must be under 10 MB'
          : err.code === 'LIMIT_UNEXPECTED_FILE' || err.code === 'LIMIT_FILE_COUNT'
            ? `You can attach up to ${FORM_MAX_PHOTOS} photos`
            : err.message || 'The photos could not be read';
    }
    next();
  });
}

// ---------------------------------------------------------------- routes

// GET /r/:token
registrationRouter.get(
  '/:token',
  asyncHandler(async (req, res) => {
    const agent = await loadAgentByToken(req.params.token);
    if (!agent) return sendPage(res, 404, notFoundPage());
    const masters = await loadMasters();
    sendPage(res, 200, renderForm({ agent, masters }));
  }),
);

/**
 * Submissions only, 20/hour/IP (SPEC §9.3-B) — it stores photos. GET /r/:token
 * is deliberately NOT limited: behind carrier-grade NAT hundreds of families
 * share one address, and a limit on page views would lock them all out of a
 * form none of them had even submitted. A browser gets a Gandharva page, not JSON.
 */
const submitLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (_req, res) => sendPage(res, 429, tooManyPage()),
});

// POST /r/:token (multipart) — customer + hidden profile in one transaction.
registrationRouter.post(
  '/:token',
  submitLimiter,
  formPhotos,
  asyncHandler(async (req, res) => {
    const agent = await loadAgentByToken(req.params.token);
    if (!agent) return sendPage(res, 404, notFoundPage());
    const masters = await loadMasters();
    const values = stringValues(req.body);
    const fail = (error) => sendPage(res, 400, renderForm({ agent, masters, values, error }));

    if (req.photoError) return fail({ title: req.photoError, items: [] });

    let phone;
    let body;
    try {
      ({ phone } = parse(phoneFormSchema, { phone: values.phone ?? '' }));
      body = await prepareProfileBody(bodyFromForm(values), { multipart: true });
    } catch (e) {
      if (e instanceof ApiError && e.status === 400) return fail(describeError(e));
      throw e;
    }

    if (await findCustomerByPhone(phone)) return sendPage(res, 409, takenPage(agent, phone));

    try {
      await tx(async (client) => {
        // No OTP on the web form: the agent vets the person; the first
        // Gandharva login verifies the number (phone_verified_at stays null).
        const { rows } = await client.query(
          `INSERT INTO customers (full_name, phone, agent_id, status, source, phone_verified_at)
           VALUES ($1, $2, $3, 'pending', 'form', NULL) RETURNING id`,
          [body.full_name, phone, agent.id],
        );
        await createProfileRecord({
          uploadedBy: agent.id,
          customerId: rows[0].id,
          body,
          files: req.files || [],
          status: 'hidden',
          client,
        });
      });
    } catch (e) {
      // The same number submitted twice at once (customers.phone unique).
      if (e.code === '23505') return sendPage(res, 409, takenPage(agent, phone));
      if (e instanceof ApiError && e.status === 400) return fail(describeError(e));
      throw e;
    }
    sendPage(res, 200, thanksPage(agent, body.full_name, phone));
  }),
);
