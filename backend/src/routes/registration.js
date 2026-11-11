// The agent's public registration form — SPEC §9.3-B. Mounted at /r (no auth).
//   GET  /r/:token  → the paper registration form as a mobile-friendly HTML
//                     page (Wedbook Matrimony styling, agent's name in the
//                     header) in four steps: Personal details, Professional
//                     details, Horoscope, Family & contact (SPEC §9.18 F).
//                     Without JavaScript the four sections simply stack.
//   POST /r/:token  → creates the customer (pending, source 'form', no OTP yet)
//                     AND their profile (hidden, uploaded_by = the agent,
//                     photos stored) in one transaction; thank-you page.
//                     Rate-limited 20/hour/IP (the POST only — §9.3-B).
// Unknown / rotated token or an inactive agent → 404 page. A number that is
// already a customer → 409 page ("open Wedbook Matrimony and log in").
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
  :root { color-scheme: light; --wine:#540729; --wine-deep:#3A0419; --gold:#C8A056; --gold-light:#F5E7C8;
          --cream:#FFF8EE; --ink:#2A1518; --muted:#7A6A64; --rule:#EFE0CA; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--cream); color:var(--ink);
         font-family: Poppins, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  .brand { background: linear-gradient(135deg, #7A1B45 0%, var(--wine) 55%, var(--wine-deep) 100%);
           color:#fff; padding: 16px 20px 18px; border-bottom: 3px solid var(--gold); }
  .brand .in { max-width: 640px; margin: 0 auto; }
  .brand .logo { display:flex; align-items:center; gap:10px; }
  .brand .logo svg { flex:none; }
  .brand .name { font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.5rem; letter-spacing:.02em; color:var(--gold); line-height:1; }
  .brand .tag { font-size:.62rem; letter-spacing:.2em; text-transform:uppercase; opacity:.8; margin-top:5px; }
  .brand .agent { margin-top:12px; font-size:.86rem; opacity:.95; }
  .brand .agent b { font-weight:600; }
  .wrap { max-width: 640px; margin: 0 auto; padding: 16px 16px 40px; }
  h1 { margin: 8px 0 4px; font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.5rem; color:var(--wine); line-height:1.2; }
  .lead { margin: 0 0 14px; color:var(--muted); font-size:.9rem; line-height:1.5; }
  fieldset.card { background:#fff; border:1px solid var(--rule); border-radius:16px; padding: 10px 16px 16px; margin: 0 0 14px;
                  box-shadow: 0 6px 20px rgba(58,4,25,.05); min-width:0; }
  legend { font-size:.72rem; letter-spacing:.16em; text-transform:uppercase; color:var(--wine); font-weight:600; padding: 0 6px; }
  .grid { display:grid; grid-template-columns: 1fr 1fr; gap: 10px 12px; }
  .f { display:flex; flex-direction:column; gap:4px; grid-column: 1 / -1; font-size:.84rem; color:var(--muted); min-width:0; }
  .f.half { grid-column: auto; }
  .f b { color:#B4453F; }
  .f small { font-size:.74rem; color:var(--muted); }
  input, select, textarea { font: inherit; font-size:16px; color:var(--ink); padding: 10px 12px; width:100%;
                            border:1px solid #E3CFB2; border-radius:10px; background:#FFFDF8; }
  textarea { resize: vertical; min-height: 72px; }
  input:focus, select:focus, textarea:focus { outline: 2px solid var(--gold); border-color: var(--gold); }
  input[type=file] { padding: 8px; background:#fff; }
  .btn { display:block; width:100%; background:var(--wine); color:var(--gold-light); border:0; border-radius:14px;
         padding: 14px; font: 600 1rem Poppins, system-ui, sans-serif; margin-top: 4px; cursor:pointer; }
  .btn:active { background: var(--wine-deep); }
  .alert { background:#FDECEC; border:1px solid #F3B9B9; color:#7A1F1F; border-radius:12px; padding: 12px 14px; margin: 0 0 14px; font-size:.9rem; }
  .alert ul { margin: 6px 0 0; padding-left: 18px; }
  .notice { background:#fff; border-radius:18px; padding: 26px 20px; text-align:center; box-shadow: 0 6px 20px rgba(58,4,25,.06); }
  .notice .icon { width:64px; height:64px; border-radius:50%; margin: 0 auto 12px; display:grid; place-items:center;
                  background: var(--gold-light); color: var(--wine); font-size:1.8rem; }
  .notice p { line-height:1.6; margin: 8px 0; }
  .notice .steps { text-align:left; margin: 14px auto 0; padding-left: 20px; max-width: 420px; line-height:1.7; }
  .notice a { color: var(--wine); font-weight:600; }
  .foot { text-align:center; color:var(--muted); font-size:.76rem; margin-top: 22px; line-height:1.6; }
  .foot .by { letter-spacing:.08em; text-transform:uppercase; font-size:.68rem; opacity:.75; margin-top:6px; }
  /* ---- the four steps (SPEC §9.18 F). Plain page: sections stack. With
     JavaScript: one step at a time, a stepper on top, Back / Next below. */
  [hidden] { display: none !important; }
  .stepper { list-style:none; display:flex; gap:6px; margin: 0 0 14px; padding:0; }
  .stepper li { flex:1; min-width:0; text-align:center; padding: 8px 4px 9px; border-radius:12px; background:#fff;
                border:1px solid var(--rule); color:var(--muted); font-size:.68rem; line-height:1.25; cursor:pointer; }
  .stepper li b { display:block; width:24px; height:24px; line-height:24px; border-radius:50%; margin: 0 auto 4px;
                  background:var(--gold-light); color:var(--wine); font-size:.8rem; }
  .stepper li.on { border-color:var(--wine); color:var(--wine); font-weight:600; }
  .stepper li.on b { background:var(--wine); color:var(--gold-light); }
  .stepper li.done b { background:var(--gold); color:#fff; }
  .step > h2 { margin: 18px 0 10px; font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.15rem; color:var(--wine); }
  .step > h2 small { display:block; font: 500 .68rem Poppins, system-ui, sans-serif; letter-spacing:.16em; text-transform:uppercase; color:var(--gold); margin-bottom:2px; }
  form.js .step > h2 { margin-top: 4px; }
  .actions { display:flex; gap:10px; margin-top: 6px; }
  .actions .btn { margin-top:0; }
  .btn.ghost { background:#fff; color:var(--wine); border:1.5px solid var(--wine); flex: 0 0 34%; }
  .onreq { font-size:.76rem; color:var(--muted); margin: -4px 0 12px; }
  @media (max-width: 420px) { .grid { grid-template-columns: 1fr; } .f.half { grid-column: 1 / -1; } }
`;

/**
 * Progressive enhancement for the four steps: shows one step at a time,
 * validates the required fields of a step before moving on, and jumps to the
 * step that holds the first invalid field on submit. Without it the form is
 * one long page with a single submit button — still complete.
 */
const STEP_SCRIPT = `
(function () {
  var form = document.querySelector('form.reg');
  var nav = document.querySelector('.stepper');
  if (!form || !nav || !form.querySelectorAll) return;
  var steps = [].slice.call(form.querySelectorAll('.step'));
  var pills = [].slice.call(nav.querySelectorAll('li'));
  var back = form.querySelector('.back');
  var next = form.querySelector('.next');
  var submit = form.querySelector('.submit');
  var cur = 0;
  function fields(i) { return [].slice.call(steps[i].querySelectorAll('input,select,textarea')); }
  function firstInvalid(i) {
    var els = fields(i);
    for (var k = 0; k < els.length; k++) if (els[k].checkValidity && !els[k].checkValidity()) return els[k];
    return null;
  }
  function show(i, keepScroll) {
    cur = i;
    steps.forEach(function (st, k) { st.hidden = k !== i; });
    pills.forEach(function (p, k) { p.className = k === i ? 'on' : k < i ? 'done' : ''; });
    back.hidden = i === 0;
    next.hidden = i === steps.length - 1;
    submit.hidden = i !== steps.length - 1;
    if (!keepScroll) window.scrollTo(0, 0);
  }
  function check(i) {
    var bad = firstInvalid(i);
    if (!bad) return true;
    if (bad.reportValidity) bad.reportValidity(); else bad.focus();
    return false;
  }
  form.className += ' js';
  nav.hidden = false;
  next.addEventListener('click', function () { if (check(cur)) show(cur + 1); });
  back.addEventListener('click', function () { show(cur - 1); });
  pills.forEach(function (p, k) {
    p.addEventListener('click', function () { if (k <= cur || check(cur)) show(k); });
  });
  form.addEventListener('submit', function (e) {
    for (var i = 0; i < steps.length; i++) {
      if (firstInvalid(i)) { e.preventDefault(); show(i); check(i); return; }
    }
  });
  show(0, true);
})();
`;

/** The two interlocked gold rings of the Wedbook logo, drawn inline (no image request). */
const RINGS = `<svg width="44" height="28" viewBox="0 0 44 28" aria-hidden="true">
  <circle cx="14" cy="14" r="11" fill="none" stroke="#C8A056" stroke-width="3"/>
  <circle cx="30" cy="14" r="11" fill="none" stroke="#C8A056" stroke-width="3"/>
</svg>`;

/** The Wedbook Matrimony page shell (noindex; Poppins / Playfair like the share page). */
function page({ title, agent, body, script = '' }) {
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
<meta name="theme-color" content="#540729">
<title>${esc(title)} — Wedbook Matrimony</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=Poppins:wght@400;500;600&display=swap" rel="stylesheet">
<style>${CSS}</style>
</head><body>
<header class="brand"><div class="in">
  <div class="logo">${RINGS}<div><div class="name">Wedbook</div><div class="tag">Matrimony</div></div></div>
  ${agentLine}
</div></header>
<main class="wrap">
${body}
<footer class="foot">
  Your details are shared only with your agent. Contact details stay private until you approve a match.
  <div class="by">Wedbook Matrimony</div>
</footer>
</main>
${script ? `<script>${script}</script>` : ''}
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
  nakshatram_id: 'Star (nakshatram)',
  zodiac_id: 'Rasi',
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
  const onRequest = '<p class="onreq">Shared with other families only after you approve them.</p>';

  // The four steps of SPEC §9.18 F — the same four as in the apps.
  const steps = [
    [
      'Personal details',
      card(
        'Your login',
        input(v, 'phone', 'Your mobile number', {
          type: 'tel',
          required: true,
          inputmode: 'numeric',
          placeholder: '10-digit mobile number',
          maxlength: 15,
          hint: 'This becomes your Wedbook Matrimony login. Use the number you will install the app on.',
        }),
      ) +
        card(
          'About you',
          input(v, 'full_name', 'Name', { required: true }) +
            select(v, 'gender', 'Gender', [{ value: 'bride', label: 'Bride (female)' }, { value: 'groom', label: 'Groom (male)' }], { required: true, half: true }) +
            input(v, 'dob', 'Date of birth', { type: 'date', required: true, half: true }) +
            select(v, 'marital_status_id', 'Marital status', master(masters.marital_statuses), { half: true }) +
            select(v, 'nationality_id', 'Nationality', countries, { half: true }),
        ) +
        card(
          'Community',
          select(v, 'religion_id', 'Religion', master(masters.religions), { half: true }) +
            select(v, 'community_id', 'Community', master(masters.communities), { required: true, half: true }) +
            input(v, 'subcaste_name', 'Subcaste', { half: true, maxlength: 80 }) +
            select(v, 'mother_tongue_id', 'Mother tongue', master(masters.languages), { half: true }),
        ) +
        card(
          'Appearance & habits',
          select(v, 'height_ft', 'Height (feet)', range(4, 7, ' ft'), { half: true, placeholder: 'Feet' }) +
            select(v, 'height_in', 'Height (inches)', range(0, 11, ' in'), { half: true, placeholder: 'Inches' }) +
            input(v, 'weight_kg', 'Weight (kg)', { type: 'number', half: true, inputmode: 'numeric', maxlength: 3 }) +
            select(v, 'complexion_id', 'Complexion', master(masters.complexions), { half: true }) +
            select(v, 'food_habit_id', 'Food habit', master(masters.food_habits)) +
            textarea(v, 'about', 'About yourself / expectations', { rows: 4 }),
        ) +
        card(
          'Photos',
          `<label class="f"><span>Photos</span>
  <input type="file" name="photos" accept="image/*" multiple>
  <small>Up to ${FORM_MAX_PHOTOS} photos (JPG or PNG). If the page comes back with an error, attach them again.</small></label>`,
        ),
    ],
    [
      'Professional details',
      card(
        'Educational qualification',
        educationRows +
          select(v, 'education_id', 'Highest qualification', master(masters.educations)) +
          textarea(v, 'education_details', 'Other education details', { rows: 2, maxlength: 500 }),
      ) +
        card(
          'Occupation',
          select(v, 'occupation_type_id', 'Occupation type', master(masters.occupation_types), { half: true }) +
            select(v, 'profession_id', 'Occupation', master(masters.professions), { half: true }) +
            textarea(v, 'profession_details', 'Other professional details', { rows: 2, maxlength: 500, placeholder: 'Employer, designation…' }) +
            input(v, 'income_text', 'Salary / income', { half: true, maxlength: 80, placeholder: 'e.g. 8 LPA' }) +
            input(v, 'other_income', 'Other income', { half: true, maxlength: 80 }) +
            select(v, 'work_country_id', 'Work country', countries, { half: true }) +
            input(v, 'work_place', 'Work place', { half: true, hint: 'City / town — shared only on request' }),
        ),
    ],
    [
      'Horoscope',
      card(
        'Star & rasi',
        select(v, 'nakshatram_id', 'Star (nakshatram)', master(masters.nakshatrams), { half: true }) +
          select(
            v,
            'zodiac_id',
            'Rasi',
            masters.zodiac_signs.map((z) => ({ value: z.id, label: `${z.indian_name} (${z.english_name})` })),
            { half: true },
          ) +
          input(v, 'gothram', 'Gothram', { half: true, maxlength: 80 }) +
          input(v, 'birth_time', 'Birth time', { type: 'time', half: true }),
      ) +
        card(
          'Birth place',
          input(v, 'birth_place', 'Birth place', { half: true, hint: 'Shared only on request' }) +
            input(v, 'birth_state', 'State', { half: true, maxlength: 80 }) +
            select(v, 'birth_country_id', 'Country', countries, { half: true }),
        ),
    ],
    [
      'Family & contact',
      onRequest +
        card(
          'Parents',
          input(v, 'father_name', "Father's name", { half: true }) +
            input(v, 'father_occupation', "Father's occupation", { half: true }) +
            input(v, 'father_phone', "Father's phone no.", { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }) +
            input(v, 'mother_name', "Mother's name", { half: true }) +
            input(v, 'mother_occupation', "Mother's occupation", { half: true }) +
            input(v, 'mother_phone', "Mother's phone no.", { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }),
        ) +
        card(
          'Siblings & family',
          input(v, 'elder_sisters', 'Elder sisters', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
            input(v, 'younger_sisters', 'Younger sisters', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
            input(v, 'elder_brothers', 'Elder brothers', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
            input(v, 'younger_brothers', 'Younger brothers', { type: 'number', half: true, inputmode: 'numeric', maxlength: 2 }) +
            textarea(v, 'family_details', 'Family other details', { rows: 3 }),
        ) +
        card(
          'Property',
          input(v, 'property_share', 'Property share', { maxlength: 500 }) +
            textarea(v, 'property_details', 'Property details', { rows: 2 }),
        ) +
        card(
          'Native place & contact person',
          input(v, 'city', 'Native place — city', { half: true, maxlength: 80 }) +
            input(v, 'state', 'Native place — state', { half: true, maxlength: 80 }) +
            input(v, 'contact_name', 'Contact person', { half: true }) +
            input(v, 'contact_phone', 'Contact person phone no.', { type: 'tel', half: true, inputmode: 'numeric', maxlength: 20 }),
        ),
    ],
  ];

  const stepper = `<ol class="stepper" hidden>${steps
    .map(([title], i) => `<li><b>${i + 1}</b>${esc(title)}</li>`)
    .join('')}</ol>`;
  const sections = steps
    .map(
      ([title, inner], i) =>
        `<section class="step"><h2><small>Step ${i + 1} of ${steps.length}</small>${esc(title)}</h2>${inner}</section>`,
    )
    .join('\n');

  const body = `
<h1>Registration form</h1>
<p class="lead">Four short steps. Fill in as much as you can — only the basics are required. Your agent will review the details before your profile goes live.</p>
${banner}
${stepper}
<form class="reg" method="post" enctype="multipart/form-data" novalidate>
${sections}
<div class="actions">
  <button class="btn ghost back" type="button" hidden>Back</button>
  <button class="btn next" type="button" hidden>Next</button>
  <button class="btn submit" type="submit">Submit registration</button>
</div>
</form>`;
  return page({ title: 'Registration form', agent, body, script: STEP_SCRIPT });
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
<p><b>+91 ${esc(phone)}</b> already has a Wedbook Matrimony account.</p>
<p>Open the <b>Wedbook Matrimony</b> app and log in with this number — you will get a one-time code by SMS. Your profile is under <b>My profile</b> there.</p>
<p>Questions? Call ${esc(agent.full_name)} on <a href="tel:+91${esc(agent.phone)}">+91 ${esc(agent.phone)}</a>.</p></div>`,
  });

const tooManyPage = () =>
  page({
    title: 'Too many submissions',
    agent: null,
    body: `<div class="notice"><div class="icon">!</div>
<h1>Too many submissions from this network</h1>
<p>Please try again in an hour, or ask your marriage bureau agent to register you from the Wedbook Agent app.</p></div>`,
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
  <li>Install the <b>Wedbook Matrimony</b> app.</li>
  <li>Log in with <b>+91 ${esc(phone)}</b> — you will receive a one-time code by SMS.</li>
  <li>Pay the <b>₹${esc(String(config.payments.profileFeeInr))}</b> registration fee in the app (My profile) — your profile becomes visible to others only after that.</li>
  <li>Once ${esc(agent.full_name)} approves you, browse profiles and mark the ones you like.</li>
</ol>
<p>Questions? Call <a href="tel:+91${esc(agent.phone)}">+91 ${esc(agent.phone)}</a>.</p></div>`,
  });

// ---------------------------------------------------------------- form → profile body

const DIRECT_KEYS = [
  'full_name', 'gender', 'marital_status_id', 'dob', 'birth_time',
  'nakshatram_id', 'zodiac_id',
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
 * form none of them had even submitted. A browser gets a Wedbook page, not JSON.
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
        // Wedbook Matrimony login verifies the number (phone_verified_at stays null).
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
